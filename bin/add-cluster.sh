#!/bin/bash
# $1 = location of gitops-system
# $2 = cluster name

gitops_system=$(realpath "$1")
cluster_name=$2

# gitops-system clusters-config template

mkdir -p $gitops_system/clusters-config/$cluster_name
cp -R $gitops_system/clusters-config/template/* $gitops_system/clusters-config/$cluster_name
grep -RiIl 'cluster-name' $gitops_system/clusters-config/$cluster_name | xargs sed -i "s/cluster-name/$cluster_name/g"

# gitops-system clusters template

mkdir -p $gitops_system/clusters/$cluster_name
cp -R $gitops_system/clusters/template/* $gitops_system/clusters/$cluster_name
grep -RiIl 'cluster-name' $gitops_system/clusters/$cluster_name | xargs sed -i "s/cluster-name/$cluster_name/g"

# gitops-system workloads template

mkdir -p $gitops_system/workloads/$cluster_name
cp -R $gitops_system/workloads/template/* $gitops_system/workloads/$cluster_name
grep -RiIl 'cluster-name'  $gitops_system/workloads/$cluster_name | xargs sed -i "s/cluster-name/$cluster_name/g"

# Add $cluster_name to clusters-config/kustomization.yaml file

yq -i e ".resources += [\"$cluster_name\"]" $gitops_system/clusters-config/kustomization.yaml