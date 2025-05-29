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
test -n "$CS_NAMESPACE"
kubectl create namespace "$CS_NAMESPACE" || true
# Default clouds.yaml location
CLOUDS_YAML=${CLOUDS_YAML:-~/.config/openstack/clouds.yaml}
# Use csp helper chart to create cloud secret
# Notes on expected clouds.yaml:
# - It should have the secrets (which you often keep in secure.yaml instead) merged into it
# 	NOTE: This will only work if the auth section is the last entry for this cloud in clouds.yaml
# - The cloud should be called openstack
# - We will detect a cacert in there and pass it to the helper chart
if ! test -r "$CLOUDS_YAML"; then echo "clouds.yaml $CLOUDS_YAML not readable"; exit 2; fi
CA=$(RMVTREE=1 extract_yaml clouds.$OS_CLOUD.cacert <$CLOUDS_YAML | sed 's/^\s*cacert: //' || true)
OS_CACERT="${OS_CACERT:-$CA}"
# Extract auth parts from secure.yaml if existent, assume same indentation
SEC_YAML="${CLOUDS_YAML%clouds.yaml}secure.yaml"
if test -r "$SEC_YAML"; then SECRETS=$(RMVTREE=1 RMVCOMMENT=1 extract_yaml clouds.$OS_CLOUD.auth < $SEC_YAML || true); fi
if test -n "$SECRETS"; then
	echo "# Appending secrets from secure.yaml to clouds.yaml"
fi
# Determine whether we need to add project ID
RAW_CLOUD=$(extract_yaml clouds.$OS_CLOUD <$CLOUDS_YAML)
if ! echo "$RAW_CLOUD" | grep -q '^\s*project_id:' && echo "$RAW_CLOUD" | grep -q '^\s*project_name:'; then
	# Need openstack CLI for this
	PROJECT_NAME=$(echo "$RAW_CLOUD" | grep '^\s*project_name:' | sed 's/^\s*project_name: //')
	PROJECT_ID=$(openstack project show $PROJECT_NAME -c id -f value | tr -d '\r')
	INDENT=$(echo "$RAW_CLOUD" | grep '^\s*project_name:' | sed 's/^\(\s*\)project_name:.*$/\1/')
	SECRETS=$(echo -en "${INDENT}project_id: $PROJECT_ID\n$SECRETS")
	echo "# Appending project_id: $PROJECT_ID to clouds.yaml"
fi
# We need a region_name, add it in
if ! echo "$RAW_CLOUD" | grep -q '^\s*region_name:'; then
	# Need openstack CLI for this
	REGION=$(openstack region list -c Region -f value | head -n1 | tr -d '\r')
	INDENT=$(echo "$RAW_CLOUD" | grep '^\s*auth:' | sed 's/^\(\s*\)auth:.*$/\1/')
	export INSERT="${INDENT}region_name: $REGION"
	echo "# Inserting region_name: $REGION to clouds.yaml"
fi
# Construct a clouds.yaml (mode 0600):
# - Only extracting one cloud addressed by $OS_CLOUD
# - By merging secrets in from secure.yaml
# - By renaming it to openstack (current CS limitation)
# - By removing cacert setting
# Store it securely in ~/tmp/clouds-$OS_CLOUD.yaml
echo "# Generating ~/tmp/clouds-$OS_CLOUD.yaml ..."
OLD_UMASK=$(umask)
umask 0177
INJECTSUB="$SECRETS" INJECTSUBKWD="auth" RMVCOMMENT=1 REPLACEKEY=openstack YAMLASSIGN=1 extract_yaml clouds.$OS_CLOUD < $CLOUDS_YAML > ~/tmp/clouds-$OS_CLOUD.yaml
# This is the location that capo wants (we could comment it out)
sed -i 's@^\(\s*cacert:\).*@\1 /etc/certs/cacert@' ~/tmp/clouds-$OS_CLOUD.yaml
#echo "octavia_ovn: true" >> ~/tmp/clouds-$OS_CLOUD.yaml
CL_YAML=$(ls ~/tmp/clouds-$OS_CLOUD.yaml)
CL_YAML_B64=$(base64 -w0 < "$CL_YAML")
CL_NAME_B64=$(echo -n openstack | base64 -w0)
#kubectl create secret -n $CS_NAMESPACE generic clouds-yaml --from-file=$CL_YAML 
umask $OLD_UMASK
if test -n "$OS_CACERT"; then
	OS_CACERT=${OS_CACERT/\~/$HOME}
	CACERT="$(cat $OS_CACERT)"
	CACERT_B64=$(echo -n "$CACERT" | base64 -w0)
	CAINSERT="
  cacert: $CACERT_B64"
else
	unset CAINSERT
fi
# For OCCM and CSI, the location of cacert is /etc/openstack
CL_YAML_ALT_B64=$(base64 -w0 < <(sed 's@/etc/certs/cacert@/etc/openstack/cacert@' "$CL_YAML"))
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
# For CAPO
kubectl apply -f - << EOT
apiVersion: v1
data:
  clouds.yaml: $CL_YAML_B64$CAINSERT
  cloudName: $CL_NAME_B64
kind: Secret
metadata:
  name: openstack
  namespace: $CS_NAMESPACE
  labels:
    clusterctl.cluster.x-k8s.io/move: "true"
type: Opaque
EOT
# FIXME: We will provide more settings in cluster-settings.env later, hardcode it for now
#if test "$CS_CCMLB=octavia-ovn"; then OCTOVN="--set octavia_ovn=true"; else unset OCTOVN; fi
# FIXME: How to pass the information that we want OVN loadbalancers???
# Workload cluster secret (for OCCM, CSI)
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
EOT
# Create ClusterRS
kubectl apply -f - <<EOT
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
EOT

# TODO: Create old style cloud.conf as well
if test -n "$OS_CACERT"; then
	CAFILE="
ca-file=/etc/config/cacert"
else
	unset CAFILE
fi
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
auth_url=$clouds__openstack__auth__auth_url
region=$clouds__openstack__region_name$CAFILE
$AUTHSECTION

[LoadBalancer]
manage-security-groups=true
enable-ingress-hostname=true
create-monitor=true
$LB_OVN
EOT
umask $OLD_UMASK
CL_CONF_B64=$(base64 -w0 <~/tmp/cloud-$OS_CLOUD.conf)
# CAINSERT is already set above
CL_YAML_WLOLD_B64=$(base64 -w0 <<EOT
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
  cloud-config-secret: $CL_YAML_WLOLD_B64
kind: Secret
metadata:
  name: openstack-workload-cluster-secret
  namespace: $CS_NAMESPACE
  labels:
    clusterctl.cluster.x-k8s.io/move: "true"
type: addons.cluster.x-k8s.io/resource-set
EOT
# Create ClusterRS
kubectl apply -f - <<EOT
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
