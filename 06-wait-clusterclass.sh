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
kubectl wait -n "$CS_NAMESPACE" clusterclass openstack-scs-${CS_MAINVER/./-}-${CS_VERSION} --for create
kubectl get clusterclasses -n "$CS_NAMESPACE"
kubectl get images -n "$CS_NAMESPACE"
kubectl wait -n "$CS_NAMESPACE" clusterstackrelease openstack-scs-${CS_MAINVER/./-}-${CS_VERSION/./-} --for condition=ready
