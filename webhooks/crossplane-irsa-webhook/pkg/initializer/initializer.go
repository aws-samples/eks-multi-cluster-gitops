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

func GetAccountIdAndClusterOIDC(c context.Context, api DescribeClusterAPI, clusterName string) (string, string) {
	klog.Infof("Querying cluster %s", clusterName)
	input := &eks.DescribeClusterInput{
		Name: &clusterName,
	}
	output, err := api.DescribeCluster(c, input)
	if err != nil {
		klog.Fatalf("Error calling DescribeCluster: %v", err.Error())
	}

	accountId := extractAccountId(output)

	oidcEndpoint := extractClusterOIDC(output)

	klog.Infof("Resolved account ID: %s, cluster OIDC: %s", accountId, oidcEndpoint)
	return accountId, oidcEndpoint
}

func extractClusterOIDC(output *eks.DescribeClusterOutput) string {
	oidcEndpoint := *output.Cluster.Identity.Oidc.Issuer
	return oidcEndpoint[8:]
}

func extractAccountId(output *eks.DescribeClusterOutput) string {
	arn := *output.Cluster.Arn
	matches := accountIdRegex.FindStringSubmatch(arn)
	accountId := matches[accountIdMatchIndex]
	return accountId
}

// InitializerOpt is an option type for setting up an Initializer
type InitializerOpt func(*Initializer)

// WithRegion set the AWS region
func WithRegion(r string) InitializerOpt {
	return func(i *Initializer) { i.Region = r }
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
	Region      string
	AccountID   string
	ClusterName string
	ClusterOIDC string
}

func (i *Initializer) Initialize() {
	var cfg aws.Config
	var err error
	if len(i.Region) == 0 {
		klog.Info("Loading AWS config with default region lookup")
		cfg, err = config.LoadDefaultConfig(context.TODO())
	} else {
		klog.Infof("Loading AWS config with region: %s", i.Region)
		cfg, err = config.LoadDefaultConfig(context.TODO(), config.WithRegion(i.Region))
	}
	if err != nil {
		klog.Fatalf("Error loading AWS config: %v", err.Error())
	}

	eks := eks.NewFromConfig(cfg)
	i.AccountID, i.ClusterOIDC = GetAccountIdAndClusterOIDC(context.TODO(), eks, i.ClusterName)
}
