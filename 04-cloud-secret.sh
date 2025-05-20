#!/bin/bash
# Create cloud secret for OpenStack credentials
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

# Create namespace
test -n "$CS_NAMESPACE"
echo "Creating namespace $CS_NAMESPACE..."
kubectl create namespace "$CS_NAMESPACE" || true

# Use csp helper chart to create cloud secret
# Notes on expected clouds.yaml:
# - It should have the secrets (which you often keep in secure.yaml instead) merged into it
# - The cloud should be called openstack
# - We will detect a cacert in there and pass it to the helper chart
if ! test -r "$CLOUDS_YAML"; then echo "clouds.yaml $CLOUDS_YAML not readable"; exit 2; fi
CA=$(grep -A12 "^\s\s*$OS_CLOUD:\s*\$" $CLOUDS_YAML | grep '^\s*cacert:' | head -n1 | tr -d '"' | sed 's/^\s*cacert: *//')
# This would be the safe way using yq:
# CA=$(yq -y < $CLOUDS_YAML '.clouds."'$OS_CLOUD'".cacert' | head -n1); if test "$CA" = "null"; then unset CA; fi
OS_CACERT="${OS_CACERT:-$CA}"
# FIXME: We will provide more settings in cluster-settings.env later, hardcode it for now
if test "$CS_CCMLB" = "octavia-ovn"; then OCTOVN="--set octavia_ovn=true"; else unset OCTOVN; fi
if test -n "$OS_CACERT"; then
	echo "Found CA cert file configured to be $OS_CACERT"
	if test ! -r "$OS_CACERT"; then echo "... but could not access it. FATAL."; exit 3; fi
	# Call the helm helper chart now
	helm upgrade -i openstack-secrets -n "$CS_NAMESPACE" --create-namespace https://github.com/SovereignCloudStack/openstack-csp-helper/releases/latest/download/openstack-csp-helper.tgz -f $CLOUDS_YAML --set cacert="$(cat $OS_CACERT)" $OCTOVN
else
	helm upgrade -i openstack-secrets -n "$CS_NAMESPACE" --create-namespace https://github.com/SovereignCloudStack/openstack-csp-helper/releases/latest/download/openstack-csp-helper.tgz -f $CLOUDS_YAML $OCTOVN
fi

echo "Cloud secret created successfully."
