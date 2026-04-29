#!/bin/bash
set -e
# We need settings
# unset KUBECONFIG
if test -n "$1"; then
	SET="$1"
	shift
else
	if test -e cluster-settings.env; then SET=cluster-settings.env;
	else echo "You need to pass a cluster-settings.env (target cluster) as parameter"; exit 1
	fi
fi
# Read settings -- make sure you can trust it
source "$SET"
unset KUBECONFIG
# Read helper
THISDIR=$(dirname $0)
source "$THISDIR/_yaml_parse.sh"
# Sanity checks 
if test -z "$CS_MAINVER"; then echo "Configure CS_MAINVER"; exit 2; fi
if test -z "$CS_VERSION"; then echo "Configure CS_VERSION"; exit 3; fi
if test -z "$CS_SERIES"; then echo "Configure CS_SERIES, default to scs2"; CS_SERIES=scs2; fi
if test -z "$CL_PATCHVER"; then echo "Configure CL_PATCHVER"; exit 4; fi
if test -z "$CL_NAME"; then echo "Configure CL_NAME"; exit 5; fi
if test -z "$CL_PODCIDR"; then echo "Configure CL_PODCIDR"; exit 6; fi
if test -z "$CL_SVCCIDR"; then echo "Configure CL_SVCCIDR"; exit 7; fi
if test -z "$CL_CTRLNODES"; then echo "Configure CL_CTRLNODES"; exit 8; fi
if test -z "$CL_WRKRNODES"; then echo "Configure CL_WRKRNODES"; exit 9; fi
# What cluster objects to move?
if test -z "$1"; then
	echo "Usage: 30-clusterctl-move.sh TARGET.env SRCNAMESPACE"
	echo "This moves the cso/capi/capo objects and secrets from the old management cluster's"
	echo " namespace SRCNAMESPACE to a new mgmt cluster created with TARGET.env"
	exit 2
fi
SRC_NS="$1"
# Pre-flight checks
# Extract image version
# $1 namespace
getver()
{
	local POD
	POD=$(kubectl get -n $1 pods | awk '{print $1;}' | grep -v NAME | head -n1)
	VER=$(kubectl get -n $1 pod $POD -o jsonpath='{.spec.containers[].image}')
	VER=${VER##*:}
	echo "$VER"
}
# Check for capi, capo, cso
CAPI_VER=$(getver capi-system)
if test -z "$CAPI_VER"; then echo "No CAPI in src mgmt cluster"; exit 10; fi
CAPO_VER=$(getver capo-system)
if test -z "$CAPO_VER"; then echo "No CAPO in src mgmt cluster"; exit 11; fi
CSO_VER=$(getver cso-system)
if test -z "$CSO_VER"; then echo "No CSO in src mgmt cluster"; exit 12; fi
echo "# CAPI $CAPI_VER CAPO $CAPO_VER CSO $CSO_VER"
# Check for objects in namespace
kubectl get -n $SRC_NS secrets >/dev/null 2>&1
if test $? != 0; then echo "No secrets in src mgmt cluster in namespace $SRC_NS"; exit 13; fi
# Install capi/capo/orc in target
export NEW_KUBECONFIG=~/.kube/$CS_NAMESPACE.$CL_NAME
echo "# Deploying CAPI, CAPO, CSO to $CL_NAME cluster in $CS_NAMESPACE ..."
./02-deploy-capi.sh $SET --infrastructure openstack:$CAPO_VER --core cluster-api:$CAPI_VER --control-plane kubeadm:$CAPI_VER --bootstrap kubeadm:$CAPI_VER
./03-deploy-cso.sh $SET
# 04: Secret will be moved
# 05: CStack will be moved
# clusterctl move
clusterctl move --to-kubeconfig=$NEW_KUBECONFIG -n $SRC_NS
# Add cluster-admin of target to ~/.kube/config
cp -p ~/.kube/config ~/.kube/config.old
OLDCTX=$(kubectl config get-contexts | grep '^*' | awk '{print $2;}')
NEWCTX=$(KUBECONFIG=$NEW_KUBECONFIG kubectl config get-contexts | grep '^*' | awk '{print $2;}')
KUBECONFIG="~/.kube/config.old:$NEW_KUBECONFIG" kubectl config view --flatten > ~/.kube/config
kubectl config set-context "$OLDCTX"
# Output message how to select it ...
echo "Use kubectl set-context $NEWCTX to switch to using new mgmt cluster"



