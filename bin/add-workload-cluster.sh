#!/bin/bash
# $1 = cluster name
# $2 = location of gitops-system

working_dir=$(pwd)

cluster_name=$1
gitops_system=$(realpath "$2")

# clusters-config

cp -R $gitops_system/clusters-config/template $gitops_system/clusters-config/$cluster_name
grep -RiIl 'cluster-name' $gitops_system/clusters-config/$cluster_name | xargs sed -i "s/cluster-name/$cluster_name/g"

# clusters

cp -R $gitops_system/clusters/template $gitops_system/clusters/$cluster_name
grep -RiIl  'cluster-name' $gitops_system/clusters/$cluster_name | xargs sed -i "s/cluster-name/$cluster_name/g"

# workloads template

cp -R $gitops_system/workloads/template $gitops_system/workloads/$cluster_name
grep -RiIl  'cluster-name'  $gitops_system/workloads/$cluster_name | xargs sed -i "s/cluster-name/$cluster_name/g"

Update kustomization

7. Add <cluster-name> to clusters-config/kustomization.yaml file.
```bash
 ---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - commercial-staging
  - <cluster-name>
```

# Ensure we exit with the same working dir where we started
cd $working_dir