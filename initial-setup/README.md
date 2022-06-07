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

**Note:** Make sure you're using the same region as defined in multi-cluster-gitops/initial-setup/config/mgmt-cluster-eksctl.yaml

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

## Create and prepare the Git repositories
### Create Git SSH keys
1. Create the SSH key that will be used for interacting with the repos in your
   GitHub account from the Cloud9 environment.
```bash
cd ~/.ssh
ssh-keygen -t ed25519 -C "<youremail@yourcompany.com>" -f gitops-cloud9
```
(Replace `<youremail@yourcompany.com>` with your email address).

2. Create the SSH key that will be used by Flux for interacting with the repos
   in your GitHub account. While the same SSH key is used for all the
   repositories in these instructions, but the structure supports using
   different SSH keys for different repos.
```bash
cd ~/.ssh
ssh-keygen -t ed25519 -C "gitops@<yourcompany.com>" -f gitops
```
(Replace the `<yourcompany.com>` with your company domain).

3. Add the public part of the keys generated above to your GitHub account to
   grant access.

4. Create/edit `config` in `~/.ssh` to use the SSH key in `gitops-cloud9` for
   the Git commands executed on the Cloud9 environment.
```bash
cat << EOF > ~/.ssh/config
Host github.com
  AddKeysToAgent yes
  IdentityFile ~/.ssh/gitops-cloud9
EOF
```
### Create Git repos
1. Clone `multi-cluster-gitops` repo from the AWS Samples GitHub organization:
```bash
git clone https://github.com/aws-samples/multi-cluster-gitops.git
```

2. Log in with the Github CLI, choosing the Cloud9 publish SSH key as the
   authentication protocol
```bash
gh auth login
```

3. Create the following empty repos in your GitHub account: `gitops-system`,
   `gitops-workloads`, and `payment-app-manifests`, and clone them
   into the Cloud9 environment.
```bash
cd ~/environment
git config --global init.defaultBranch main
repos=( gitops-system gitops-workloads payment-app-manifests )
for repo in "${repos[@]}"; do
  gh repo create --private --clone $repo
done
```

