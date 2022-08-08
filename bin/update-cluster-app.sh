#!/bin/bash
# $1 = location of gitops-workloads
# $2 = cluster name
# $3 = app name
# $4 = git release tag

gitops_workloads=$(realpath "$1")
cluster_name=$2
app_name=$3
release_tag=$4

yq -i e ".spec.ref.tag = \"$release_tag\"" $gitops_workloads/$cluster_name/$app_name/git-repo.yaml