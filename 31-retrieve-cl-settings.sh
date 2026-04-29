#!/bin/bash
usage()
{
	echo "Usage: 31-retrieve-settings.sh namespace"
	exit 1
}

if test -z "$1"; then usage; fi
# Read helper
THISDIR=$(dirname $0)
source "$THISDIR/_yaml_parse.sh"
# Read settings
unset KUBECONFIG
CS_NAMESPACE="$1"

# Remove one item from a newline separated list
# $1: item to remove
# $@: list
# Return: stdout
rmv_list()
{
	local RMV="$1"
	shift
	RMV="${RMV/-/\-}"
	RMV="${RMV/./\.}"
	echo "$@" | grep -v "^$RMV\$"
}

retrieve_clouds_yaml()
{
	# TODO
	echo "not yet implemented"
}

# Look at Cluster Stack object $1, return CS_SERIES, CS_MAINVER, CS_VERSION
retrieve_cstack()
{
	CS_MAINVER="${1#openstack-}"
	CS_MAINVER="${CS_MAINVER#scs*-}"
	CS_MAINVER_="${CS_MAINVER/-/.}"
	STACK=$(kubectl get -n $CS_NAMESPACE clusterStack $1 -o yaml) || return 2
	YAMLASSIGN=1 extract_yaml spec < <(echo "$STACK") >/dev/null
	CS_SERIES=$spec__name
	CS_MAINVER=$spec__kubernetesVersion
	CS_VERSION="${spec__versions[*]}"
	if test -z "$CS_SERIES" -o -z "$CS_MAINVER" -o -z "$CS_VERSION"; then
		echo "Some settings missing for $1 \"$CS_SERIES\" \"$CS_MAINVER\" \"$CS_VERSION\""
		return 3
	fi
	if test "$CS_MAINVER_" != "$CS_MAINVER"; then
		echo "Inconsistent k8s main version \"$CS_MAINVER\" vs \"$CS_MAINVER_\""
		return 4
	fi
	CS_VERSION="[${CS_VERSION/ /,}]"
	#echo "\"$CS_NAMESPACE\" \"$CS_SERIES\" \"$CS_MAINVER\" \"$CS_VERSION\""
	# TODO: retrieve_clouds_yaml
}

# Look at Cluster object $1, return CL_NAME, CL_PODCIDR, CL_SVCCIDR
# S_SERIES, CS_MAINVER, CS_VERSION
retrieve_cluster()
{
	CL_NAME="$1"
	CLUSTER=$(kubectl get -n $CS_NAMESPACE cluster $1 -o yaml)
	YAMLASSIGN=1 extract_yaml spec < <(echo "$CLUSTER") >/dev/null
	CL_PODCIDR="$spec__clusterNetwork__pods__cidrBlocks"		# only one for now
	CL_SVCCIDR="$spec__clusterNetwork__services__cidrBlocks"	# only one for now
	CL_CTRLNODES=$spec__topology__controlPlane__replicas
	CL_PATCHVER=${spec__topology__version#v}
	# CS_ variables
	MAINVER=${CL_PATCHVER%.*}
	CCLASS=$spec__topology__classRef__name
	SCLASS="${CCLASS%%-v*}"
	retrieve_cstack $SCLASS
	if test $? != 0; then
		SCLASS="openstack-${MAINVER/./-}"
		retrieve_cstack $SCLASS || return 5
	fi
	# Eliminate $SCLASS from CSTACKS list
	CSTACKS="$(rmv_list $SCLASS $CSTACKS)"
	# TODO: CL_WORKERS
	# TODO: CL_VARIABLES
}


# Find latest clusterstack
CSTACKS=$(kubectl get -n $CS_NAMESPACE clusterStack | awk '{print $1;}' | grep -v '^NAME' | sort)
if test -z "$CSTACKS"; then echo "No clusterStack found"; exit 2; fi
CLUSTERS=$(kubectl get -n $CS_NAMESPACE clusters | awk '{print $1;}' | grep -v '^NAME' | sort)
for cluster in $CLUSTERS; do retrieve_cluster "$cluster"; done