4. Copy the content of the `multi-cluster-gitops/repos` directories to their
   respective repos you created in your GitHub account as indicated in the [Git
   Repositories](https://gitlab.aws.dev/mahgisla/multi-cluster-gitops/-/tree/main#git-repositories)
   section.

### Update the references to any repositories
1. Update the `git-repo.yaml` files, replacing the `url` of the repository with
   the one created in your account:
   1. In the `gitops-system` repo:
     - `./workloads/commercial-staging/git-repo.yaml`
     - `./workloads/commercial-prod/git-repo.yaml`
     - `./clusters/mgmt/flux-system/gotk-sync.yaml`
     - `./clusters/commercial-prod/flux-system/gotk-sync.yaml`
     - `./clusters/commercial-staging/flux-system/gotk-sync.yaml`
   2. In the `gitops-workloads` repo:
     - `./template/app-template/git-repo.yaml`
     - `./commercial-staging/app-template/git-repo.yaml`
     - `./commercial-staging/payment-app/git-repo.yaml`

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

### Update the `SealedSecret` resource that contains the Git Credentials for `gitops-system`

1. Copy the content of
   `multi-cluster-gitops/initial-setup/secrets-template/git-credentials.yaml` to
   `~/environment/mygitsecret.yaml`.

2. Replace the value for the field `identity` with the base64 encoding of the
   content in `~/.ssh/gitops`
```bash
KEY=$(cat ~/.ssh/gitops | base64 -w 0) yq -i '.data.identity = strenv(KEY)' mygitsecret.yaml
```
3. Replace the value for the field `identity.pub` with the base64 encoding of
   the content in `~/.ssh/gitops.pub`.
```
CERT=$(cat ~/.ssh/gitops.pub | base64 -w 0) yq -i '.data."identity.pub" = strenv(CERT)' mygitsecret.yaml
```
4. Replace the value for the field `known_hosts` with the base64 encoding of the
   following: "github.com " + the value of the `ssh_keys` starting with
   `ecdsa-sha2-nistp256` returned from https://api.github.com/meta.

```bash
HOST=$(echo "github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=" | base64 -w 0) yq -i '.data.known_hosts = strenv(HOST)' mygitsecret.yaml
```

5. Create SealedSecret resource for the updated content.
```bash
kubeseal --cert sealed-secrets-keypair-public.pem --format yaml <mygitsecret.yaml > mygitsealedsecret.yaml
```

6. Replace the content of
   `gitops-system/clusters-config/commercial-staging/secrets/git-secret.yaml` with the
   content of `mygitsealedsecret.yaml`.

7.  Replace the content of
    `gitops-system/clusters-config/commercial-prod/secrets/git-secret.yaml` with the
    content of `mygitsealedsecret.yaml`.

### Update the `SealedSecret` resource that contains the Git Credentials for `gitops-workloads`

1. Change the value for the `metadata.name` field in `mygitsecret.yaml` from
   `flux-system` to `gitops-workloads`.

2. Create `SealedSecret` resource for the updated content.
```bash
kubeseal --cert sealed-secrets-keypair-public.pem --format yaml <mygitsecret.yaml > mygitsealedsecret.yaml
```

3. Replace the definition of the `SealedSecret` resource in
   `gitops-system/workloads/commercial-staging/git-repo.yaml` with the content of
   `mygitsealedsecret.yaml`.

4. Replace the definition of the `SealedSecret` resource in
   `gitops-system/workloads/commercial-prod/git-repo.yaml` with the content of
   `mygitsealedsecret.yaml`.


### Update the `SealedSecret` resource that contains the Git Credentials for `payment-app-manifests`

4. Change the value for the `metadataname` field in `mygitsecret.yaml` from
   `gitops-workloads` to `red`.

5. Create `SealedSecret` resource for the updated content.
```bash
kubeseal --cert sealed-secrets-keypair-public.pem --format yaml <mygitsecret.yaml > mygitsealedsecret.yaml
```

6. Replace the definition of the `SealedSecret` resource in
   `gitops-workloads/commercial-staging/payment-app/git-repo.yaml` with the content of
   `mygitsealedsecret.yaml`.


### Commit and push the changes.
1. Commit and push `gitops-system` repo changes 
```bash
cd ~/environment/gitops-system
git add .
git commit -m "initial commit"
git push --set-upstream origin main
```

2. Commit and push `gitops-workloads` repo changes 
```bash
cd ~/environment/gitops-workloads
git add .
git commit -m "initial commit"
git push --set-upstream origin main
```
3. Commit and push `payment-app-manifests` repo changes 
```bash
cd ~/environment/payment-app-manifests
git add .
git commit -m "initial commit"
git push --set-upstream origin main
```

## Install the management cluster
1. Log into the AWS CLI with AWS credentials that have the privilege to create
   and connect to an EKS cluster

2. Create the management cluster using `eksctl`
```bash
eksctl create cluster -f ~/environment/multi-cluster-gitops/initial-setup/config/mgmt-cluster-eksctl.yaml
```

## Bootstrap the management cluster

1. Create GitHub personal access token. Please note that the `repo` scopes are
   the only ones required for the token used by Flux.

2. Bootstrap Flux on the management cluster with the `mgmt` cluster config path.
```bash
export CLUSTER_NAME=mgmt
export GITHUB_TOKEN=XXXX
export GITHUB_USER=<your-github-username>

flux bootstrap github \
  --components-extra=image-reflector-controller,image-automation-controller \
  --owner=$GITHUB_USER \
  --namespace=flux-system \
  --repository=gitops-system \
  --branch=main \
  --path=clusters/$CLUSTER_NAME \
  --personal
```

3. Wait for the `staging` cluster to start. Track the progress of the Flux
   deployments using the Flux CLI. This may take >30 minutes due to exponential
   backoff, however this is only a one-time process.
```bash
flux get all
```

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
