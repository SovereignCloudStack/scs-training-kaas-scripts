#!/bin/bash
# (c) Kurt Garloff <s7n@garloff.de>, 5/2025
# SPDX-License-Identifier: CC-BY-SA-4.0
set -e
THISDIR=$(dirname 0)
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
# Use workload cluster
export KUBECONFIG=~/.kube/$CS_NAMESPACE.$CL_NAME
# Add kubernetes-dashboard repository
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
# Deploy a Helm Release named "kubernetes-dashboard" using the kubernetes-dashboard chart
helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard --create-namespace --namespace kubernetes-dashboard
# Expose to localhost:8443
#kubectl -n kubernetes-dashboard port-forward svc/kubernetes-dashboard-kong-proxy 8443:443
# Expose it via loadbalancer
kubectl patch -n kubernetes-dashboard svc kubernetes-dashboard-kong-proxy --patch '{"spec": {"type": "LoadBalancer"}}'
# Create a service-account
kubectl -n kubernetes-dashboard create serviceaccount dashboard-svc-act
# Grant cluster-admin to dashboard-svc-act
kubectl apply -f - << EOT
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: dashboard-svc-act-rbac
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: dashboard-svc-act
  namespace: kubernetes-dashboard
EOT
# Get bearer token
echo "kubectl -n kubernetes-dashboard create token dashboard-svc-act"
kubectl -n kubernetes-dashboard create token dashboard-svc-act
# Display service
kubectl get -n kubernetes-dashboard svc kubernetes-dashboard-kong-proxy
