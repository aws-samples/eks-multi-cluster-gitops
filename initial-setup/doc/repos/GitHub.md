## Create and prepare the Git repositories
### Create Git SSH keys
1. Create the SSH key that will be used for interacting with the repos in your
   GitHub account from the Cloud9 environment.
   ```bash
   cd ~/.ssh
   ssh-keygen -t ed25519 -C "<youremail@yourcompany.com>" -f gitops-cloud9
   ```
   (Replace `<youremail@yourcompany.com>` with your email address).
   This generates two files: `gitops-cloud9` contains a private key, and `gitops-cloud9.pub` contains the corresponding public key.

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
   This generates two files: `gitops` contains a private key, and `gitops.pub` contains the corresponding public key.

3. Copy the contents of the public key files generated above (these have a `.pub` suffix) to your GitHub account in order to
   grant access. To do this, use the GitHub console to access **Settings->SSH and GPG Keys**,
   and use the **New SSH Key** buttton to add each of the keys in turn.

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

1. Log in with the Github CLI using:
   ```bash
   gh auth login -p ssh -h GitHub.com
   ```
<!--
   3. For the SSH public key, choose **/home/ubuntu/.ssh/gitops-cloud9.pub**.
-->

2. Create the following empty repos in your GitHub account: `gitops-system`,
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
   
3. Copy the content of the `multi-cluster-gitops/repos` directories
   to the corresponding repos you created in the previous step:
   ```
   cp -r multi-cluster-gitops/repos/gitops-system/* gitops-system/
   cp -r multi-cluster-gitops/repos/gitops-workloads/* gitops-workloads/
   cp -r multi-cluster-gitops/repos/app-manifests/payment-app/* payment-app-manifests/
   ```
   
### Update references to Git repositories

1. Set the variable `GITHUB_ACCOUNT` to your GitHub user name.
   ```
   GITHUB_ACCOUNT=<your-github-user-name>
   ```
2. Set the variable `REPO_PREFIX` as follows:
   ```
   REPO_PREFIX=ssh://git@github.com/$GITHUB_ACCOUNT
   ```
4. Update the `git-repo.yaml` files in the `workloads` folder of the `gitops-system` repo,
   replacing the `url` for the `GitRepository` resource with
   the URL for the `gitpops-workloads` repo created in your account:
   ```
   yq e \
     ".spec.url = \"$REPO_PREFIX/gitops-workloads\"" \
     -i ./gitops-system/workloads/commercial-staging/git-repo.yaml
   yq e \
     ".spec.url = \"$REPO_PREFIX/gitops-workloads\"" \
     -i ./gitops-system/workloads/commercial-prod/git-repo.yaml
   ```
3. Update the `gotk-sync.yaml` files in the `clusters` folder of the `gitops-system` repo,
   replacing the `url` for the `GitRepository` resource with
   the URL for the `gitpops-system` repo created in your account:
   ```
   yq e \
     ".spec.url = \"$REPO_PREFIX/gitops-system\"" \
     -i ./gitops-system/clusters/mgmt/flux-system/gotk-sync.yaml
   yq e \
     ".spec.url = \"$REPO_PREFIX/gitops-system\"" \
     -i ./gitops-system/clusters/commercial-prod/flux-system/gotk-sync.yaml
   yq e \
     ".spec.url = \"$REPO_PREFIX/gitops-system\"" \
     -i ./gitops-system/clusters/commercial-staging/flux-system/gotk-sync.yaml
   ```

4. Update the `git-repo.yaml` files in the `gitops-workloads` repo,
   replacing the `url` for the `GitRepository` resource with
   the URL for the `payment-app-manifests` repo created in your account:
   ```
   yq e \
     ".spec.url = \"$REPO_PREFIX/payment-app-manifests\"" \
     -i ./gitops-workloads/template/app-template/git-repo.yaml
   yq e \
     ".spec.url = \"$REPO_PREFIX/payment-app-manifests\"" \
     -i ./gitops-workloads/commercial-staging/app-template/git-repo.yaml
   yq e \
     ".spec.url = \"$REPO_PREFIX/payment-app-manifests\"" \
     -i ./gitops-workloads/commercial-staging/payment-app/git-repo.yaml
   ```



### Create a `Secret` resource that contains the Git Credentials for `gitops-system`

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
   KEY=$(cat ~/.ssh/gitops | base64 -w 0) yq -i '.data.identity = strenv(KEY)' git-creds-system.yaml
   ```

3. Replace the value for the field `identity.pub` with the base64 encoding of
   the content in `~/.ssh/gitops.pub`.
   ```
   CERT=$(cat ~/.ssh/gitops.pub | base64 -w 0) yq -i '.data."identity.pub" = strenv(CERT)' git-creds-system.yaml
   ```

4. Replace the value for the field `known_hosts` with the base64 encoding of the
   following: "github.com " + the value of the `ssh_keys` starting with
   `ecdsa-sha2-nistp256` returned from https://api.github.com/meta.

   ```bash
   HOST=$(echo "github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=" | base64 -w 0) yq -i '.data.known_hosts = strenv(HOST)' git-creds-system.yaml
   ```

When done, continue with the setup process [here](../README.md#create-sealed-secrets-for-access-to-git-repos)
