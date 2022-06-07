package main

import (
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	goflag "flag"
	"fmt"
	"net/http"
	"os"
	"time"

	"github.com/prometheus/client_golang/prometheus/promhttp"
	flag "github.com/spf13/pflag"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/clientcmd"
	"k8s.io/klog"
	"sigs.k8s.io/controller-runtime/pkg/certwatcher"
	"sigs.k8s.io/controller-runtime/pkg/manager/signals"

	"github.com/aws-samples/multi-cluster-gitops/crossplane-irsa-webhook/pkg/cert"
	"github.com/aws-samples/multi-cluster-gitops/crossplane-irsa-webhook/pkg/handler"
	"github.com/aws-samples/multi-cluster-gitops/crossplane-irsa-webhook/pkg/initializer"
	ver "github.com/aws-samples/multi-cluster-gitops/crossplane-irsa-webhook/pkg/version"
)

func main() {
	port := flag.Int("port", 443, "Port to listen on")
	metricsPort := flag.Int("metrics-port", 9999, "Port to listen on for metrics and healthz (http)")

	// out-of-cluster kubeconfig / TLS options
	kubeconfig := flag.String("kubeconfig", "", "(out-of-cluster) Absolute path to the API server kubeconfig file")
	apiURL := flag.String("kube-api", "", "(out-of-cluster) The url to the API server")
	tlsKeyFile := flag.String("tls-key", "/etc/webhook/certs/tls.key", "(out-of-cluster) TLS key file path")
	tlsCertFile := flag.String("tls-cert", "/etc/webhook/certs/tls.crt", "(out-of-cluster) TLS certificate file path")

	// in-cluster TLS options
	inCluster := flag.Bool("in-cluster", true, "Use in-cluster authentication and certificate request API")
	serviceName := flag.String("service-name", "crossplane-irsa-webhook", "(in-cluster) The service name fronting this webhook")
	namespaceName := flag.String("namespace", "crossplane-system", "(in-cluster) The namespace name this webhook, the TLS secret, and configmap resides in")
	tlsSecret := flag.String("tls-secret", "crossplane-irsa-webhook", "(in-cluster) The secret name for storing the TLS serving cert")

	awsRegion := flag.String("aws-region", "eu-west-1", "The AWS region to configure for the AWS API calls")
	clusterName := flag.String("cluster-name", "", "Name of the Amazon EKS cluster to introspect for the OIDC provider")

	version := flag.Bool("version", false, "Display the version and exit")

	klog.InitFlags(goflag.CommandLine)
	// Add klog CommandLine flags to pflag CommandLine
	goflag.CommandLine.VisitAll(func(f *goflag.Flag) {
		flag.CommandLine.AddFlag(flag.PFlagFromGoFlag(f))
	})
	flag.Parse()

	// trick goflag.CommandLine into thinking it was called.
	// klog complains if its not been parsed
	_ = goflag.CommandLine.Parse([]string{})

	if *version {
		fmt.Println(ver.Info())
		os.Exit(0)
	}

	klog.Info(ver.Info())

	config, err := clientcmd.BuildConfigFromFlags(*apiURL, *kubeconfig)
	if err != nil {
		klog.Fatalf("Error creating config: %v", err.Error())
	}

	config.QPS = 50
	config.Burst = 50

	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		klog.Fatalf("Error creating clientset: %v", err.Error())
	}

	initializer := initializer.NewInitializer(
		initializer.WithAwsRegion(*awsRegion),
		initializer.WithClusterName(*clusterName),
	)

	initializer.Initialize()

	mod := handler.NewModifier(
		handler.WithRegion(*awsRegion),
		handler.WithAccountID(initializer.AccountID),
		handler.WithClusterName(*clusterName),
		handler.WithOidcProvider(initializer.OidcProvider),
	)

	addr := fmt.Sprintf(":%d", *port)
	metricsAddr := fmt.Sprintf(":%d", *metricsPort)
	mux := http.NewServeMux()

	baseHandler := handler.Apply(
		http.HandlerFunc(mod.Handle),
		handler.InstrumentRoute(),
		handler.Logging(),
	)
	mux.Handle("/mutate", baseHandler)

	metricsMux := http.NewServeMux()
	metricsMux.Handle("/metrics", promhttp.Handler())
	metricsMux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "ok")
	})

	// setup signal handler to be passed to certwatcher and http server
	signalHandlerCtx := signals.SetupSignalHandler()
	tlsConfig := &tls.Config{}

	if *inCluster {
		csr := &x509.CertificateRequest{
			Subject: pkix.Name{CommonName: fmt.Sprintf("%s.%s.svc", *serviceName, *namespaceName)},
			DNSNames: []string{
				fmt.Sprint(*serviceName),
				fmt.Sprintf("%s.%s", *serviceName, *namespaceName),
				fmt.Sprintf("%s.%s.svc", *serviceName, *namespaceName),
				fmt.Sprintf("%s.%s.svc.cluster.local", *serviceName, *namespaceName),
			},
			/*
				// TODO: SANIPs for service IP, but not pod IP
				//IPAddresses: nil,
			*/
		}

		certManager, err := cert.NewServerCertificateManager(
			clientset,
			*namespaceName,
			*tlsSecret,
			csr,
		)
		if err != nil {
			klog.Fatalf("failed to initialize certificate manager: %v", err)
		}
		certManager.Start()
		defer certManager.Stop()

		tlsConfig.GetCertificate = func(_ *tls.ClientHelloInfo) (*tls.Certificate, error) {
			certificate := certManager.Current()
			if certificate == nil {
				return nil, fmt.Errorf("no serving certificate available for the webhook, is the CSR approved?")
			}
			return certificate, nil
		}
	} else {
		watcher, err := certwatcher.New(*tlsCertFile, *tlsKeyFile)
		if err != nil {
			klog.Fatalf("Error initializing certwatcher: %q", err)
		}

		go func() {
			if err := watcher.Start(signalHandlerCtx); err != nil {
				klog.Fatalf("Error starting certwatcher: %q", err)
			}
		}()

		tlsConfig.GetCertificate = watcher.GetCertificate
	}

	klog.Info("Creating server")
	server := &http.Server{
		Addr:      addr,
		Handler:   mux,
		TLSConfig: tlsConfig,
	}

	handler.ShutdownFromContext(signalHandlerCtx, server, time.Duration(10)*time.Second)

	metricsServer := &http.Server{
		Addr:    metricsAddr,
		Handler: metricsMux,
	}

	go func() {
		klog.Infof("Listening on %s", addr)
		if err := server.ListenAndServeTLS("", ""); err != http.ErrServerClosed {
			klog.Fatalf("Error listening: %q", err)
		}
	}()

	klog.Infof("Listening on %s for metrics and healthz", metricsAddr)
	if err := metricsServer.ListenAndServe(); err != http.ErrServerClosed {
		klog.Fatalf("Error listening: %q", err)
	}
	klog.Info("Graceflully closed")
}
