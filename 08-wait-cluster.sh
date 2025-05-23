#!/bin/bash
# Wait for cluster
set -e
# We need settings
if test -n "$1"; then
	SET="$1"
else
	if test -e cluster-settings.env; then SET=cluster-settings.env;
	else echo "You need to pass a cluster-settings.env file as parameter"; exit 1
	fi
fi
# Read settings -- make sure you can trust it
source "$SET"
kubectl get cluster -A
#set -x
kubectl wait --timeout=14m --for=condition=certificatesavailable -n "$CS_NAMESPACE" kubeadmcontrolplanes -l cluster.x-k8s.io/cluster-name=$CL_NAME
kubectl get -n "$CS_NAMESPACE" cluster $CL_NAME
clusterctl describe cluster -n "$CS_NAMESPACE" $CL_NAME --grouping=false
KCFG=~/.kube/$CS_NAMESPACE.$CL_NAME
clusterctl get kubeconfig -n "$CS_NAMESPACE" $CL_NAME > $KCFG
KUBECONFIG=$KCFG kubectl get nodes -o wide
KUBECONFIG=$KCFG kubectl get pods -A
echo "# Hint: Use KUBECONFIG=$KCFG kubectl ... to access you workload cluster $CS_NAMESPACE/$CL_NAME"
