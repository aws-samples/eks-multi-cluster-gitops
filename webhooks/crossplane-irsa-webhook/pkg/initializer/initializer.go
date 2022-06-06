package initializer

import (
	"context"
	"regexp"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/eks"

	"k8s.io/klog"
)

var (
	accountIdRegex      = regexp.MustCompile(`^arn:aws:eks:[^:]+:(?P<AccountId>\d{12}):cluster/.+$`)
	accountIdMatchIndex = accountIdRegex.SubexpIndex("AccountId")
)

type DescribeClusterAPI interface {
	DescribeCluster(ctx context.Context,
		params *eks.DescribeClusterInput,
		optFns ...func(*eks.Options)) (*eks.DescribeClusterOutput, error)
}

func introspectCluster(c context.Context, api DescribeClusterAPI, clusterName string) *eks.DescribeClusterOutput {
	klog.Infof("Querying cluster %s", clusterName)
	input := &eks.DescribeClusterInput{
		Name: &clusterName,
	}
	output, err := api.DescribeCluster(c, input)
	if err != nil {
		klog.Fatalf("Error calling DescribeCluster: %v", err.Error())
	}

	return output
}

func extractOidcProvider(output *eks.DescribeClusterOutput) string {
	oidcProvider := *output.Cluster.Identity.Oidc.Issuer
	return oidcProvider[8:]
}

func extractAccountId(output *eks.DescribeClusterOutput) string {
	arn := *output.Cluster.Arn
	matches := accountIdRegex.FindStringSubmatch(arn)
	accountId := matches[accountIdMatchIndex]
	return accountId
}

// InitializerOpt is an option type for setting up an Initializer
type InitializerOpt func(*Initializer)

// WithAwsRegion set the AWS region
func WithAwsRegion(r string) InitializerOpt {
	return func(i *Initializer) { i.AwsRegion = r }
}

// WithClusterName sets the cluster name
func WithClusterName(cn string) InitializerOpt {
	return func(i *Initializer) { i.ClusterName = cn }
}

// NewInitializer returns a Initializer with default values
func NewInitializer(opts ...InitializerOpt) *Initializer {
	initializer := &Initializer{}

	for _, opt := range opts {
		opt(initializer)
	}

	return initializer
}

type Initializer struct {
	AwsRegion    string
	AccountID    string
	ClusterName  string
	OidcProvider string
}

func (i *Initializer) Initialize() {
	var cfg aws.Config
	var err error
	if len(i.AwsRegion) == 0 {
		klog.Info("Loading AWS config with default region lookup")
		cfg, err = config.LoadDefaultConfig(context.TODO())
	} else {
		klog.Infof("Loading AWS config with region: %s", i.AwsRegion)
		cfg, err = config.LoadDefaultConfig(context.TODO(), config.WithRegion(i.AwsRegion))
	}
	if err != nil {
		klog.Fatalf("Error loading AWS config: %v", err.Error())
	}

	eks := eks.NewFromConfig(cfg)

	output := introspectCluster(context.TODO(), eks, i.ClusterName)
	i.AccountID = extractAccountId(output)
	i.OidcProvider = extractOidcProvider(output)

	klog.Infoln("Resolved values")
	klog.Infof("  account ID: %s", i.AccountID)
	klog.Infof("  OIDC provider: %s", i.OidcProvider)
}
