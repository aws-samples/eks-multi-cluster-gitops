#!/bin/bash
# $1 = location of gitops-system
# $2 = cluster name


gitops_system=$(realpath "$1")
cluster_name=$2

# Remove $cluster_name from clusters-config/kustomization.yaml file
yq -i e "del ( .resources[] | select (. == \"$cluster_name\" ))" $gitops_system/clusters-config/kustomization.yaml

# Commit change
pushd $gitops_system
git add .
git commit -m "deleting $cluster_name cluster"
git push
popd
