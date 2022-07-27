#!/bin/bash
# $1 = location of gitops-system
# $2 = location of gitops-workloads
# $3 = cluster name

gitops_system=$(realpath "$1")
gitops_workloads=$(realpath "$2")
cluster_name=$3

# Remove $cluster_name from clusters-config/kustomization.yaml file
yq -i e "del ( .resources[] | select (. == \"$cluster_name\" ))" $gitops_system/clusters-config/kustomization.yaml

rm -rf $gitops_system/clusters-config/$cluster_name
rm -rf $gitops_system/clusters/$cluster_name
rm -rf $gitops_system/workloads/$cluster_name
rm -rf $gitops_workloads/$cluster_name