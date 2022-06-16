## Create and prepare the Git repositories
### Create Git SSH keys
1. Create a new IAM user that will be used to interact with the CodeCommit repos from Cloud9 environment and from the EKS clusters by Flux source controller. While the same IAM user is used for all the
   repositories in these instructions, but the structure supports using
   different users for different repos.

```bash
cd ~/environment
aws iam create-user \
  --user-name gitops

cat >gitops-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "codecommit:GitPull",
        "codecommit:GitPush"
      ],
      "Resource": [
         "arn:aws:codecommit:${AWS_REGION}:${AWS_ACCOUNT_ID}:gitops-system",
         "arn:aws:codecommit:${AWS_REGION}:${AWS_ACCOUNT_ID}:gitops-workloads",
         "arn:aws:codecommit:${AWS_REGION}:${AWS_ACCOUNT_ID}:payment-app-manifests"
      ]
    }
  ]
}
EOF

POLICY_ARN=$(aws iam create-policy \
  --policy-name "gitops-policy" \
  --description "IAM policy for user gitops." \
  --policy-document file://gitops-policy.json \
  --query 'Policy.Arn' \
  --output text)

aws iam attach-user-policy \
  --user-name gitops \
  --policy-arn "${POLICY_ARN}"
```

2. Create the SSH key that will be used by Flux for interacting with the repos
   in your AWS account. While the same SSH key is used for all the
   repositories in these instructions, but the structure supports using
   different SSH keys for different repos.
```bash
cd ~/.ssh
ssh-keygen -t rsa -b 4096 -N "" -C "gitops@<yourcompany.com>" -f gitops
```
(Replace the `<yourcompany.com>` with your company domain).

3. Add the public part of the keys generated above to the respective IAM users in your AWS account to
   grant access. Note down the SSH key ids printed in the terminal.

```bash
cd ~/.ssh
SSH_KEY_ID_GITOPS=$(aws iam upload-ssh-public-key \
  --user-name gitops \
  --ssh-public-key-body file://gitops.pub \
    --query 'SSHPublicKey.SSHPublicKeyId' \
    --output text)
echo "SSH key id of user gitops: ${SSH_KEY_ID_GITOPS}"
```

4. Create/edit `config` in `~/.ssh` to use the SSH key in `gitops` for
   the Git commands executed on the Cloud9 environment.
```bash
cat >~/.ssh/config <<EOF 
Host git-codecommit.*.amazonaws.com
  User ${SSH_KEY_ID_GITOPS}
  IdentityFile ~/.ssh/gitops
EOF
```
### Create Git repos

1. Create the following empty CodeCommit repos in your AWS account: `gitops-system`,
   `gitops-workloads`, and `payment-app-manifests`, and clone them
   into the Cloud9 environment.

```bash
cd ~/environment
git config --global init.defaultBranch main
repos=( gitops-system gitops-workloads payment-app-manifests )
for repo in "${repos[@]}"; do
  aws codecommit create-repository \
    --repository-name $repo
  
  echo "SSH Clone URL for user gitops"
  echo " - ssh://${SSH_KEY_ID_GITOPS}@git-codecommit.${AWS_REGION}.amazonaws.com/v1/repos/$repo"
done
```

2. Copy the content of the `multi-cluster-gitops/repos` directories to their
   respective repos you created in your AWS account as indicated in the [Git
   Repositories](https://gitlab.aws.dev/mahgisla/multi-cluster-gitops/-/tree/main#git-repositories)
   section.

### Update the references to any repositories
1. Update the `git-repo.yaml` files, replacing the `url` of the repository with
   the one created in your account. Note the ssh clone url must contain the SSH key id of gitops user as printed above :
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
2. Update files containing `GitRepository` specs, adding `gitImplementation: libgit2` inside `spec` object for `GitRepository`.
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
3. The above two edits should result in the `GitRepository` manifests resembling below sample.

```yaml
---
# This is a sample GitRepository manifest
# showing edits required for AWS CodeCommit
apiVersion: source.toolkit.fluxcd.io/v1beta1
kind: GitRepository
metadata:
  name: <name>
  namespace: flux-system
spec:
  gitImplementation: libgit2 ### Edit 2
  interval: 1m0s
  ref:
    branch: main
  secretRef:
    name: <secret-ref>
  url: ssh://<SSH key id>@git-codecommit.<region>.amazonaws.com/v1/repos/<repo> ### Edit 1
```


### Create a `Secret` resource that contains the Git Credentials for `gitops-system`

1. Create `codecommit_known_hosts` file for AWS CodeCommit regional endpoint

```bash
cd ~/environment
ssh-keyscan \
  -t rsa \
  git-codecommit.${AWS_REGION}.amazonaws.com \
  > ~/.ssh/codecommit_known_hosts 2>/dev/null
```

2. Generate a Kubernetes secret file with git ssh credentials for gitops user.

```bash
cd ~/environment
kubectl create secret generic flux-system -n flux-system \
    --from-file=identity=${HOME}/.ssh/gitops \
    --from-file=identity.pub=${HOME}/.ssh/gitops.pub \
    --from-file=known_hosts=${HOME}/.ssh/codecommit_known_hosts \
    --dry-run=client \
    --output=yaml \
    >git-creds-system.yaml
```


