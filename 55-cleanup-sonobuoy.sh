#!/bin/bash
set -e
# Cleaning up inside cluster
# We need to remove the LB and Storage resources
unset KUBECONFIG
if test -n "$1"; then
	SET="$1"
else
	if test -e cluster-settings.env; then SET=cluster-settings.env;
	else echo "You need to pass a cluster-settings.env file as parameter"; exit 1
	fi
fi
# Read settings -- make sure you can trust it
source "$SET"
#kubectl get cluster -A
KCFG=~/.kube/$CS_NAMESPACE.$CL_NAME
export KUBECONFIG=$KCFG
echo "Removing sonobuoy namespace from cluster -n $CS_NAMESPACE $CL_NAME"
kubectl delete namespace sonobuoy || true

