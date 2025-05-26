#!/bin/bash
#
# 09-fixup-cinder.sh: Patch Cinder-CSI config path from /etc/kubernetes/
# de
#  to /etc/config/, so the reference ca-file=/etc/config/cacert in the
#  file cloud.conf points to an existing place again.
#
# This is required in case we use a custom CA file and inject it.
#
# (c) Kurt Garloff <s7n@garloff.de>, 5/2025
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
# Get cinder-csi-controllerplugin deployment and patch it
kubectl get -n kube-system deployment openstack-cinder-csi-controllerplugin -o yaml > ~/tmp/cinder-csi-controllerplugin.yaml
patch ~/tmp/cinder-csi-controllerplugin.yaml <$THISDIR/csi-cinder-controller-deployment.diff 
kubectl get -n kube-system daemonset openstack-cinder-csi-nodeplugin -o yaml > ~/tmp/cinder-csi-nodeplugin.yaml
patch ~/tmp/cinder-csi-nodeplugin.yaml <$THISDIR/csi-cinder-nodeplugin-daemonset.diff
kubectl apply -f ~/tmp/cinder-csi-controllerplugin.yaml
kubectl apply -f ~/tmp/cinder-csi-nodeplugin.yaml

