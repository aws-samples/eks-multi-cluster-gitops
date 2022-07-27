#!/bin/bash
# $1 = location of app manifests local repo
# $2 = cluster name
# $3 = app name
# $4 = name suffix

app_manifests=$(realpath "$1")
cluster_name=$2
app_name=$3
name_suffix=$4

mkdir $app_manifests/kubernetes/overlays/$cluster_name

cat <<EoF >$app_manifests/kubernetes/overlays/$cluster_name/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- ../../base
namespace: $app_name
nameSuffix: $name_suffix
patchesStrategicMerge:
EoF