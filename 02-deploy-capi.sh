#!/bin/bash
# Rollout ORC, CAPI, CAPO
set -e
# We need settings (not really yet)
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
# Set feature flags
export CLUSTER_TOPOLOGY=true
export EXP_CLUSTER_RESOURCE_SET=true
export EXP_RUNTIME_SDK=true
# We must have the management cluster creds in ~/.kub/config
KUBECONFIG=${KUBECONFIG:-~/.kube/config}
if test ! -r $KUBECONFIG; then
	echo "ERROR: Must have KUBECONFIG for mgmt cluster in $KUBECONFIG"
	echo " You can create a management cluster with 01-kind-cluster.sh"
	exit 1
fi
# We need ORC these days and clusterctl has chosen to ignore that
kubectl apply -f https://github.com/k-orc/openstack-resource-controller/releases/latest/download/install.yaml
# Rollout capi and capo (assuming that orc gets deployed independently)
clusterctl init --infrastructure openstack
# Wait for completion
kubectl -n capi-system rollout status deployment
kubectl -n capo-system rollout status deployment
