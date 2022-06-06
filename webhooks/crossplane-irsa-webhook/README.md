# Crossplane IRSA Webhook

This MutatingWebhook replaces placeholders in Role trust relationship and ServiceAccount IRSA annotation
to help setup IRSA for workloads deployed using gitops.

## Prerequisites

### `cert-manager`
The webhook deployment requires TLS for the webserver. TLS setup requires a private key and a certificate signed by a CA trusted by the API server. The sample [deployment manifest](./deploy/deployment-base.yaml) depends on `cert-manager` to provision a self signed certificate.

### IAM identity with permission to introspect EKS cluster
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

### Network access to AWS EKS API
By default the initializer routine introspects the EKS cluster by invoking `eks:DescribeCluster` with the `cluster-name` provided as a bootstrap argument. The network configuration for the cluster should allow HTTPS calls to EKS API from within the cluster.

***Note:*** This will not work in private cluster setups as EKS does not provide VPC endpoints as of this writing. As an enhancement launch arguments may be added in the future to allow cluster provisioners to supply `--account-id` and `--cluster-oidc` values as boostrap arguments to allow deployment in private clusters.

## Placeholder replacements
The webhook recognizes the following placeholders for replacement.

| Placeholder     | Alternate Form | Replacements   |
|-----------------|----------------|----------------|
| `${ACCOUNT_ID}`   | `$ACCOUNT_ID`    | Account ID of the AWS account in which the EKS cluster is deployed. The initializer invokes `eks:DescribeCluster` API action  and extracts the account ID from the returned ARN of the cluster. |
| `${OIDC_PROVIDER}` | `$OIDC_PROVIDER`  | The OIDC provider for the EKS cluster in which the webhook is deployed. The initializer invokes `eks:DescribeCluster` API action to retrieve the cluster OIDC endpoint. |

### Example for `Role`
Given:
  - Account id is `012345678901`
  - EKS cluster OIDC provider is `oidc.eks.eu-west-1.amazonaws.com/id/XXXXXXC756AECD797B338FAA4A4D`
When:
  - `Role` creation request is submitted with `assumeRolePolicyDocument` as
  
```yaml
---
apiVersion: iam.aws.crossplane.io/v1beta1
kind: Role
metadata:
  name: my-sample-irsa-role
  labels:
    type: my-sample-irsa-role
spec:
  forProvider:
    assumeRolePolicyDocument: |
        {
          "Version": "2012-10-17",
          "Statement": [
            {
              "Effect": "Allow",
              "Principal": {
                "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
              },
              "Action": "sts:AssumeRoleWithWebIdentity",
              "Condition": {
                "StringEquals": {
                  "${OIDC_PROVIDER}:aud": "sts.amazonaws.com",
                  "${OIDC_PROVIDER}:sub": "system:serviceaccount:my-namespace:my-service-account"
                }
              }
            }
          ]
        }
  providerConfigRef:
    name: default
```

Then:
  - Webhook will patch the `assumeRolePolicyDocument` field with replacement values like below.

```yaml
---
apiVersion: iam.aws.crossplane.io/v1beta1
kind: Role
metadata:
  name: my-sample-irsa-role
  labels:
    type: my-sample-irsa-role
spec:
  forProvider:
    assumeRolePolicyDocument: |
        {
          "Version": "2012-10-17",
          "Statement": [
            {
              "Effect": "Allow",
              "Principal": {
                "Federated": "arn:aws:iam::012345678901:oidc-provider/oidc.eks.eu-west-1.amazonaws.com/id/XXXXXXC756AECD797B338FAA4A4D"
              },
              "Action": "sts:AssumeRoleWithWebIdentity",
              "Condition": {
                "StringEquals": {
                  "oidc.eks.eu-west-1.amazonaws.com/id/XXXXXXC756AECD797B338FAA4A4D:aud": "sts.amazonaws.com",
                  "oidc.eks.eu-west-1.amazonaws.com/id/XXXXXXC756AECD797B338FAA4A4D:sub": "system:serviceaccount:my-namespace:my-service-account"
                }
              }
            }
          ]
        }
  providerConfigRef:
    name: default
```

### Example for `ServiceAccount`
Given:
  - Account id is `012345678901`
When:
  - `ServiceAccount` creation request is submitted with an annotation field named `eks.amazonaws.com/role-arn` as
  
```yaml
---
apiVersion: v1
kind: ServiceAccount
metadata:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::${ACCOUNT_ID}:role/my-sample-irsa-role
  name: my-sample-irsa-sa
  namespace: crossplane-system
```

Then:
  - Webhook will patch the `eks.amazonaws.com/role-arn` annotation field with replacement values like below.

```yaml
---
apiVersion: v1
kind: ServiceAccount
metadata:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::012345678901:role/my-sample-irsa-role
  name: my-sample-irsa-sa
  namespace: crossplane-system
```

## Local build to generate platform binaries

### `make` command line

```bash
cd ~/environment/multi-cluster-gitops/webhooks/crossplane-irsa-webhook
make -f ./Makefile install
```

The output binaries are generated at the following location:

    webhooks
      |- crossplane-irsa-webhook
        |- build
          |- gopath
            |- bin
              |- darwin_amd64
                |- crossplane-irsa-webhook
              |- linux_amd64
                |- crossplane-irsa-webhook
    

## Run tests with coverage report

### `make` command line

```bash
cd ~/environment/multi-cluster-gitops/webhooks/crossplane-irsa-webhook
make -f ./Makefile test
```

The output `coverage.out` report file is generated at the following location:

    webhooks
      |- crossplane-irsa-webhook
        |- coverage.out

## Build image and push to repository

The `Makefile` uses variables to locate the coordinates of the image repository.

| Name | Default | Description |
|------|---------|-------------|
| `REGISTRY_ID` | `012345678901` | AWS Account ID of the ECR registry. Override the default value by setting an environment variable with the same name and value set to your AWS account id. |
| `IMAGE_NAME` | `multi-cluster-gitops/crossplane-irsa-webhook` | Namespaced image name. Create the repository before executing the build. |
| `REGION` | `eu-west-1` | AWS region where the ECR repository is created. |

### `make` command line

```bash
cd ~/environment/multi-cluster-gitops/webhooks/crossplane-irsa-webhook
make -f ./Makefile push
```

Update the image name and tag in `./deploy/kustomization.yaml`

## Command line arguments


        --add_dir_header                   If true, adds the file directory to the header
        --alsologtostderr                  log to standard error as well as files
        --aws-region string                The AWS region to configure for the AWS API calls (default "eu-west-1")
        --cluster-name string              Name of the Amazon EKS cluster to introspect for the OIDC provider
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


### Bootstrap arguments required for cluster introspection

| Name | Optional | Default |
|------|----------|---------|
| `--aws-region` | No | -NA- |
| `--cluster-name` | Yes | `eu-west-1` |