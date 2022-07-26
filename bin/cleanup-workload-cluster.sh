#!/bin/bash
# $1 = location of gitops-system
# $2 = location of gitops-workloads
# $3 = cluster name

gitops_system=$(realpath "$1")
gitops_workloads=$(realpath "$2")
cluster_name=$3

# Remove cluster folders from repos

rm -rf $gitops_system/clusters-config/$cluster_name
rm -rf $gitops_system/clusters/$cluster_name
rm -rf $gitops_system/workloads/$cluster_name
rm -rf $gitops_workloads/$cluster_name

pushd $gitops_system
git rm -r $gitops_system/clusters-config/$cluster_name
git rm -r $gitops_system/clusters/$cluster_name
git rm -r $gitops_system/workloads/$cluster_name
git commit -m "cleaning up $cluster_name cluster"
git push
popd

pushd $gitops_workloads
git rm -r $gitops_workloads/$cluster_name
git commit -m "cleaning up $cluster_name cluster"
git push
popd