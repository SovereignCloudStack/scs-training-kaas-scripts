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
kubectl get cluster -A

# Show cluster description
clusterctl describe cluster -n "$CS_NAMESPACE" $CL_NAME --grouping=false
echo

# Get cluster status if available
#kubectl wait --timeout=14m --for=condition=certificatesavailable -n "$CS_NAMESPACE" kubeadmcontrolplanes -l cluster.x-k8s.io/cluster-name=$CL_NAME
if kubectl get cluster -n "$CS_NAMESPACE" $CL_NAME &>/dev/null; then
    CLUSTER_STATUS=$(kubectl get cluster -n "$CS_NAMESPACE" $CL_NAME -o jsonpath='{.status.phase}')
    echo "Cluster status: $CLUSTER_STATUS"
    
    # If cluster is ready, save kubeconfig
    if [ "$CLUSTER_STATUS" = "Provisioned" ]; then
        echo "Cluster is ready!"
        
        # Get kubeconfig
        echo "Creating ~/.kube directory if needed..."
        mkdir -p ~/.kube
        KCFG=~/.kube/$CS_NAMESPACE.$CL_NAME

        echo "Saving kubeconfig to $KCFG
        OLDUMASK=$(umask)
        umask 0077
        clusterctl get kubeconfig -n "$CS_NAMESPACE" $CL_NAME > $KCFG
        umask $OLDUMASK

        echo "Kubeconfig has been saved"
        echo "You can access the cluster with: export KUBECONFIG=~/.kube/$CS_NAMESPACE.$CL_NAME"
        echo

        # Display cluster info
        echo "Displaying cluster info:"
        KUBECONFIG=$KCFG kubectl cluster-info
        #KUBECONFIG=$KCFG kubectl get nodes -o wide
        #KUBECONFIG=$KCFG kubectl get pods -A
        echo "# Hint: Use KUBECONFIG=$KCFG kubectl ... to access you workload cluster $CS_NAMESPACE/$CL_NAME"
    else
        echo "Cluster is not yet ready (status: $CLUSTER_STATUS)"
        echo "Run this script again after some time to check status and save kubeconfig when ready"
    fi
else
    echo "Cluster $CL_NAME not found or not accessible in namespace $CS_NAMESPACE"
    echo "Please check if the cluster has been created and you have the necessary permissions"
fi