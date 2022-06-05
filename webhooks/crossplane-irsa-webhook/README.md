# Crossplane IRSA Webhook

This MutatingWebhook replaces placeholders in Role trust relationship and ServiceAccount IRSA annotation
to help setup IRSA for workloads deployed using gitops.

## Placeholder replacements
The webhook recognizes the following placeholders for replacement.

| Placeholder     | Alternate Form | Replacements   |
|-----------------|----------------|----------------|
| `${ACCOUNT_ID}`   | `$ACCOUNT_ID`    | Account ID of the AWS account in which the EKS cluster is deployed. The initializer invokes `DescribeCluster` API action of AWS EKS service and extracts the account ID from the returned ARN of the cluster. |
| `${CLUSTER_OIDC}` | `$CLUSTER_OIDC`  | The OIDC endpoint of the EKS cluster in which the webhook is deployed. The initializer invokes `DescribeCluster` API action of AWS EKS service to retrieve the cluster OIDC endpoint. |

The webhook needs an IAM identity (user or role) with the following IAM permission policy to make `eks:DescribeCluster` call.

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "eks:DescribeCluster"
            ],
            "Resource": [
                "arn:aws:eks:${AWS_REGION}:${ACCOUNT_ID}:cluster/${CLUSTER_NAME}"
            ]
        }
    ]
}
```
## Local build to generate platform binaries

```bash
cd ~/environment/multi-cluster-gitops/webhooks/crossplane-irsa-webhook
make -f ./Makefile install
```

## Test coverage

```bash
cd ~/environment/multi-cluster-gitops/webhooks/crossplane-irsa-webhook
make -f ./Makefile test
```

## Build image and push to repository

The `Makefile` uses variables to locate the coordinates of the image repository.

| Name | Default | Description |
|------|---------|-------------|
| `REGISTRY_ID` | `012345678901` | AWS Account ID of the ECR registry. Override the default value by setting an environment variable with the same name and value set to the AWS account id of your account. |
| `IMAGE_NAME` | `multi-cluster-gitops/crossplane-irsa-webhook` | Namespaced image name. Create the repository before executing the build. |
| `REGION` | `eu-west-1` | AWS region where the ECR repository is created. |



```bash
cd ~/environment/multi-cluster-gitops/webhooks/crossplane-irsa-webhook
make -f ./Makefile push
```

## Command line arguments

```bash
--add_dir_header                   If true, adds the file directory to the header
--alsologtostderr                  log to standard error as well as files
--cluster-name string              Name of the cluster to introspect for the OIDC endpoint
--in-cluster                       Use in-cluster authentication and certificate request API (default true)
--kube-api string                  (out-of-cluster) The url to the API server
--kubeconfig string                (out-of-cluster) Absolute path to the API server kubeconfig file
--log_backtrace_at traceLocation   when logging hits line file:N, emit a stack trace (default :0)
--log_dir string                   If non-empty, write log files in this directory
--log_file string                  If non-empty, use this log file
--log_file_max_size uint           Defines the maximum size a log file can grow to. Unit is megabytes. If the value is 0, the maximum file size is unlimited. (default 1800)
--logtostderr                      log to standard error instead of files (default true)
--metrics-port int                 Port to listen on for metrics and healthz (http) (default 9999)
--namespace string                 (in-cluster) The namespace name this webhook, the TLS secret, and configmap resides in (default "crossplane-system")
--port int                         Port to listen on (default 443)
--region string                    The AWS region to configure for the AWS API calls
--service-name string              (in-cluster) The service name fronting this webhook (default "crossplane-irsa-webhook")
--skip_headers                     If true, avoid header prefixes in the log messages
--skip_log_headers                 If true, avoid headers when opening log files
--stderrthreshold severity         logs at or above this threshold go to stderr (default 2)
--tls-cert string                  (out-of-cluster) TLS certificate file path (default "/etc/webhook/certs/tls.crt")
--tls-key string                   (out-of-cluster) TLS key file path (default "/etc/webhook/certs/tls.key")
--tls-secret string                (in-cluster) The secret name for storing the TLS serving cert (default "crossplane-irsa-webhook")
-v, --v Level                          number for the log level verbosity
--version                          Display the version and exit
--vmodule moduleSpec               comma-separated list of pattern=N settings for file-filtered logging
```

### Arguments required for cluster introspection

| Name |
|------|
| `--region` |
| `--cluster-name` |