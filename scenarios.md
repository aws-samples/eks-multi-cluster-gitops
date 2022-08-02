# Scenarios

This document walks you through steps for a number of scenarios including:
- Adding and removing a workload cluster
- Adding and removing an application to / from a workload cluster
- Connecting to a workload cluster to check reconciliation status
- Upgrading a workload cluster

For illustration purposes, these scenarios are based on the example of a product catalog application developed by the commercial department of an organisation.
- The department
runs two clusters `commercial-staging` and `commercial-prod`.
- The product catalog application comprises two microservices which are owned by different teams.
  - API server: this provides the backend, and makes use of an AWS DynamoDB table to store its state.
  - Front end server: provides a web front end service that can be accessed via a browser.

## Provision and bootstrap a new cluster

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

### Detailed explanation of `add-cluster.sh` script

The `add-cluster.sh` script performs the following steps. You can choose to execute these steps instead of running the script. Please ensure your working directory is set to `~/envionment` before executing.

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
, and update `commercial-staging/kustomization.yaml` Once done, you then push the
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

You can make the required changes quickly using the script `add-cluster-app.sh`:
```
cd ~/environment
multi-cluster-gitops/bin/add-cluster-app.sh \
  ./gitops-workloads \
  commercial-staging product-catalog-api \
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

### Detailed explanation

MORE TO COME HERE



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



## Upgrade an existing cluster
1. Open `gitops-system/clusters-config/<cluster-name>/def/eks-cluster.yaml`.

(Replace `<cluster-name>` with the cluster name).

2. Change the value for `spec.parameters.k8s-version` (e.g. from `1.20` to `1.21`).

3. Commit changes.
```bash
cd ~/environment/gitops-system/
git add .
git commit -m "upgrading <cluster-name> cluster"
git push
```
(Replace `<cluster-name>` with the new cluster name).

4. Confirm cluster updating. 
```bash
eksctl get cluster --name <cluster-name> --region <region-name> 
```

## Delete an existing cluster
1. Delete the deployed applications from the cluster by following the instructions in delete an application from a cluster section, and wait for the applications to be removed.

2. Delete the line in `gitops-system/clusters-config/kustomization.yaml` that corresponds to the cluster.
3. Commit changes, and wait for the cluster to be removed.

```bash
cd ~/environment/gitops-system/
git add .
git commit -m "removing <cluster-name> cluster"
git push
```
(Replace `<cluster-name>` with the cluster name).

4. Delete `gitops-system/clusters-config/<cluster-name>`.

(Replace `<cluster-name>` with the cluster name).

5. Delete `gitops-system/clusters/<cluster-name>`.

(Replace `<cluster-name>` with the cluster name).

6. Delete `gitops-system/workloads/<cluster-name>`.

(Replace `<cluster-name>` with the cluster name).

7. Delete `gitops-workloads/<cluster-name>`.

(Replace `<cluster-name>` with the cluster name).


## Onboard a new application into a cluster

1. Make a copy of `app-template` for the new application in `gitops-workloads`.

```bash
cd ~/environment/gitops-workloads/<cluster-name>
mkdir <app-name>
cp -R app-template/* <app-name>/
cd <app-name>
grep -RiIl  'app-name' . | xargs sed -i 's/app-name/<app-name>/g'
```

(Replace `<app-name>` with the application name, and replace `<cluster-name>` with the cluster name).

2. Update the git repo for an application in `gitops-worklaods/<cluster-name>/<app-name>/git-repo.yaml`.

(Replace `<app-name>` with the application name, and replace `<cluster-name>` with the cluster name).

3. Create sealed secrets for the new application. 

```bash
cd ~/environment
cp git-creds-system.yaml git-creds-<app-name>.yaml
yq e '.metadata.name="<app-name>"' -i git-creds-<app-name>.yaml
kubeseal --cert sealed-secrets-keypair-public.pem --format yaml <git-creds-<app-name>.yaml >git-creds-sealed-<app-name>.yaml
cp git-creds-sealed-<app-name>.yaml gitops-workloads/<cluster-name>/<app-name>/git-secret.yaml
```

(Replace `<app-name>` with the application name, and replace `<cluster-name>` with the cluster name).

4. Add an entry for the application in `gitops-workloads/<cluster-name>/kustomization.yaml`.

5. Commit changes.

```bash
cd ~/environment/gitops-workloads/
git add .
git commit -m "onboarding <app-name> into <cluster-name>"
git push
```
(Replace `<app-name>` with the application name, and replace `<cluster-name>` with the cluster name).

## Delete an application from a cluster

1. Delete the entry in `gitops-workloads/<cluster-name>/kustomization.yaml` that corresponds to the application.

(Replace `<cluster-name>` with the cluster name).

2. Delete `gitops-workloads/<cluster-name>/<app-name>`.

(Replace `<app-name>` with the application name, and replace `<cluster-name>` with the cluster name).

3. Commit the changes.

```bash
cd ~/environment/gitops-workloads/
git add .
git commit -m "removing <app-name> from <cluster-name>"
git push
```

(Replace `<app-name>` with the application name, and replace `<cluster-name>` with the cluster name).
