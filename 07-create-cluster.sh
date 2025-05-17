#!/bin/bash
# Create a Kubernetes cluster using Cluster API
set -e

# We need settings
if test -n "$1"; then
	SET="$1"
else
	if test -e cluster-settings.env; then SET=cluster-settings.env;
	else echo "You need to pass a cluster-settings.env file as parameter"; exit 1
	fi
fi

# Read settings -- make sure you can trust it
source "$SET"
echo "Using settings from $SET"

# Sanity checks 
echo "Performing sanity checks on required variables..."
if test -z "$CS_MAINVER"; then echo "Configure CS_MAINVER"; exit 2; fi
if test -z "$CS_VERSION"; then echo "Configure CS_VERSION"; exit 3; fi
if test -z "$CL_PATCHVER"; then echo "Configure CL_PATCHVER"; exit 4; fi
if test -z "$CL_NAME"; then echo "Configure CL_NAME"; exit 5; fi
if test -z "$CL_PODCIDR"; then echo "Configure CL_PODCIDR"; exit 6; fi
if test -z "$CL_SVCCIDR"; then echo "Configure CL_SVCCIDR"; exit 7; fi
if test -z "$CL_CTRLNODES"; then echo "Configure CL_CTRLNODES"; exit 8; fi
if test -z "$CL_WRKRNODES"; then echo "Configure CL_WRKRNODES"; exit 9; fi

echo "Creating cluster manifest for $CL_NAME..."
echo "  Kubernetes Version: v$CL_PATCHVER"
echo "  Control Plane Nodes: $CL_CTRLNODES"
echo "  Worker Nodes: $CL_WRKRNODES"
echo "  Pod CIDR: $CL_PODCIDR"
echo "  Service CIDR: $CL_SVCCIDR"

# Create Cluster yaml
# TODO: There are a number of variables that allow us to set things like
#  flavors, disk sizes, loadbalancer types, etc.
#  We need to make them visible!
cat > ~/tmp/cluster-$CL_NAME.yaml <<EOF
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: "$CL_NAME"
  namespace: "$CS_NAMESPACE"
  labels:
    managed-secret: cloud-config
spec:
  clusterNetwork:
    pods:
      cidrBlocks:
      - "$CL_PODCIDR"
    serviceDomain: cluster.local
    services:
      cidrBlocks:
      - "$CL_SVCCIDR"
  topology:
    class: openstack-scs-${CS_MAINVER/./-}-$CS_VERSION
    controlPlane:
      replicas: $CL_CTRLNODES
    version: v$CL_PATCHVER
    workers:
      machineDeployments:
        - class: default-worker
          name: md-0
          replicas: $CL_WRKRNODES
    variables:
      - name: apiserver_loadbalancer
        value: "octavia-ovn"
EOF

echo "Applying cluster manifest..."
kubectl apply -f ~/tmp/cluster-$CL_NAME.yaml

echo "Cluster $CL_NAME creation initiated. Run 08-wait-cluster.sh to monitor progress."
