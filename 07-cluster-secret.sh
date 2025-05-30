#!/bin/bash
# Create cloud secret -- alternative. Not yet complete.
set -e
# We need settings
unset KUBECONFIG
if test -n "$1"; then
	SET="$1"
else
	if test -e cluster-settings.env; then SET=cluster-settings.env;
	else echo "You need to pass a cluster-settings.env file as parameter"; exit 1
	fi
fi
# Read settings -- make sure you can trust it
source "$SET"
# Read helper
THISDIR=$(dirname 0)
source "$THISDIR/_yaml_parse.sh"

# Create namespace
# Our global clouds.yaml
CL_YAML=~/tmp/clouds-$OS_CLOUD.yaml
#export OS_CLOUD=openstack
CLOUDS_YAML=${CLOUDS_YAML:-~/.config/openstack/clouds.yaml}
CA=$(RMVTREE=1 extract_yaml clouds.$OS_CLOUD.cacert <$CLOUDS_YAML | sed 's/^\s*cacert: //' || true)
OS_CACERT="${OS_CACERT:-$CA}"
if test -n "$OS_CACERT"; then
	OS_CACERT=${OS_CACERT/\~/$HOME}
	CACERT_B64="$(base64 -w0 < $OS_CACERT)"
	CAINSERT="
  cacert: $CACERT_B64"
	CAFILE="
ca-file=/etc/config/cacert"
else
	unset CAINSERT
	unset CAFILE
fi

OLD_UMASK=$(umask)

# Deal with per-cluster secrets
# A few cases:
# 1. CL_APPCRED_LIFETIME=0 or empty: No AppCreds wanted
#   We then share one workload-cluster-secret (and newsecret) with all clusters with that setting
#   Make sure it exists and is up-to-date and create CRS to manage it
# 2. CL_APPCRED_LIFETIME=non-zero: We want per-cluster AppCreds (need openstacktools installed)
#   A. We still have one that's valid for at least a third of its lifetime: Do nothing
#   B. We have one, but it is about to expire or has expired: Renew it
#   C. We have none: Create one

# Store it securely in ~/tmp/clouds-$OS_CLOUD.yaml
echo "# Generating ~/tmp/clouds-$OS_CLOUD.yaml ..."
YAMLASSIGN=1 extract_yaml clouds.openstack < ~/tmp/clouds-$OS_CLOUD.yaml >/dev/null

# Case 1
if test -z "$CL_APPCRED_LIFETIME" -o "$CL_APPCRED_LIFETIME" = 0; then
	if test -n "$clouds__openstack__auth__application_credential_id"; then
		AUTHSECTION="application-credential-id=$clouds__openstack__application_credential_id
application-credential-secret=$clouds__openstack__aplication_credential_secret"
	else
		AUTHSECTION="username=$clouds__openstack__auth__username
password=$clouds__openstack__auth__password
user-domain-name=$clouds__openstack__auth__user_domain_name
domain-name=${clouds__openstack__auth__domain_name:-$clouds__openstack__auth__project_domain_name}
tenant-id=$clouds__openstack__auth__project_id
project-id=$clouds__openstack__auth__project_id"
	fi
	if test -z "$PREFER_AMPHORA"; then
		LB_OVN="lb-provider=ovn
lb-method=SOURCE_IP_PORT"
	fi
	umask 0177
	cat >~/tmp/cloud-$OS_CLOUD.conf <<EOT
[Global]
auth-url=$clouds__openstack__auth__auth_url
region=$clouds__openstack__region_name$CAFILE
$AUTHSECTION

[LoadBalancer]
manage-security-groups=true
enable-ingress-hostname=true
create-monitor=true
$LB_OVN
EOT
	umask $OLD_UMASK
	CL_CONF_B64="$(base64 -w0 < ~/tmp/cloud-$OS_CLOUD.conf)"
	CL_YAML_ALT_B64=$(base64 -w0 < <(sed 's@/etc/certs/cacert@/etc/openstack/cacert@' "$CL_YAML"))
	# Workload cluster clouds-yaml
	CL_YAML_WL_B64=$(base64 -w0 <<EOT
apiVersion: v1
kind: Secret
type: Opaque
metadata:
  name: clouds-yaml
  namespace: kube-system
data:
  clouds.yaml: $CL_YAML_ALT_B64$CAINSERT
  cloudName: $CL_NAME_B64
EOT
)
	# Workload cluster cloud-config
	CL_CONF_WL_B64=$(base64 -w0 <<EOT
apiVersion: v1
kind: Secret
type: Opaque
metadata:
  name: cloud-config
  namespace: kube-system
data:
  cloud.conf: $CL_CONF_B64$CAINSERT
  cloudprovider.conf: $CL_CONF_B64
EOT
)
	kubectl apply -f - <<EOT
apiVersion: v1
data:
  clouds-yaml-secret: $CL_YAML_WL_B64
kind: Secret
metadata:
  name: openstack-workload-cluster-newsecret
  namespace: $CS_NAMESPACE
  labels:
    clusterctl.cluster.x-k8s.io/move: "true"
type: addons.cluster.x-k8s.io/resource-set
---
apiVersion: addons.cluster.x-k8s.io/v1beta1
kind: ClusterResourceSet
metadata:
  name: crs-openstack-newsecret
  namespace: $CS_NAMESPACE
  labels:
    clusterctl.cluster.x-k8s.io/move: "true"
spec:
  strategy: "Reconcile"
  clusterSelector:
    matchLabels:
      managed-secret: clouds-yaml
  resources:
    - name: openstack-workload-cluster-newsecret
      kind: Secret
---
apiVersion: v1
data:
  cloud-config-secret: $CL_CONF_WL_B64
kind: Secret
metadata:
  name: openstack-workload-cluster-secret
  namespace: $CS_NAMESPACE
  labels:
    clusterctl.cluster.x-k8s.io/move: "true"
type: addons.cluster.x-k8s.io/resource-set
---
apiVersion: addons.cluster.x-k8s.io/v1beta1
kind: ClusterResourceSet
metadata:
  name: crs-openstack-secret
  namespace: $CS_NAMESPACE
  labels:
    clusterctl.cluster.x-k8s.io/move: "true"
spec:
  strategy: "Reconcile"
  clusterSelector:
    matchLabels:
      managed-secret: cloud-config
  resources:
    - name: openstack-workload-cluster-secret
      kind: Secret
EOT
else
	echo "ERROR: Application credential support not yet implemented."
	exit 10
fi
