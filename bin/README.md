# Multi-cluster GitOps Scripts

Note: these scripts operate on local repos and do not commit changes or push to remotes.
Commits and pushes must be done separately.

## Workload cluster management

### add-cluster.sh

Usage:
```
add-cluster.sh <gitops_system_path> <cluster_name> 
```

Updates the local repo for `gitops-system` to add a new workload cluster.

This is achieved by copying the required template folders into new folders for the cluster to be added, and updating the cluster name. The `kustomization.yaml` file in `clusters-config` is also updated to add the new cluster.

### remove-cluster.sh

Usage:
```
remove-cluster.sh <gitops_system_path> <gitops_workloads_path> <cluster_name> 
```

This removes the specified cluster from `cluster-configs/kustomization.yaml`, which triggers crossplane to remove the cluster.

It also removes all cluster configuration files from the local
repos for `gitops-system` and `gitops-workloads`.

## Application management

### add-cluster-app.sh

Usage:
```
add-cluster-app.sh
  <gitops_workloads_path>
  <cluster_name> <app-name>
  <public_key_pem>
  <git_creds_template_path>
  <git_private_key_file> <git_public_key_file> <git_known_hosts>
  <sealed_secrets_public_pem_file>
```

Adds the application `app-name` to the cluster `cluster-name`, using the following steps:
- creates a new folder for the app under the correct workloads cluster folder and copies the app template
- updates the folder content with the correct cluster name and app name
- creates a sealed secret `gitops-secret.yaml` using the supplied template, keys, and known_hosts string
- updates `kustomization.yaml` in the workloads cluster folder.

It is assumed that a repo called `app-name-manifests` exists.

### remove-cluster-app.sh

```
remove-cluster-app.sh <gitops_workloads_path> <cluster_name> <app-name>
```

Removes the application from `kustomization.yaml` and deletes the application folder from the workloads cluster folder.

### add-app-cluster-overlay

Usage:
```
add-app-cluster-overlay <app_manifests_path> cluster_name 
```


## Example sequence

Create a `staging` cluster:
```
add-cluster.sh ./gitops-system staging
```

Add an app `product-catalog-api` to the `staging` cluster:
```
add-cluster-app.sh \
  ./gitops-workloads \
  staging product-catalog-api \
  multi-cluster-gitops/initial-setup/secrets-template/git-credentials.sh \
  ~/.ssh/gitops ~/.ssh/gitops.pub \
  "github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=" \
  ./sealed-secrets-keypair-public.pem
```