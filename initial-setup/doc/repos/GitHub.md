## Create and prepare the Git repositories

### Create SSH key for Dev_Environment access to GitHub repo

1. Create the SSH key that will be used for interacting with the repos in your
   GitHub account from the Dev_Environment.
   ```bash
   cd ~/.ssh
   ssh-keygen -t ed25519 -C "<youremail@yourcompany.com>" -f gitops-devenv
   ```
   (Replace `<youremail@yourcompany.com>` with your email address).
   This generates two files: `gitops-devenv` contains a private key, and `gitops-devenv.pub` contains the corresponding public key.


2. Create/edit `config` in `~/.ssh` to use the SSH key in `gitops-devenv` for
   the Git commands executed in the Dev_Environment.
   ```bash
   cat << EOF > ~/.ssh/config
   Host github.com
   AddKeysToAgent yes
   IdentityFile ~/.ssh/gitops-devenv
   EOF
   ```
   
3. Log in with the Github CLI using:
   ```bash
   gh auth login -p ssh -h github.com
   ```
   
   - In response to **Upload your SSH public key to your GitHub account?**, choose **/home/participant/.ssh/gitops-devenv.pub**.
   - For **Title for your SSH key**, enter **gitops-devenv**.
   - In response to **How would you like to authenticate GitHub CLI?**, choose **Login with a web browser**.
   - Note the one-time code.
   - Pressing Enter will result in an error message as you cannot open a browser directly from your Dev_Environment.
   - Use a separate tab on your browser to navigate to https://github.com/login/device and enter the code.
   - Choose **Authorize github**.
   - Return to your Dev_Environment terminal to continue. You are now logged in to your GitHub account from the Dev_Environment. You can test this by running commands like `gh auth status` and `gh repo list`.

### Create SSH key for Flux access to GitHub repo

1. Create the SSH key that will be used by Flux for interacting
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

2. Copy the contents of the public key file `gitops.pub` generated above to your GitHub account as follows:
   ```
   gh ssh-key add -t gitops ~/.ssh/gitops.pub
   ```
   
3. Verify that the key has been added:
   ```
   gh ssh-key list
   ```

   
### Create GitHub repos

Create empty repos  `gitops-system` and `gitops-workloads` in your GitHub account, and clone them
into the Dev_Environment.
```
cd ~/environment
git config --global init.defaultBranch main
gh repo create --private --clone  gitops-system
gh repo create --private --clone  gitops-workloads
```
   
### Set the `REPO_PREFIX` variable to point at your GitHub account

1. Set the variable `GITHUB_ACCOUNT` to your GitHub user name.
   ```
   GITHUB_ACCOUNT=<your-github-user-name>
   ```
2. Set the variable `REPO_PREFIX` as follows:
   ```
   export REPO_PREFIX="ssh:\/\/git@github.com\/$GITHUB_ACCOUNT"
   ```


### Create a `Secret` resource that contains the Git Credentials for `gitops-system`

1. Copy the content of
   `eks-multi-cluster-gitops/initial-setup/secrets-template/git-credentials.yaml` to
   `~/environment/git-creds-system.yaml`.
   ```
   cd ~/environment
   cp eks-multi-cluster-gitops/initial-setup/secrets-template/git-credentials.yaml git-creds-system.yaml
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

When done, continue with the setup process [here](../../README.md#populate-and-update-the-repositories)
