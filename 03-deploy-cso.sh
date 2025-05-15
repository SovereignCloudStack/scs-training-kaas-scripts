#!/bin/bash
# Deploy Cluster Stack Operator (CSO)
set -e

echo "Creating temporary directory..."
mkdir ~/tmp || true

echo "Generating CSO RBAC configuration..."
cat > ~/tmp/cso-rbac.yaml <<EOF
clusterStackVariables:
  ociRepository: registry.scs.community/kaas/cluster-stacks
controllerManager:
  rbac:
    additionalRules:
      - apiGroups:
          - "openstack.k-orc.cloud"
        resources:
          - "images"
        verbs:
          - create
          - delete
          - get
          - list
          - patch
          - update
          - watch
EOF

echo "Installing Cluster Stack Operator with Helm..."
echo "Using registry.scs.community/kaas/cluster-stacks as OCI repository"
helm upgrade -i cso -n cso-system \
	--create-namespace --values ~/tmp/cso-rbac.yaml \
	oci://registry.scs.community/cluster-stacks/cso

echo "Waiting for CSO deployments to be ready..."
kubectl -n cso-system rollout status deployment

echo "Cluster Stack Operator deployed successfully."
