# Scenarios

This document walks you through steps for a number of scenarios covering:
- Adding a workload cluster
- Adding an application to a workload cluster (including associated AWS resources)
- Connecting to a workload cluster to check reconciliation status
- Updating an application running in a workload cluster
- Upgrading a workload cluster
- Removing an application from a workload cluster
- Removing a workload cluster

For illustration purposes, these scenarios are based on the example of a product catalog application developed by the commercial department of an organisation.
- The department
runs two clusters `commercial-staging` and `commercial-prod`.
- The product catalog application comprises two microservices which are owned by different teams.
  - API server: this provides the backend, and makes use of an AWS DynamoDB table to store its state.
  - Front end server: provides a web front end service that can be accessed via a browser.

Pre-prepared manifest files for the application workloads are included in the
`repos/apps-manifests` directory as follows:
- `reops/apps-manifests/product-catalog-api-manifests`: contains manifests for two dsictinct versions of the API server, labelled `V1` and `V2`.
- `reops/apps-manifests/product-catalog-fe-manifests`: contains manifests for the front end
server.
You can see that both of these include overlays for both the `commercial-staging` and `commercial-prod` clusters.

## Provision and bootstrap a new workload cluster

In this section you will create a new workload cluster called `commercial-staging`. To achieve this, you need to use the supplied templates to create manifest files for the new cluster in
`gitops-system`, and update `clusters-config/kustomization.yaml` Once done, you then push the
changes so that flux can pick them up and act on them.

You can make the required changes quickly using the script `add-cluster.sh`:
```
cd ~/environment
multi-cluster-gitops/bin/add-cluster.sh ./gitops-system commercial-staging
```

Once done, commit and push the changes as follows:
```
cd gitops-system
git add .
git commit -m "Add cluster commercial-staging"
git push
```

Use
```
kubectl get kustomization -n flux-system
```
to monitor the creation of resources for the new cluster.

You can repeat the same process to create the `commercial-prod` cluster.

### Detailed explanation of `add-cluster.sh` script

The `add-cluster.sh` script performs the following steps. You can choose to execute these steps instead of running the script. Please ensure your working directory is set to `~/environment` before executing.

1. **Instantiate the `cluster-configs` template:** This creates a folder for the new `commercial-staging` cluster under `cluster-configs`, and copies the template.
It then replaces all occurances of `cluster-name` in the template with `commercial-staging`.
    ```
    mkdir -p gitops_system/clusters-config/commercial-staging
    cp -R gitops_system/clusters-config/template/* gitops_system/clusters-config/commercial-staging
    grep -RiIl 'cluster-name' gitops_system/clusters-config/commercial-staging| xargs sed -i "s/cluster-name/commercial-staging/g"
    ```

2. **Instantiate the `cluster` template:** This create a folder for the `commcercial-staging` cluster
under `clusters`, and copies the template. It then replaces all occurances of `cluster-name` in the template with `commercial-staging`.
    ```
    mkdir -p gitops_system/clusters/commercial-staging
    cp -R gitops_system/clusters/template/* gitops_system/clusters/commercial-staging
    grep -RiIl 'cluster-name' gitops_system/clusters/commercial-staging | xargs sed -i "s/cluster-name/commercial-staging/g"
    ```

3. **Instantiate the `workloads` template.** This creates a folder for the
 `commcercial-staging` cluster under `workloads` and copies the template. It then
 replaces all occurences of `cluster-name` in the template with `commercial-staging`.
    ```
    mkdir -p gitops_system/workloads/commercial-staging
    cp -R gitops_system/workloads/template/* gitops_system/workloads/commercial-staging
    grep -RiIl 'cluster-name'  gitops_system/workloads/commercial-staging | xargs sed -i "s/cluster-name/commercial-staging/g"
    ```

4.  **Add `commercial-staging` to `clusters-config/kustomization.yaml`.**
    This forces Flux to pick up the new cluster config.
    ```
    yq -i e ".resources += [\"commercial-staging\"]" gitops_system/clusters-config/kustomization.yaml
    ```


## Add an application to a cluster

