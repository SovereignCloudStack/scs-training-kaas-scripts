#!/bin/bash
# Rollout ORC, CAPI, CAPO
set -e
# Set feature flags
export CLUSTER_TOPOLOGY=true
export EXP_CLUSTER_RESOURCE_SET=true
export EXP_RUNTIME_SDK=true
# We need ORC these days and clusterctl has chosen to ignore that
kubectl apply -f https://github.com/k-orc/openstack-resource-controller/releases/latest/download/install.yaml
# Rollout capi and capo (assuming that orc gets deployed independently)
clusterctl init --infrastructure openstack
# Wait for completion
kubectl -n capi-system rollout status deployment
kubectl -n capo-system rollout status deployment

