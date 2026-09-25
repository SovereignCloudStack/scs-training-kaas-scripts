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
if test -z "$CS_SERIES"; then echo "Configure CS_SERIES, default to scs2"; CS_SERIES=scs2; fi
#
# Fill in CS_VERSIONS if needed
REPO="registry.scs.community/kaas/cluster-stacks"
if test "$CS_VERSION" = "all"; then
	echo "# Info: CS_VERSION not specified, retrieve from scs registry with oras ..."
	CS_VERSION=$(oras repo tags "$REPO" | tail -n +2 | grep "openstack-$CS_SERIES-${CS_MAINVER/./-}" | sed "s@openstack\-$CS_SERIES\\-${CS_MAINVER/./-}\-@@g" | tr "\n" "," | sed -e 's@git-@git.@g' -e 's@sha-@sha.@g')
	CS_VERSION="[ ${CS_VERSION%,} ]"
	echo "# Info: CS_VERSION set to $CS_VERSION"
elif test -z "$CS_VERSION"; then
	echo "# Info: CS_VERSION not specified, retrieve from scs registry with oras ..."
	CS_VERSION=$(oras repo tags "$REPO" | tail -n +2 | grep "openstack-$CS_SERIES-${CS_MAINVER/./-}" | sed "s@openstack\-$CS_SERIES\\-${CS_MAINVER/./-}\-@@g" | grep -v git | grep -v sha | tr "\n" ",")
	CS_VERSION="[ ${CS_VERSION%,} ]"
	echo "# Info: CS_VERSION set to $CS_VERSION"
fi
# If we have an array, match what CS_VERSION we want to wait for
if test "${CS_VERSION:0:1}" = "["; then
	VERSIONS="$(echo $CS_VERSION | sed -e 's/\[//' -e 's/\]//' -e 's/,/ /g')"
	for ver in $VERSIONS; do
		echo "Wait for clusterstackrelease -n $CS_NAMESPACE openstack-${CS_SERIES}-${CS_MAINVER/./-}-${ver/./-} creation"
		kubectl wait -n "$CS_NAMESPACE" clusterstackrelease openstack-${CS_SERIES}-${CS_MAINVER/./-}-${ver/./-} --for create
	done
	VERSIONS=$(kubectl get clusterstackreleases -n $CS_NAMESPACE -o "custom-columns=NAME:.metadata.name,K8SVER:.status.kubernetesVersion")
	echo -e "# Table of registered clusterstackreleases:\n$VERSIONS"
	CVERSIONS=()
	while read csnm k8sver; do
		if test "$csnm" = "NAME"; then continue; fi
		if test "$k8sver" = "v$CL_PATCHVER"; then
			CS_VERSION="v${csnm#openstack-${CS_SERIES}-?-??-v}"
			CS_VERSION="${CS_VERSION//-/.}"
			CS_VERSION="${CS_VERSION/./-}"
			#echo "$CS_VERSION"
			CVERSIONS[${#CVERSIONS[*]}]="$CS_VERSION"
			#break
		fi
	done < <(echo "$VERSIONS")
	if test -z "$CVERSIONS"; then
		echo "No clusterstackrelease with v$CL_PATCHVER found"
	fi
	# Prefer highest
	CS_VERSION=$(echo "${CVERSIONS[*]}" | tr ' ' '\n' | sort -r | head -n1)
else
	echo "Wait for clusterstackrelease -n $CS_NAMESPACE openstack-${CS_SERIES}-${CS_MAINVER/./-}-${CS_VERSION/./-} readiness"
	kubectl wait -n "$CS_NAMESPACE" clusterstackrelease openstack-${CS_SERIES}-${CS_MAINVER/./-}-${CS_VERSION/./-} --for condition=ready
fi
echo "# Wait for clusterclass -n $CS_NAMESPACE openstack-${CS_SERIES}-${CS_MAINVER/./-}-${CS_VERSION} creation"
kubectl wait -n "$CS_NAMESPACE" clusterclass openstack-${CS_SERIES}-${CS_MAINVER/./-}-${CS_VERSION} --for create
kubectl get clusterclasses -n "$CS_NAMESPACE"
kubectl get images -n "$CS_NAMESPACE"
