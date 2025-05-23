#!/bin/bash
# Deploy CSO
set -e
mkdir ~/tmp || true

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
# Install Cluster Stack Operator (CSO) with above values
helm upgrade -i cso -n cso-system \
	--create-namespace --values ~/tmp/cso-rbac.yaml \
	oci://registry.scs.community/cluster-stacks/cso
kubectl -n cso-system rollout status deployment
