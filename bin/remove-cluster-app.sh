#!/bin/bash
# $1 = location of gitops-workloads
# $2 = cluster name
# $3 = app_name


gitops_workloads=$(realpath "$1")
cluster_name=$2
app_name=$3

# Remove $cluster_name from clusters-config/kustomization.yaml file
yq -i e "del ( .resources[] | select (. == \"$app_name\" ))"  $gitops_workloads/$cluster_name/kustomization.yaml

# Remove app folder from cluster folder

rm -rf $gitops_workloads/$cluster_name/$app_name