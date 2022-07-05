#!/bin/bash
# $1 = cluster name
# $2 = location of gitops-system

cluster_name=$1
gitops_system=$(realpath "$2")

# This script assumes that all templates for the new cluster have already been created

# Add $cluster_name to clusters-config/kustomization.yaml file, and push

yq -i e ".resources += [\"$cluster_name\"]" $gitops_system/clusters-config/kustomization.yaml

pushd $gitops_system
git add .
git commit -m "adding $cluster_name cluster"
git push
popd
