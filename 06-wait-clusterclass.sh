#!/bin/bash
#
# Do we need this?
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
# If we have an array, match what CS_VERSION we want to wait for
if test "${CS_VERSION:0:1}" = "["; then
	VERSIONS="$(echo $CS_VERSION | sed -e 's/\[//' -e 's/\]//' -e 's/,/ /g')"
	for ver in $VERSIONS; do
		#echo "Wait for clusterstackrelease -n $CS_NAMESPACE openstack-scs-${CS_MAINVER/./-}-${ver/./-} readiness"
		echo "Wait for clusterstackrelease -n $CS_NAMESPACE openstack-scs-${CS_MAINVER/./-}-${ver/./-} creation"
		kubectl wait -n "$CS_NAMESPACE" clusterstackrelease openstack-scs-${CS_MAINVER/./-}-${ver/./-} --for create
	done
	VERSIONS=$(kubectl get clusterstackreleases -n $CS_NAMESPACE -o "custom-columns=NAME:.metadata.name,K8SVER:.status.kubernetesVersion")
	echo -e "# Table of registered clusterstackreleases:\n$VERSIONS"
	while read csnm k8sver; do
		if test "$csnm" = "NAME"; then continue; fi
		if test "$k8sver" = "v$CL_PATCHVER"; then
			CS_VERSION="v${csnm#openstack-scs-?-??-v}"
			CS_VERSION="${CS_VERSION//-/.}"
			CS_VERSION="${CS_VERSION/./-}"
			break
		fi
	done < <(echo "$VERSIONS")
	if test "${CS_VERSION:0:1}" = "["; then
		echo "No clusterstackrelease with v$CL_PATCHVER found"
	fi
else
	echo "Wait for clusterstackrelease -n $CS_NAMESPACE openstack-scs-${CS_MAINVER/./-}-${CS_VERSION/./-} readiness"
	kubectl wait -n "$CS_NAMESPACE" clusterstackrelease openstack-scs-${CS_MAINVER/./-}-${CS_VERSION/./-} --for condition=ready
fi
echo "# Wait for clusterclass -n $CS_NAMESPACE openstack-scs-${CS_MAINVER/./-}-${CS_VERSION} creation"
kubectl wait -n "$CS_NAMESPACE" clusterclass openstack-scs-${CS_MAINVER/./-}-${CS_VERSION} --for create
kubectl get clusterclasses -n "$CS_NAMESPACE"
kubectl get images -n "$CS_NAMESPACE"
