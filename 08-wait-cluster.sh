#!/bin/bash
# Wait for cluster to be ready and save kubeconfig
set -e

# We need settings
if test -n "$1"; then
	SET="$1"
	echo "Using settings from $1"
else
	if test -e cluster-settings.env; then 
		SET=cluster-settings.env
		echo "Using settings from cluster-settings.env"
	else 
		echo "You need to pass a cluster-settings.env file as parameter"
		exit 1
	fi
fi

# Read settings -- make sure you can trust it
source "$SET"

# Display initial cluster state
echo "Checking initial state of cluster $CL_NAME in namespace $CS_NAMESPACE..."
clusterctl describe cluster -n "$CS_NAMESPACE" $CL_NAME

# Wait for cluster to be ready
echo "Waiting for cluster $CL_NAME to be ready..."
set -x

TIMEOUT=3600  # 60 minutes timeout
START_TIME=$(date +%s)
READY=false

# Disable command echo for cleaner output
set +x
echo "Will timeout after $((TIMEOUT/60)) minutes if not ready"

while [ "$READY" = "false" ]; do
  # Check if timeout has been reached
  CURRENT_TIME=$(date +%s)
  ELAPSED_TIME=$((CURRENT_TIME - START_TIME))
  ELAPSED_MINUTES=$((ELAPSED_TIME/60))
  ELAPSED_SECONDS=$((ELAPSED_TIME%60))
  
  if [ $ELAPSED_TIME -gt $TIMEOUT ]; then
    echo "Timeout waiting for cluster to be ready after $ELAPSED_MINUTES minutes"
    exit 1
  fi
  
  # Check cluster status using kubectl instead of clusterctl json output
  if kubectl get cluster -n "$CS_NAMESPACE" $CL_NAME -o jsonpath='{.status.phase}' 2>/dev/null; then
    CLUSTER_STATUS=$(kubectl get cluster -n "$CS_NAMESPACE" $CL_NAME -o jsonpath='{.status.phase}' 2>/dev/null)
    echo "Current cluster status: $CLUSTER_STATUS"
  else
    CLUSTER_STATUS="Unknown"
    echo "Current cluster status: Unknown (cluster resource may not be fully created yet)"
  fi
  
  # Check if the cluster is ready based on status
  if [ "$CLUSTER_STATUS" = "Provisioned" ]; then
    READY=true
    echo "Cluster is ready!"
  else
    # Show current cluster state
    echo "Current cluster details:"
    clusterctl describe cluster -n "$CS_NAMESPACE" $CL_NAME
    echo "Waiting for cluster to be ready... (elapsed: $ELAPSED_MINUTES minutes, $ELAPSED_SECONDS seconds)"
    sleep 30
  fi
done

# Get kubeconfig once the cluster is ready
echo "Creating ~/.kube directory if needed..."
mkdir -p ~/.kube

echo "Saving kubeconfig to ~/.kube/$CS_NAMESPACE.$CL_NAME.yaml"
clusterctl get kubeconfig -n "$CS_NAMESPACE" $CL_NAME > ~/.kube/$CS_NAMESPACE.$CL_NAME.yaml
chmod 600 ~/.kube/$CS_NAMESPACE.$CL_NAME.yaml

echo "Cluster $CL_NAME is ready and kubeconfig has been saved"
echo "You can access the cluster with: export KUBECONFIG=~/.kube/$CS_NAMESPACE.$CL_NAME.yaml"

# Display a quick cluster summary
echo "Displaying cluster info:"
KUBECONFIG=~/.kube/$CS_NAMESPACE.$CL_NAME.yaml kubectl cluster-info
