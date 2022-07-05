#!/bin/bash
# $1 = cluster name
# $2 = location of gitops-system

cluster_name=$1
gitops_system=$(realpath "$2")

# Remove $cluster_name from clusters-config/kustomization.yaml file
yq -i e "del ( .resources[] | select (. == \"$cluster_name\" ))" $gitops_system/clusters-config/kustomization.yaml

# Commit change
pushd $gitops_system
git add .
git commit -m "deleting $cluster_name cluster"
git push
popd
