#!/bin/bash
# $1 = location of gitops-workloads
# $2 = cluster name
# $3 = app name
# $4 = Sealed secrets public key .pem file

gitops_workloads=$(realpath "$1")
cluster_name=$2
app_name=$3
pem_file=$4

cp -R $gitops_workloads/template/app-template $gitops_workloads/$cluster_name/$app_name
grep -RiIl 'cluster-name' $gitops_workloads/$cluster_name/$app_name | xargs sed -i "s/cluster-name/$cluster_name/g"
grep -RiIl 'app-name' $gitops_workloads/$cluster_name/$app_name | xargs sed -i "s/app-name/$app_name/g"
cp $gitops_workloads/$cluster_name/$app_name/git-secret.yaml /tmp/git-secret.yaml
kubeseal --cert $pem_file --format yaml </tmp/git-secret.yaml >$gitops_workloads/$cluster_name/$app_name/git-secret.yaml

pushd $gitops_workloads
git add .
git commit -m "adding app: $app_name to cluster: $cluster_name "
git push
popd