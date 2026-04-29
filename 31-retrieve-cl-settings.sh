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

output()
{
	echo "# ClusterStack settings"
	echo "CS_NAMESPACE=$CS_NAMESPACE"
	# echo CLOUDS_YAML
	# echo OS_CLOUD
	echo "CS_MAINVER=$CS_MAINVER"
	echo "CS_VERSION=\"$CS_VERSION\""
	echo "CS_SERIES=$CS_SERIES"
	echo "# Cluster settings"
	echo "CL_NAME=\"$CL_NAME\""
	echo "CL_PATCHVER=$CL_PATCHVER"
	echo "CL_PODCIDR=$CL_PODCIDR"
	echo "CL_SVCCIDR=$CL_SVCCIDR"
	echo "CL_CTRLNODES=$CL_CTRLNODES"
	echo "CL_WRKRNODES=$CL_WRKRNODES"
	echo "CL_VARIABLES=\"$CL_VARIABLES\""
	echo "# END #"
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
	STACK=$(kubectl get -n $CS_NAMESPACE clusterStack $1 -o yaml 2>/dev/null) || return 2
	VPRE=cs__ YAMLASSIGN=1 extract_yaml spec < <(echo "$STACK") >/dev/null
	CS_SERIES=$cs__spec__name
	CS_MAINVER=$cs__spec__kubernetesVersion
	CS_VERSION="${cs__spec__versions[*]}"
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
	# CL_WORKERS
	unset CL_WRKRNODES
	NOMDS=${#spec__topology__workers__machineDeployments[*]}
	for MDIDX in $(seq 0 $((NOMDS-1))); do
		unset item__failureDomain
		VPRE=item__ YAMLASSIGN=1 extract_yaml . < <(echo "${spec__topology__workers__machineDeployments[$MDIDX]}") >/dev/null
		if test -n "$item__failureDomain"; then
			CL_WRKRNODES="$CL_WRKRNODES${item__failureDomain}:${item__replicas},"
		else
			CL_WRKRNODES="$CL_WRKRNODES${item__replicas},"
		fi
	done
	CL_WRKRNODES="${CL_WRKRNODES%,}"
	# CL_VARIABLES
	unset CL_VARIABLES
	NOVARS=${#spec__topology__variables[*]}
	for VARIDX in $(seq 0 $((NOVARS-1))); do
		unset item__value
		VPRE=item__ YAMLASSIGN=1 extract_yaml . < <(echo "${spec__topology__variables[$VARIDX]}") >/dev/null
		if is_array "$item__value"; then
			val=${item__value[*]}
			CL_VARIABLES="$CL_VARIABLES$item__name=[${val// /,}];"
		elif test -n "$item__value"; then
			# TODO: Check for defaults and filter out
			CL_VARIABLES="$CL_VARIABLES$item__name=$item__value;"
		fi
	done
	CL_VARIABLES="${CL_VARIABLES%;}"
	output
}


# Find latest clusterstack
CSTACKS=$(kubectl get -n $CS_NAMESPACE clusterStack | awk '{print $1;}' | grep -v '^NAME' | sort)
if test -z "$CSTACKS"; then echo "No clusterStack found"; exit 2; fi
CLUSTERS=$(kubectl get -n $CS_NAMESPACE clusters | awk '{print $1;}' | grep -v '^NAME' | sort)
for cluster in $CLUSTERS; do retrieve_cluster "$cluster"; done
