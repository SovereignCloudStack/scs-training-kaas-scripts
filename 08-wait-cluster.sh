#!/bin/bash
# Check cluster status and save kubeconfig
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

# Display cluster state
echo "Checking state of cluster $CL_NAME in namespace $CS_NAMESPACE..."
echo

# Show cluster description
clusterctl describe cluster -n "$CS_NAMESPACE" $CL_NAME
echo

# Get cluster status if available
if kubectl get cluster -n "$CS_NAMESPACE" $CL_NAME &>/dev/null; then
    CLUSTER_STATUS=$(kubectl get cluster -n "$CS_NAMESPACE" $CL_NAME -o jsonpath='{.status.phase}')
    echo "Cluster status: $CLUSTER_STATUS"
    
    # If cluster is ready, save kubeconfig
    if [ "$CLUSTER_STATUS" = "Provisioned" ]; then
        echo "Cluster is ready!"
        
        # Get kubeconfig
        echo "Creating ~/.kube directory if needed..."
        mkdir -p ~/.kube
        
        echo "Saving kubeconfig to ~/.kube/$CS_NAMESPACE.$CL_NAME"
        clusterctl get kubeconfig -n "$CS_NAMESPACE" $CL_NAME > ~/.kube/$CS_NAMESPACE.$CL_NAME
        chmod 600 ~/.kube/$CS_NAMESPACE.$CL_NAME
        
        echo "Kubeconfig has been saved"
        echo "You can access the cluster with: export KUBECONFIG=~/.kube/$CS_NAMESPACE.$CL_NAME"
        echo
        
        # Display cluster info
        echo "Displaying cluster info:"
        KUBECONFIG=~/.kube/$CS_NAMESPACE.$CL_NAME kubectl cluster-info
    else
        echo "Cluster is not yet ready (status: $CLUSTER_STATUS)"
        echo "Run this script again after some time to check status and save kubeconfig when ready"
    fi
else
    echo "Cluster $CL_NAME not found or not accessible in namespace $CS_NAMESPACE"
    echo "Please check if the cluster has been created and you have the necessary permissions"
fi