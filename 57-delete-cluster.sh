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
echo "# Please ensure you have emptied the cluster from resources that create PVs or LBs"
sleep 2
kubectl delete -n "$CS_NAMESPACE" cluster "$CL_NAME"
if test -n "$CL_APPCRED_LIFETIME" -a "$CL_APPCRED_LIFETIME" != "0"; then
	echo "# Cleaning up secrets and Application Credential"
	kubectl delete -n $CS_NAMESPACE clusterresourceset crs-openstack-newsecret-$CL_NAME
	kubectl delete -n $CS_NAMESPACE clusterresourceset crs-openstack-secret-$CL_NAME
	kubectl delete -n $CS_NAMESPACE secret openstack-workload-cluster-newsecret-$CL_NAME 2>/dev/null || true
	kubectl delete -n $CS_NAMESPACE secret openstack-workload-cluster-secret-$CL_NAME 2>/dev/null || true
	openstack application credential delete "CS-$CS_NAMESPACE-$CL_NAME-AppCred1" "CS-$CS_NAMESPACE-$CL_NAME-AppCred2" 2>/dev/null || true
fi
