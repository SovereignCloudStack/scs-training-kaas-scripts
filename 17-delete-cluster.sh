#!/bin/bash
set -e
# We need settings
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
# Sanity checks 
if test -z "$CS_NAMESPACE"; then echo "Configure CS_NAMESPACE"; exit 2; fi
if test -z "$CL_NAME"; then echo "Configure CL_NAME"; exit 5; fi
# Delete Cluster
kubectl delete -n "$CS_NAMESPACE" cluster "$CL_NAME"