In this section you will add an application `product-catalog-api` to the cluster `commercial-staging`. To achieve this, you need to use the supplied template to
create manifest files for the new application in `gitops-workloads/commercial-staging`
, and update `commercial-staging/kustomization.yaml`. Once done, you then push the
changes so that flux can pick them up and act on them.

First, prepare a repo for `product-catalog-api-manifests` as follows:
```
cd ~/environment
gh repo create --private --clone product-catalog-api-manifests
cp -r multi-cluster-gitops/repos/apps-manifests/product-catalog-api-manifests/v1/* product-catalog-api-manifests/
cd product-catalog-api-manifests
git add .
git commit -m "baseline version"
git branch -M main
git push --set-upstream origin main
```

Next, tag the current commit as version 1.0 and push the tag:
```
git tag -a v1.0 -m "Version 1.0"
git push origin v1.0
```

You can make the required changes in `gitops-workloads`  using the script `add-cluster-app.sh`:
```
cd ~/environment
multi-cluster-gitops/bin/add-cluster-app.sh \
  ./gitops-workloads \
  commercial-staging product-catalog-api v1.0 \
  multi-cluster-gitops/initial-setup/secrets-template/git-credentials.yaml \
  ~/.ssh/gitops ~/.ssh/gitops.pub \
  "github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=" \
  ./sealed-secrets-keypair-public.pem
```

Once done, commit and push the changes as follows:
```
cd gitops-workloads
git add .
git commit -m "Add product-catalog-api to commercial-staging"
git push
```

