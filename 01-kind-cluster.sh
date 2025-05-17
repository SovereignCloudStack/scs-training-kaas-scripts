#!/bin/bash
# Create a local kind (Kubernetes in Docker) cluster
set -e

echo "Creating a new kind cluster..."
kind create cluster

echo "Verifying cluster status..."
kubectl cluster-info

echo "Kind cluster ready."
