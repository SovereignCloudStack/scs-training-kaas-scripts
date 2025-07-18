#!/bin/bash
#
# 11-fixup-ovn-lb.sh: Patch ccm-cloud-config secret to use ovn LB provider
#
# This is required to make the OCCM create octavia-ovn LBs for workloads.
# This is a temporary solution. We should have a proper setting in cluster-settings.env
# that gets passed down and is being consumed when the creaton of ccm-cloud-config
# happens.
#
# (c) Kurt Garloff <s7n@garloff.de>, 7/2025
# SPDX-License-Identifier: CC-BY-SA-4.0
set -e
THISDIR=$(dirname 0)
# We need settings
#unset KUBECONFIG
if test -n "$1"; then
	SET="$1"
else
	if test -e cluster-settings.env; then SET=cluster-settings.env;
	else echo "You need to pass a cluster-settings.env file as parameter"; exit 1
	fi
fi
# Read settings -- make sure you can trust it
source "$SET"
# Do this on the workload cluster, ensure we have a config
#clusterctl get kubeconfig -n $CS_NAMESPACE $CL_NAME > ~/.kube/$CS_NAMESPACE.$CL_NAME
export KUBECONFIG=~/.kube/$CS_NAMESPACE.$CL_NAME
CCONF_SECRET="$(kubectl get -n kube-system secrets ccm-cloud-config -o yaml)"
CCONF=$(echo "$CCONF_SECRET" | grep '^\s*cloud.conf:' | sed 's/^\s*cloud.conf: //')
NCCONF=$(LB=0; while read line; do
		if test $LB = 0; then echo "$line"; fi
		if test "$line" != "[LoadBalancer]" -a $LB = 0; then continue; fi
		if test "${line:0:1}" = "[" -a $LB = 1; then LB=0; echo "$line"; continue; fi
		if test "$line" = "[LoadBalancer]"; then LB=1; continue; fi
		# If we got here, we are in the Loadbalancer section
		if test -z "$line"; then echo -e "enabled = true\nlb-provider = ovn\nlb-method = SOURCE_IP_PORT\ncreate-monitor = true\n"; fi
		# Don't output anything else here
	done < <(echo "$CCONF" | base64 -d) | base64 -w0)
NCONF_SECRET=$(while IFS="" read line; do
		if echo "$line" | grep '^\s*cloud.conf' >/dev/null 2>&1; then
			echo "$line" | sed "s/cloud.conf: .*\$/cloud.conf: $NCCONF/"
		else
			echo "$line"
		fi
	done < <(echo "$CCONF_SECRET"))
# echo echo "$NCONF_SECRET" "| kubectl apply -f -"
echo "$NCONF_SECRET" | kubectl apply -f -
kubectl rollout restart -n kube-system daemonset openstack-cloud-controller-manager
