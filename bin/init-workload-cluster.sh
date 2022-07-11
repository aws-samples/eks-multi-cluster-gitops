#!/bin/bash
# $1 = cluster name
# $2 = location of gitops-system
# $3 = location of gitops-workloads

cluster_name=$1
gitops_system=$(realpath "$2")
gitops_workloads=$(realpath "$3")

# gitops-system clusters-config template

cp -R $gitops_system/clusters-config/template $gitops_system/clusters-config/$cluster_name
grep -RiIl 'cluster-name' $gitops_system/clusters-config/$cluster_name | xargs sed -i "s/cluster-name/$cluster_name/g"

# gitops-system clusters template

cp -R $gitops_system/clusters/template $gitops_system/clusters/$cluster_name
grep -RiIl 'cluster-name' $gitops_system/clusters/$cluster_name | xargs sed -i "s/cluster-name/$cluster_name/g"

# gitops-system workloads template

cp -R $gitops_system/workloads/template $gitops_system/workloads/$cluster_name
grep -RiIl 'cluster-name'  $gitops_system/workloads/$cluster_name | xargs sed -i "s/cluster-name/$cluster_name/g"

# workloads template
cp -R $gitops_workloads/template $gitops_workloads/$cluster_name
grep -RiIl 'cluster-name'  $gitops_workloads/$cluster_name | xargs sed -i "s/cluster-name/$cluster_name/g"


pushd $gitops_system
git add .
git commit -m "adding $cluster_name cluster"
git push
popd

pushd $gitops_workloads
git add .
git commit -m "adding $cluster_name cluster"
git push
popd