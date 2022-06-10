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

4. Change the value for the `metadata.name` field in `mygitsecret.yaml` from
   `gitops-workloads` to `payment-app`.

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