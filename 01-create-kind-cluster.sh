#!/bin/bash
# Create a local kind (Kubernetes in Docker) cluster
set -e

echo "Creating a new local kind cluster..."
kind create cluster

# Verify the cluster is running
echo "Verifying cluster status..."
kubectl cluster-info

echo "Kind cluster successfully created and running."