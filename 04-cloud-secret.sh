#!/bin/bash
# Create cloud secret
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
# Create namespace
test -n "$CS_NAMESPACE"
kubectl create namespace "$CS_NAMESPACE" || true
# Use csp helper chart to create cloud secret
# Notes on expected clouds.yaml:
# - It should have the secrets (which you often keep in secure.yaml instead) merged into it
# - The cloud should be called openstack
# - We will detect a cacert in there and pass it to the helper chart
if ! test -r "$CLOUDS_YAML"; then echo "clouds.yaml $CLOUDS_YAML not readable"; exit 2; fi
CA=$(grep -A12 "^  *$OS_CLOUD: *$" $CLOUDS_YAML | grep 'cacert:' | head -n1 | sed 's/^ *cacert: //')
OS_CACERT=${OS_CACERT:-$CA}
if test -n "$OS_CACERT"; then
	echo "Found CA cert file configured to be $OS_CACERT"
	if test ! -r "$OS_CACERT"; then echo "... but could not access it. FATAL."; exit 3; fi
	# Call the helm helper chart now
	helm upgrade -i openstack-secrets -n "$CS_NAMESPACE" --create-namespace https://github.com/SovereignCloudStack/openstack-csp-helper/releases/latest/download/openstack-csp-helper.tgz -f $CLOUDS_YAML --set cacert="$(cat $OS_CACERT)"
else
	helm upgrade -i openstack-secrets -n "$CS_NAMESPACE" --create-namespace https://github.com/SovereignCloudStack/openstack-csp-helper/releases/latest/download/openstack-csp-helper.tgz -f $CLOUDS_YAML
fi
