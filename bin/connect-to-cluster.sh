#!/bin/bash
# $1 = cluster name

# Creates kubeconfig file and sources KUBECONFIG environment variable
# to connect to cluster.
#
# To use the script use the source command at the terminal to make sure
# the KUBECONFIG environment variable is exported.
# Example: source ~/environment/eks-multi-cluster-gitops/bin/connect-to-cluster.sh <cluster name>

WORKLOAD_CLUSTER_NAME=$1
KUBECONFIG_DEFAULT_DIR=~/.kube
unset KUBECONFIG
if [ ! -d $KUBECONFIG_DEFAULT_DIR ]; then
  echo "Directory $KUBECONFIG_DEFAULT_DIR does not exist"
  echo "Creating directory..."
  mkdir -p $KUBECONFIG_DEFAULT_DIR
fi
pushd $KUBECONFIG_DEFAULT_DIR
echo "Generating kubeconfig file..."
kubectl -n flux-system get secret $WORKLOAD_CLUSTER_NAME-eks-connection -n flux-system -o jsonpath="{.data.value}" | base64 -d > wl-kube.conf
export KUBECONFIG=$KUBECONFIG_DEFAULT_DIR/wl-kube.conf
kubectl config current-context
popd