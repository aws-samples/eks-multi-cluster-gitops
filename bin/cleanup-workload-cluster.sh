#!/bin/bash
# $1 = cluster name
# $2 = location of gitops-system
# $3 = location of gitops-workloads


cluster_name=$1
gitops_system=$(realpath "$2")
gitops_workloads=$(realpath "$3")

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