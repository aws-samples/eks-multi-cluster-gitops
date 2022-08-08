#!/bin/bash
# $1 = location of gitops-workloads
# $2 = cluster name
# $3 = app name
# $4 = git release tag
# $5 = location of git-credentials template file
# $6 = private key file
# $7 = public key
# $8 = known hosts
# $9 = Sealed secrets public key .pem file

gitops_workloads=$(realpath "$1")
cluster_name=$2
app_name=$3
release_tag=$4
git_creds_file=$(realpath "$5")
private_key_file=$(realpath "$6")
public_key_file=$(realpath "$7")
known_hosts=$8
pem_file=$(realpath "$9")

mkdir -p $gitops_workloads/$cluster_name/$app_name
if [[ ! -f $gitops_workloads/$cluster_name/kustomization.yaml ]]
then
    cp $gitops_workloads/template/kustomization.yaml $gitops_workloads/$cluster_name
fi
cp -R $gitops_workloads/template/app-template/* $gitops_workloads/$cluster_name/$app_name
grep -RiIl 'cluster-name' $gitops_workloads/$cluster_name/$app_name | xargs sed -i "s/cluster-name/$cluster_name/g"
grep -RiIl 'app-name' $gitops_workloads/$cluster_name/$app_name | xargs sed -i "s/app-name/$app_name/g"
grep -RiIl 'release-tag' $gitops_workloads/$cluster_name/$app_name | xargs sed -i "s/release-tag/$release_tag/g"


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