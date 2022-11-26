#!/bin/bash
# $1 = location of gitops-workloads
# $2 = cluster name
# $3 = app name
# $4 = overlay directory name
# $5 = git branch name
# $6 = location of git-credentials template file
# $7 = private key file
# $8 = public key
# $9 = known hosts
# $10 = Sealed secrets public key .pem file

gitops_workloads=$(realpath "$1")
cluster_name=$2
app_name=$3
overlay_dir_name=$4
branch_name=$5
git_creds_file=$(realpath "$6")
private_key_file=$(realpath "$7")
public_key_file=$(realpath "$8")
known_hosts=$9
pem_file=$(realpath "${10}")

mkdir -p $gitops_workloads/$cluster_name/$app_name
if [[ ! -f $gitops_workloads/$cluster_name/kustomization.yaml ]]
then
    cp $gitops_workloads/template/kustomization.yaml $gitops_workloads/$cluster_name
fi
cp -R $gitops_workloads/template/app-template/* $gitops_workloads/$cluster_name/$app_name
grep -RiIl 'cluster-name' $gitops_workloads/$cluster_name/$app_name | xargs sed -i "s/cluster-name/$cluster_name/g"
grep -RiIl 'overlay-dir-name' $gitops_workloads/$cluster_name/$app_name | xargs sed -i "s/overlay-dir-name/$overlay_dir_name/g"
grep -RiIl 'app-name' $gitops_workloads/$cluster_name/$app_name | xargs sed -i "s/app-name/$app_name/g"
grep -RiIl 'branch-name' $gitops_workloads/$cluster_name/$app_name | xargs sed -i "s/branch-name/$branch_name/g"


# Prep the sealed secret

tmp_git_creds=$(mktemp /tmp/git-creds.yaml.XXXXXXXXX)
cp $git_creds_file $tmp_git_creds
APP_NAME=$app_name yq e '.metadata.name=strenv(APP_NAME)' -i $tmp_git_creds
KEY=$(cat $private_key_file | base64 -w 0) yq -i '.data.identity = strenv(KEY)' $tmp_git_creds
CERT=$(cat $public_key_file | base64 -w 0) yq -i '.data."identity.pub" = strenv(CERT)' $tmp_git_creds
HOSTS=$(echo $known_hosts | base64 -w 0) yq -i '.data.known_hosts = strenv(HOSTS)' $tmp_git_creds
kubeseal --cert $pem_file --format yaml <$tmp_git_creds >$gitops_workloads/$cluster_name/$app_name/git-secret.yaml
rm $tmp_git_creds

# Add to kustomization.yaml

yq -i e ".resources += [\"$app_name\"]" $gitops_workloads/$cluster_name/kustomization.yaml