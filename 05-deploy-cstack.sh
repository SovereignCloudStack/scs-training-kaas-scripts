#!/bin/bash
# Deploy the ClusterStack
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
# Create clusterstack template
# Sanity checks 
if test -z "$CS_MAINVER"; then echo "Configure CS_MAINVER"; exit 2; fi
if test -z "$CS_VERSION"; then echo "Configure CS_VERSION"; exit 3; fi
if test -z "$CS_SERIES"; then echo "Configure CS_SERIES, default to scs2"; CS_SERIES=scs2; fi
# if test -z "$CL_PATCHVER"; then echo "Configure CL_PATCHVER"; exit 4; fi
# Create ClusterStack yaml
cat > ~/tmp/clusterstack-$CS_MAINVER.yaml <<EOF
apiVersion: clusterstack.x-k8s.io/v1alpha1
kind: ClusterStack
metadata:
  name: openstack-${CS_MAINVER/./-}
  namespace: "$CS_NAMESPACE"
spec:
  provider: openstack
  name: "$CS_SERIES"
  kubernetesVersion: "$CS_MAINVER"
  channel: custom
  autoSubscribe: false
  noProvider: true
  versions: $CS_VERSION
EOF
# Apply
kubectl apply -f ~/tmp/clusterstack-$CS_MAINVER.yaml
# Does the clusterclass exist?
sleep 1
echo "The clusterclass should exist now"
set -x
kubectl get clusterclasses -n "$CS_NAMESPACE"
kubectl get images -n "$CS_NAMESPACE"