To view the reconciliation of resources in the workload cluster, and verify that application
resources have been created, see the section [Connect to a workload cluster](#connect-to-a-workload-cluster).

This application makes use of a DynamoDB table which is created by Crossplane. You can
verify that this has been created using the [DynamoDB console](https://console.aws.amazon.com/dynamodb/), or via the AWS CLI:
```
aws dynamodb list-tables
```

You can repeat the same process to add the application to the `commercial-prod` cluster
(using the same manifests repo).

You can also repeat this process to add the front-end application `product-catalog-fe` to
each cluster. You will
find pre-prepared manifests for this in the `product-catalog-fe-manifests` repo. Note these
include overlays for each of `commercial-staging` and `commercial-prod`.

### Detailed explanation of `add-cluster-app.sh`

The `add-cluster-app.sh` script performs the following steps. You can choose to execute these steps instead of running the script. Please ensure your working directory is set to `~/environment` before executing.

1. **Ensure a directory for the application exists under `gitops-workloads/commercial-staging`:** create a directory if it does not yet exist (i.e. this is the first app in this cluster).
```
mkdir -p gitops-workloads/commercial-staging/product-catalog-api
```

2. **Ensure a `kustomization.yaml` file exists:** check if the file exists, and if not then
create one by copying the template (only happens for the first app that is added to the cluster).
```
if [[ ! -f gitops-workloads/commercial-staging/kustomization.yaml ]]
then
    cp gitops-workloads/template/kustomization.yaml gitops-workloads/commercial-staging
fi
```

3. **Instantiate the workloads application template:** this copies the application template
from `gitops-workloads/template/app-template` to `gitops-workloads/commercial-staging/product-catalog-api`, and then updates the cluster name and app name to the correct values.
```
cp -R gitops-workloads/template/app-template/* gitops-workloads/commercial-staging/product-catalog-api
grep -RiIl 'cluster-name' gitops-workloads/commercial-staging/product-catalog-api | xargs sed -i "s/cluster-name/commercial-staging/g"
grep -RiIl 'app-name' gitops-workloads/commercial-staging/product-catalog-api | xargs sed -i "s/app-name/product-catalog-api/g"
grep -RiIl 'release-tag' gitops-workloads/commercial-staging/product-catalog-api | xargs sed -i "s/release-tag/v1.0/g"
```

4. **Prepare the sealed secret for the application:** this prepares a sealed secret for the
application, which contains the Git credentials needed to access the repo. A
temporary file is used to store a copy of the Git credentials template (which is
a K8s `Secret`). This file is updated to use the correct name, public/private key pair, and
known hosts. `kubeseal` is then used to create a sealed secret, using a supplied `.pem` file
containing a key to encrypt the sealed secret which is stored in `gitops-workloads/commercial-staging/product-catalog-api/git-secret.yaml`.

```
tmp_git_creds=$(mktemp /tmp/git-creds.yaml.XXXXXXXXX)
cp multi-cluster-gitops/initial-setup/secrets-template/git-credentials.yaml $tmp_git_creds
APP_NAME=product-catalog-api yq e '.metadata.name=strenv(APP_NAME)' -i $tmp_git_creds
KEY=$(cat ~/.ssh/gitops | base64 -w 0) yq -i '.data.identity = strenv(KEY)' $tmp_git_creds
CERT=$(cat ~/.ssh/gitops.pub | base64 -w 0) yq -i '.data."identity.pub" = strenv(CERT)' $tmp_git_creds
HOSTS=$(echo "github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=" | base64 -w 0) yq -i '.data.known_hosts = strenv(HOSTS)' $tmp_git_creds
kubeseal --cert ./sealed-secrets-keypair-public.pem --format yaml <$tmp_git_creds >gitops-workloads/commercial-staging/product-catalog-api/git-secret.yaml
rm $tmp_git_creds
```

5. **Add entry to `kustomization.yaml`:** this forces Flux to pick up the new application.

```
yq -i e ".resources += [\"product-catalog-api\"]" gitops-workloads/commercial-staging/kustomization.yaml
```

## Connect to a workload cluster

To connect to `<cluster-name>` workload cluster using `kubeconfig` stored as a `Secret`

1. In a terminal window that is currently configured for the management cluster, obtain a
config file for the workload cluster using:

```bash
unset KUBECONFIG
kubectl -n flux-system get secret <cluster-name>-eks-connection -n flux-system -o jsonpath="{.data.value}" | base64 -d > wl-kube.conf
export KUBECONFIG=wl-kube.conf

kubectl config current-context
```
(Replace `<cluster-name>` with the cluster name).

2. To monitor the bootstrapping of the workload clusters (and subseuently for the
  deployment of the applications into it), list the `Kustomization` resources
  using the following command:

  ```bash
  kubectl get kustomization -n flux-system
  ```

## Upgrade an existing application

In this section you will push a new version of the application `product-catalog-api` in
the cluster `commercial-staging`. To achieve this, you need to update the release tag
in the app manifests in `gitops-workloads/commercial-staging/product-catalog-api`.
Once done, you then push the
changes so that flux can pick them up and act on them.


First, update the repo for `product-catalog-api` to the new version (v2):
```
cd ~/environment
cp -r multi-cluster-gitops/repos/apps-manifests/product-catalog-api-manifests/v2/* product-catalog-api-manifests/
cd product-catalog-api-manifests
git add .
git commit -m "Updated version"
git push origin main
```

Next, tag the current commit as version 2.0 and push the tag:
```
git tag -a v2.0 -m "Version 2.0"
git push origin v2.0
```

Update the release tag in `gitops-workloads/commercial-staging/product-catalog-api`. You
can do this using the `update-cluster-app.sh` script as follows:
```
cd ~/environment
multi-cluster-gitops/bin/update-cluster-app.sh ./gitops-workloads commercial-staging product-catalog-api v2.0
```

Finally, commit this change:
```
cd gitops-workloads
git add .
git commit -m "Updated product-catalog-api to v2.0 in commercial-staging"
git push
```

Monitor the reconciliation in the cluster. You can verify that the application deployment
has been updated by checking the deployment history:
```
kubectl rollout history deployment/product-catalog-api-staging -n product-catalog-api
```

You can also verify that the container image in the deployment has been updated:
```
kubectl describe deployment/product-catalog-api-staging -n product-catalog-api
```

### Detailed explanation of `update-cluster-app.sh` script


The `update-cluster-app.sh` script makes a single change as follows. Please ensure your working directory is set to `~/envionment` before executing.

```
yq -i e ".spec.ref.tag = \"v2.0\"" gitops-workloads/commercial-staging/product-catalog-api/git-repo.yaml
```


## Upgrade an existing cluster

In this section you will upgrade the cluster `commercial-staging` to a newer version
of Kubernetes. To achieve this, you need to update the cluster configuration
in `gitops-system/clusters-config/commercial-staging/def/eks-cluster.yaml`.
Once done, you then push the changes so that flux can pick them up and act on them.


1. Open `gitops-system/clusters-config/commercial-staging/def/eks-cluster.yaml`.

2. Change the value for `spec.parameters.k8s-version` (e.g. from `1.20` to `1.21`).

3. Commit changes.
```bash
cd ~/environment/gitops-system/
git add .
git commit -m "upgrading commercial-staging cluster"
git push
```

4. Confirm that the cluster is updating using:
```bash
eksctl get cluster --name commercial-staging --region $AWS_REGION
```

## Delete an application from a cluster

In this section you will delete the application `product-catalog-api` from
the cluster `commercial-staging`. To achieve this, you need to remove the
entry for this application from `gitops-workloads/commercial-staging/kustomization.yaml`.
Once done, you then push the changes so that flux can pick them up and act on them.
You also need to tidy up the `gitops-workloads/commercial-staging` directory by removing
the `product-catalog-api` directory.

You can make the required changes quickly using the script `remove-cluster-app.sh`:
```
cd ~/environment
multi-cluster-gitops/bin/remove-cluster-app.sh ./gitops-workloads commercial-staging product-catalog-api
```

Once done, commit and push the changes as follows:
```
cd gitops-workloads
git add .
git commit -m "Removed product-catalog-api from cluster commercial-staging"
git push
```

You can monitor the reconciliation of resources in the cluster using the 
method described previously.

### Detailed explanation of `remove-cluster-app.sh` script

The `remove-cluster-app.sh` script performs the following steps. You can choose to execute these steps instead of running the script. Please ensure your working directory is set to `~/envionment` before executing.

1. **Remove `product-catalog-api` from `gitops-workloads/commrical-staging/kustomization.yaml`:**
this forces Flux to remove the application resources from the cluster.
```
yq -i e "del ( .resources[] | select (. == \"product-catalog-api\" ))" gitops-workloads/commercial-staging/kustomization.yaml
```

2. **Tidy up `gitops-workloads/commercial-staging`:** remove the application folder from the
`gitops-workloads/commrical-staging` as it is no longer needed. 
```
rm -rf gitops-workloads/commercial-staging/product-catalog-api
```


## Delete an existing cluster

In this section you will delete the `commercial-staging` cluster. To achieve this, you
need to remove the entry for this cluster from `gitops-system/clusters-config/kustomization.yaml`.
this triggers Flux (via Crossplane) to remove the cluster.
You also need to tidy up various directories by removing the various cluster manifests.

Before proceeding, you should ensure that all applications running in the cluster
have been removed.

You can make the required repo changes quickly using the script `remove-cluster.sh`:
```
cd ~/environment
multi-cluster-gitops/bin/remove-cluster.sh ./gitops-system ./gitops-workloads commercial-staging
```

Once done, commit and push the changes as follows:
```
cd gitops-system
git add .
git commit -m "Removed cluster commercial-staging"
git push
cd ../gitops-workloads
git add .
git commit -m "Removed cluster commercial-staging"
git push
```

You can monitor the reconciliation of resources in the management cluster using 
```
kubectl get kustomization -n flux-system
```

### Detailed explanation of `remove-cluster.sh` script

The `remove-cluster.sh` script performs the following steps. You can choose to execute these steps instead of running the script. Please ensure your working directory is set to `~/environment` before executing.

1. **Remove `commercial-staging` from `gitops-system/clusters-config/kustomization.yaml`:**
this forces Flux to remove the application resources from the cluster.
```
yq -i e "del ( .resources[] | select (. == \"commercial-staging\" ))" gitops-system/clusters-config/kustomization.yaml
```

2. **Tidy up `gitops-system` and `gitops-workloads` repos:**

```
rm -rf gitops-system/clusters-config/commercial-staging
rm -rf gitops-system/clusters/commercial-staging
rm -rf gitops-system/workloads/commercial-staging
rm -rf gitops-workloads/commercial-staging
```
