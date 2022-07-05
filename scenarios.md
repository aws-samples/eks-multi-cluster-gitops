## Provision and bootstrap a new cluster

1. Make a copy of the cluster definition template folder for the new cluster.

```bash
cd ~/environment/gitops-system/clusters-config
mkdir <cluster-name>
cp -R template/* <cluster-name>/
cd <cluster-name>
grep -RiIl  'cluster-name' . | xargs sed -i 's/cluster-name/<cluster-name>/g'
```
(Replace `<cluster-name>` with the new cluster name).

2. Make a copy of the cluster template folder for the new cluster.

```bash
cd ~/environment/gitops-system/clusters
mkdir <cluster-name>
cp -R template/* <cluster-name>/
cd <cluster-name>
grep -RiIl  'cluster-name' . | xargs sed -i 's/cluster-name/<cluster-name>/g'
```
(Replace `<cluster-name>` with the new cluster name).

3. Make a copy of the workloads template folder in `gitops-system` for the new cluster.

```bash
cd ~/environment/gitops-system/workloads
mkdir <cluster-name>
cp -R template/* <cluster-name>/
cd <cluster-name>
grep -RiIl  'cluster-name' . | xargs sed -i 's/cluster-name/<cluster-name>/g'
```
(Replace `<cluster-name>` with the new cluster name).


4. Make a copy of the workloads template folder in `clusters-config` for the new cluster.

```bash
cd ~/environment/clusters-config
mkdir <cluster-name>
cp -R template/* <cluster-name>/
cd <cluster-name>
grep -RiIl  'cluster-name' . | xargs sed -i 's/cluster-name/<cluster-name>/g'
```
(Replace `<cluster-name>` with the new cluster name).


5. Add <cluster-name> to clusters-config/kustomization.yaml file.
```bash
 ---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - commercial-staging
  - <cluster-name>
```
  
6. Commit changes
```bash
cd ~/environment/gitops-system/
git add .
git commit -m "adding <cluster-name> cluster"
git push
```
(Replace `<cluster-name>` with the new cluster name).


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
cd red
grep -RiIl  'app-name' . | xargs sed -i 's/app-name/<app-name>/g'
```

(Replace `<app-name>` with the application name, and replace `<cluster-name>` with the cluster name).

2. Update the git credentials for the application git repo in `gitops-worklaods/<cluster-name>/<app-name>/git-repo.yaml`.

(Replace `<app-name>` with the application name, and replace `<cluster-name>` with the cluster name).

3. Add an entry for the application in `gitops-workloads/<cluster-name>/kustomization.yaml`.

4. Commit changes.

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
