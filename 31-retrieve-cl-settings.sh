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
# Find latest clusterstack
CSTACKS=$(kubectl get -n $CS_NAMESPACE clusterStack | awk '{print $1;}' | grep -v '^NAME' | sort)
if test -z "$CSTACKS"; then echo "No clusterStack found"; exit 2; fi
CLUSTERS=$(kubectl get -n $CS_NAMESPACE clusters | awk '{print $1;}' | grep -v '^NAME' | sort)

# Look at Cluster Stack object $1, return CS_SERIES, CS_MAINVER, CS_VERSION
retrieve_cstack()
{
	CS_MAINVER="${1#openstack-}"
	CS_MAINVER_="${CS_MAINVER/-/.}"
	STACK=$(kubectl get -n $CS_NAMESPACE clusterStack $CSTACK -o yaml)
	YAMLASSIGN=1 extract_yaml spec < <(echo "$STACK") >/dev/null
	CS_SERIES=$spec__name
	CS_MAINVER=$spec__kubernetesVersion
	CS_VERSION="${spec__versions[*]}"
	if test -z "$CS_SERIES" -o -z "$CS_MAINVER" -o -z "$CS_VERSION"; then
		echo "Some settings missing \"$CS_SERIES\" \"$CS_MAINVER\" \"$CS_VERSION\""
		exit 3
	fi
	if test "$CS_MAINVER_" != "$CS_MAINVER"; then
		echo "Inconsistent k8s main version \"$CS_MAINVER\" vs \"$CS_MAINVER_\""
		exit 4
	fi
	CS_VERSION="[${CS_VERSION/ /,}]"
	#echo "\"$CS_NAMESPACE\" \"$CS_SERIES\" \"$CS_MAINVER\" \"$CS_VERSION\""
}

retrieve_clouds_yaml()
{
	# TODO
	echo "not yet implemented"
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
	CL_PATCHVER=$spec__topology__version
	# CS_ variables
	MAINVER=${CL_PATCHVER%.*}
	CCLASS=$spec__topology__classRef__namea
	retrieve_cstack ${CCLASS%%-v*}
	# TODO: Eliminate ${CCLASS%%-v*} from CSTACKS list
	# TODO: CL_WORKERS
	# TODO: CL_VARIABLES
}

