# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This repository contains scripts to automate the creation of Kubernetes clusters using Cluster API and OpenStack. The scripts are organized into a sequence of numbered steps that correspond to different phases of the cluster lifecycle management process.

## Environment Setup

Before running the scripts:

1. Create a copy of `cluster-settings-template.env` and fill in the required parameters
2. Source this file: `source your-settings.env` or pass it as a parameter to the individual scripts

## Script Execution Flow

The scripts are designed to be run in numerical order, based on the frequency and context of operations:

### Management Host Setup (Run once per host)

```bash
# Install required tools (Debian-based systems)
./00-bootstrap-vm-cs.sh

# Create a local kind cluster
./01-create-kind-cluster.sh

# Install Cluster API components
./02-deploy-capi.sh 

# Install Cluster Stack Operator
./03-deploy-cso.sh
```

### Cloud Access Configuration (Run once per OpenStack project)

```bash
# Create namespace and cloud secrets
./04-cloud-secret.sh your-settings.env
```

### Kubernetes Version Setup (Run once per Kubernetes version)

```bash
# Deploy the cluster stack for a specific K8s version
./05-deploy-cstack.sh your-settings.env

# Wait for cluster class to be ready
./06-wait-clusterclass.sh your-settings.env
```

### Cluster Lifecycle Management (Run per cluster)

```bash
# Create a new cluster
./07-create-cluster.sh your-settings.env

# Wait for cluster to be ready
./08-wait-cluster.sh your-settings.env

# Delete a cluster when no longer needed
./16-delete-cluster.sh your-settings.env
```

## Configuration Parameters

Key parameters in the cluster settings file include:

- `CS_NAMESPACE`: Namespace for cluster resources
- `CLOUDS_YAML`: Path to OpenStack credentials file
- `OS_CLOUD`: Name of the cloud in the clouds.yaml file
- `CS_MAINVER`: Kubernetes major.minor version (e.g., 1.32)
- `CS_VERSION`: Cluster stack template version
- `CL_PATCHVER`: Full Kubernetes version (e.g., 1.32.3)
- `CL_NAME`: Cluster name
- `CL_PODCIDR`: Pod CIDR range
- `CL_SVCCIDR`: Service CIDR range
- `CL_CTRLNODES`: Number of control plane nodes
- `CL_WRKRNODES`: Number of worker nodes

## Implementation Notes

- The scripts follow a modular design to accommodate different frequencies of operations
- They handle the installation of required tools, CAPI components, and the cluster stack operator
- Cloud credentials are managed through Kubernetes secrets
- Cluster deployment is templated based on the settings file
- Some scripts (e.g., waiting for resources) are placeholders with "not yet implemented" functionality

## Troubleshooting

If a script fails:
1. Check the error message for missing configuration parameters
2. Verify that previous steps completed successfully
3. Ensure your OpenStack credentials in `clouds.yaml` are correct
4. Verify the Kubernetes resources with `kubectl get` commands as shown in the scripts