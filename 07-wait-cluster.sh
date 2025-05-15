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
# ToDo: Wait for cluster
echo "The cluster should exist now"
echo "WARN: Waiting not yet implemented"
set -x
clusterctl describe cluster -n "$CS_NAMESPACE" $CL_NAME
echo clusterctl get kubeconfug -n "$CS_NAMESPACE" $CL_NAME > "~/.kube/$CS_NAMESPACE.$CL_NAME.yaml"
