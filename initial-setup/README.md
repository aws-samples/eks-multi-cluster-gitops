# The initial setup
## Prerequisites

Each cluster you create requires 1 VPC (with an Internet Gateway attached), 2
Public Subnets, 2 Private Subnets, 2 NAT Gateways, and 2 Elastic IP Addresses
(attached to the NAT Gateways). Please make sure that the quotes of the AWS
account you use for deploying this sample implementation can accommodate that.

This document will assume all resources are created in `eu-west-1`.

## Create and prepare the Cloud9 workspace
1. Create an *Ubuntu 18.04* Cloud9 workspace with the name "gitops"
2. Follow [these instructions][resize-c9] to increase the volume of the EBS
   volume to 30GB
3. [Disable Cloud9 managed temporary credentials][disable-c9-creds]
4. Install Kubernetes CLI (`kubectl`)
```bash
sudo curl --silent --location -o /usr/local/bin/kubectl \
   https://amazon-eks.s3.us-west-2.amazonaws.com/1.19.6/2021-01-05/bin/linux/amd64/kubectl

sudo chmod +x /usr/local/bin/kubectl
```

5. Install Flux CLI
```bash
curl -s https://fluxcd.io/install.sh | sudo bash
```

6. Install `kubeseal`
```bash
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.16.0/kubeseal-linux-amd64 -O kubeseal
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

7. Install the Github CLI
```bash
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt update
sudo apt install gh
```

8. Install `yq`
```bash
sudo curl --silent --location -o /usr/local/bin/yq https://github.com/mikefarah/yq/releases/download/v4.24.5/yq_linux_amd64
sudo chmod +x /usr/local/bin/yq
```

9. Install `eksctl`
```bash
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin
```

[resize-c9]:
    https://docs.aws.amazon.com/cloud9/latest/user-guide/move-environment.html
[disable-c9-creds]:
    https://pcluster-sarus-gromacs.workshop.aws/setup/cloud9/disable-cred.html

## Create a secret in AWS Secret Manager for Sealed Secrets keys
1. Generate 4096 bit RSA key pair using openssl.
```bash
cd ~/environment
openssl genrsa -out sealed-secrets-keypair.pem 4096
openssl req -new -x509 -key sealed-secrets-keypair.pem -out sealed-secrets-keypair-public.pem -days 3650
```
2. Create a secret with the name `sealed-secrets` in the AWS Secrets Manager
   that contains the generated private key, and the certificate. Use a JSON file
   with the following structure for that:
```json
{
  "crt": "-----BEGIN CERTIFICATE-----
  ....
  -----END CERTIFICATE-----",
  "key": "-----BEGIN RSA PRIVATE KEY-----
  ....
  -----END RSA PRIVATE KEY-----"
}
```

## Create AWS credentials for Crossplane

1. Create the IAM user that will be used by Crossplane for provisioning AWS
   resources (DynamoDB table, SQS queue, etc.), allow programmatic access, and
   attach `AdministratorAccess` permissions. Keep a record of the generated
   access key ID and secret access key as you will use them in a subsequent
   step.

2. You can fine-tune the permissions granted to the created IAM user, and only
   select those that you want to grant to Crossplane.

### Update the AWS Credentials `SealedSecret`
1. Create `aws-credentials.conf`.
```
cd ~/environment
echo -e "[default]\naws_access_key_id = <access-key-id>\naws_secret_access_key = <secret-access-key>" > aws-credentials.conf
```
(Replace `<access-key-id>` and `<secret-access-key>` with the Access Key ID and
the Secret Access Key you created above).

2. Create `secret` resource that contains the AWS credentials, and create a
   corresponding `SealedSecret` resource.
```
kubectl create secret generic aws-credentials -n crossplane-system --dry-run=client --from-file=credentials=./aws-credentials.conf -o yaml >mysecret.yaml

kubeseal --cert sealed-secrets-keypair-public.pem --format yaml <mysecret.yaml > mysealedsecret.yaml
```
3. Replace the content of
   `gitops-system/tools/crossplane/crossplane-aws-provider-config/aws-credentials-sealed.yaml`
   with the content of `mysealedsecret.yaml`.

NOTE: Make sure you do not commit `aws-credentials.conf``` and/or
`mysecret.yaml` to Git. Otherwise, your AWS credentials will be stored
unencrypted in Git!

## Install the management cluster
1. Log into the AWS CLI with AWS credentials that have the privilege to create
   and connect to an EKS cluster

2. Create the management cluster using `eksctl`
```bash
eksctl create cluster -f ~/environment/multi-cluster-gitops/initial-setup/config/mgmt-cluster-eksctl.yaml
```

## Setup instructions to initialize git repositories

[Using GitHub as `GitRepository` backend.](doc/repos/GitHub.md#create-and-prepare-the-git-repositories)

OR

[Using AWS CodeCommit as `GitRepository` backend.](doc/repos/AWSCodeCommit.md#create-and-prepare-the-git-repositories)

## Connect to cluster
1. Connect to `<cluster-name>`  cluster using `kubeconfig` stored as a `Secret`
```bash
unset KUBECONFIG
kubectl -n flux-system get secret <cluster-name>-eks-connection -n flux-system -o jsonpath="{.data.value}" | base64 -d > wl-kube.conf
export KUBECONFIG=wl-kube.conf

kubectl config current-context
```
(Replace `<cluster-name>` with the cluster name).

## Monitoring Flux Kustomizations
* If you want to monitor the bootstrapping of the management cluster, and/or the
  provisioning/bootstrapping of the workload clusters, list the `Kustomization`
  resources in the management cluster using the following command:

```bash
kubectl get kustomization -n flux-system
```
* If you want to monitor the bootstrapping of the workload clusters, and the
  deployment of the applications into it, connect to the workload cluster by
  following the instructions above, then list the `Kustomization` resources
  using the following command:

```bash
kubectl get kustomization -n flux-system
```

NOTE: We will soon add a section about Flux notification controller, and how you
can use that to know the status of the reconciliation activities without having
to connect to the clusters.