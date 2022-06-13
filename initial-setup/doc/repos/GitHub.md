## Create and prepare the Git repositories
### Create Git SSH keys
1. Create the SSH key that will be used for interacting with the repos in your
   GitHub account from the Cloud9 environment.
   ```bash
   cd ~/.ssh
   ssh-keygen -t ed25519 -C "<youremail@yourcompany.com>" -f gitops-cloud9
   ```
   (Replace `<youremail@yourcompany.com>` with your email address).

2. Create the SSH key that will be used by Flux for interacting
   with the repos in your GitHub account. Ensure that you do not use a
   passphrase to protect the key, as this will prevent Flux from being able to use
   the key.

   **Note:** In order to keep this walkthrough as short as possible, the same SSH
   key is used for all GitHub repositories. However, the architecture does support
   use of different SSH keys for different repos.
   ```bash
   cd ~/.ssh
   ssh-keygen -t ed25519 -C "gitops@<yourcompany.com>" -f gitops
   ```
   (Replace the `<yourcompany.com>` with your company domain or a fictitious domain).

3. Add the public part of the keys generated above to your GitHub account to
   grant access.

4. Create/edit `config` in `~/.ssh` to use the SSH key in `gitops-cloud9` for
   the Git commands executed in the Cloud9 environment.
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
   cd ~/environment
   git clone https://github.com/aws-samples/multi-cluster-gitops.git
   ```

2. Log in with the Github CLI using:
   ```bash
   gh auth login
   ```
   1. In response to the prompt for an account, choose **GitHub.com**.
   2. For preferred protocol, choose **SSH**.
   3. For the SSH public key, choose **/home/ubuntu/.ssh/gitops-cloud9.pub**.
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
   
4. Copy the content of the `multi-cluster-gitops/repos` directories
   to the corresponding repos you created in the previous step:
   ```
   cp -r multi-cluster-gitops/repos/gitops-system/* gitops-system/
   cp -r multi-cluster-gitops/repos/gitops-workloads/* gitops-workloads/
   cp -r multi-cluster-gitops/repos/app-manifests/payment-app/* payment-app-manifests/
   ```
   
### Update references to Git repositories

1. Set the variable name `GITHUB_ACCOUNT` to your GitHub user name.
   ```
   GITHUB_ACCOUNT=<your-github-user-name>
   ```
2. Update the `git-repo.yaml` files in the `workloads` folder of the `gitops-system` repo,
   replacing the `url` for the `GitRepository` resource with
   the URL for the `gitpops-workloads` repo created in your account:
   ```
   yq e \
     ".spec.url = \"ssh://git@github.com/$GITHUB_ACCOUNT/gitops-workloads\"" \
     -i ./gitops-system/workloads/commercial-staging/git-repo.yaml
   yq e \
     ".spec.url = \"ssh://git@github.com/$GITHUB_ACCOUNT/gitops-workloads\"" \
     -i ./gitops-system/workloads/commercial-prod/git-repo.yaml
   ```
3. Update the `gotk-sync.yaml` files in the `clusters` folder of the `gitops-system` repo,
   replacing the `url` for the `GitRepository` resource with
   the URL for the `gitpops-system` repo created in your account:
   ```
   yq e \
     ".spec.url = \"ssh://git@github.com/$GITHUB_ACCOUNT/gitops-system\"" \
     -i ./gitops-system/clusters/mgmt/flux-system/gotk-sync.yaml
   yq e \
     ".spec.url = \"ssh://git@github.com/$GITHUB_ACCOUNT/gitops-system\"" \
     -i ./gitops-system/clusters/commercial-prod/flux-system/gotk-sync.yaml
   yq e \
     ".spec.url = \"ssh://git@github.com/$GITHUB_ACCOUNT/gitops-system\"" \
     -i ./gitops-system/clusters/commercial-staging/flux-system/gotk-sync.yaml
   ```

4. Update the `git-repo.yaml` files in the `gitops-workloads` repo,
   replacing the `url` for the `GitRepository` resource with
   the URL for the `payment-app-manifests` repo created in your account:
   ```
   yq e \
     ".spec.url = \"ssh://git@github.com/$GITHUB_ACCOUNT/payment-app-manifests\"" \
     -i ./gitops-workloads/template/app-template/git-repo.yaml
   yq e \
     ".spec.url = \"ssh://git@github.com/$GITHUB_ACCOUNT/payment-app-manifests\"" \
     -i ./gitops-workloads/commercial-staging/app-template/git-repo.yaml
   yq e \
     ".spec.url = \"ssh://git@github.com/$GITHUB_ACCOUNT/payment-app-manifests\"" \
     -i ./gitops-workloads/commercial-staging/payment-app/git-repo.yaml
   ```



### Update the `SealedSecret` resource that contains the Git Credentials for `gitops-system`

1. Copy the content of
   `multi-cluster-gitops/initial-setup/secrets-template/git-credentials.yaml` to
   `~/environment/git-creds-system.yaml`.
   ```
   cd ~/environment
   cp multi-cluster-gitops/initial-setup/secrets-template/git-credentials.yaml git-creds-system.yaml
   ```

2. Replace the value for the field `identity` with the base64
   encoding of the content in `~/.ssh/gitops`
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

5. Create a SealedSecret resource for the updated content.
   ```bash
   kubeseal --cert sealed-secrets-keypair-public.pem --format yaml <git-creds-system.yaml >git-creds-secret-system.yaml
   ```

6. Replace the content of
   `gitops-system/clusters-config/commercial-staging/secrets/git-secret.yaml` with the
   content of `git-creds-secret-system.yaml`.
   ```
   cp git-creds-secret-system.yaml gitops-system/clusters-config/commercial-staging/secrets/git-secret.yaml
   ```

7. Replace the content of
   `gitops-system/clusters-config/commercial-prod/secrets/git-secret.yaml` with the content of `git-creds-secret-system.yaml`.
   ```
   cp git-creds-secret-system.yaml gitops-system/clusters-config/commercial-prod/secrets/git-secret.yaml
   ```

### Update the `SealedSecret` resource that contains the Git Credentials for `gitops-workloads`

1. Copy `git-creds-system.yaml` to `git-creds-workloads.yaml`, and change the value for `metadata.name` from
   `flux-system` to `gitops-workloads`.
   ```
   cp git-creds-system.yaml git-creds-workloads.yaml
   yq e '.metadata.name="gitops-workloads"' -i git-creds-workloads.yaml
   ```

2. Create a SealedSecret resource for the updated content.
   ```bash
   kubeseal --cert sealed-secrets-keypair-public.pem --format yaml <git-creds-workloads.yaml >git-creds-secret-workloads.yaml
   ```

3. Replace the content of
   `gitops-system/workloads/commercial-staging/git-secret.yaml` with the content of
   `git-creds-secret-workloads.yaml`.
   ```
   cp git-creds-secret-workloads.yaml gitops-system/workloads/commercial-staging/git-secret.yaml
   ```

4. Replace the content of
   `gitops-system/workloads/commercial-prod/git-secret.yaml` with the content of
   `git-creds-secret-workloads.yaml`.
   ```
   cp git-creds-secret-workloads.yaml gitops-system/workloads/commercial-prod/git-secret.yaml
   ```

### Update the `SealedSecret` resource that contains the Git Credentials for `payment-app-manifests`

1. Copy `git-creds-system.yaml` to `git-creds-app.yaml`, and change the value for `metadata.name` from
   `flux-system` to `payment-app`.
   ```
   cp git-creds-system.yaml git-creds-app.yaml
   yq e '.metadata.name="payment-app"' -i git-creds-app.yaml
   ```

2. Create a SealedSecret resource for the updated content.
   ```bash
   kubeseal --cert sealed-secrets-keypair-public.pem --format yaml <git-creds-app.yaml >git-creds-secret-app.yaml
   ```

3. Replace the content of
   `gitops-workloads/commercial-staging/payment-app/git-secret.yaml` with the content of `git-creds-secret-app.yaml`.
   ```
   cp git-creds-secret-app.yaml gitops-workloads/commercial-staging/payment-app/git-secret.yaml
   ```

### Commit and push the changes

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

1. Create a GitHub personal access token. Please note that the `repo` scopes are
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
   You can watch this to see once it's ready by using:
   ```bash
   watch -n 30 -d flux get all
   ```
