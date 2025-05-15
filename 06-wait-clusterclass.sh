#!/bin/bash
#
# Do we need this?
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
# ToDo: Wait for cluster class
echo "The clusterclass should exist now"
echo "WARN: Waiting not yet implemented"
set -x
kubectl get clusterclasses -n "$CS_NAMESPACE"
kubectl get images -n "$CS_NAMESPACE"
