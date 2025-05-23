#!/bin/bash
# Rollout ORC, CAPI, CAPO (Cluster API with OpenStack provider)
set -e

echo "Setting required feature flags for Cluster API..."
export CLUSTER_TOPOLOGY=true
export EXP_CLUSTER_RESOURCE_SET=true
export EXP_RUNTIME_SDK=true
echo "CLUSTER_TOPOLOGY=$CLUSTER_TOPOLOGY"
echo "EXP_CLUSTER_RESOURCE_SET=$EXP_CLUSTER_RESOURCE_SET"
echo "EXP_RUNTIME_SDK=$EXP_RUNTIME_SDK"

echo "Deploying OpenStack Resource Controller (ORC)..."
# We need ORC these days and clusterctl has chosen to ignore that
kubectl apply -f https://github.com/k-orc/openstack-resource-controller/releases/latest/download/install.yaml

echo "Initializing Cluster API with OpenStack infrastructure provider..."
# Rollout capi and capo (assuming that orc gets deployed independently)
clusterctl init --infrastructure openstack

echo "Waiting for CAPI deployments to be ready..."
kubectl -n capi-system rollout status deployment

echo "Waiting for CAPO deployments to be ready..."
kubectl -n capo-system rollout status deployment

echo "Cluster API components deployed successfully."

