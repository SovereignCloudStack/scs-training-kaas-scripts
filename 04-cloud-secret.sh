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
# Read helper
THISDIR=$(dirname 0)
source "$THISDIR/yaml_parse.sh"

# Create namespace
test -n "$CS_NAMESPACE"
kubectl create namespace "$CS_NAMESPACE" || true
# Use csp helper chart to create cloud secret
# Notes on expected clouds.yaml:
# - It should have the secrets (which you often keep in secure.yaml instead) merged into it
# - The cloud should be called openstack
# - We will detect a cacert in there and pass it to the helper chart
if ! test -r "$CLOUDS_YAML"; then echo "clouds.yaml $CLOUDS_YAML not readable"; exit 2; fi
CA=$(RMVTREE=1 extract_yaml clouds.$OS_CLOUD.cacert <$CLOUDS_YAML | sed 's/^\s*cacert: //' || true)
OS_CACERT="${OS_CACERT:-$CA}"
# Extract auth parts from secure.yaml if existent, assume same indentation
SEC_YAML="${CLOUDS_YAML%clouds.yaml}secure.yaml"
if test -r "$SEC_YAML"; then SECRETS=$(RMVTREE=1 RMVCOMMENT=1 extract_yaml clouds.$OS_CLOUD.auth < $SEC_YAML || true); fi
# Construct a clouds.yaml (mode 0600):
# - Only extracting one cloud addressed by $OS_CLOUD
# - By merging secrets in from secure.yaml
# - By renaming it to openstack (current CS limitation)
# - By removing cacert setting
# Store it securely in ~/tmp/clouds-$OS_CLOUD.yaml
OLD_UMASK=$(umask)
umask 0177
APPEND="$SECRETS" RMVCOMMENT=1 REMOVE=cacert extract_yaml clouds.$OS_CLOUD < $CLOUDS_YAML | sed "s/^\\(\\s*\\)\\($OS_CLOUD\\):/\\1openstack:/" > ~/tmp/clouds-$OS_CLOUD.yaml
umask $OLD_UMASK
# FIXME: We will provide more settings in cluster-settings.env later, hardcode it for now
#if test "$CS_CCMLB=octavia-ovn"; then OCTOVN="--set octavia_ovn=true"; else unset OCTOVN; fi
OCTOVN="--set octavia_ovn=true"
if test -n "$OS_CACERT"; then
	echo "Found CA cert file configured to be \"$OS_CACERT\""
	OS_CACERT="$(ls ${OS_CACERT/\~/$HOME})"
	# This will error out as needed
	# Extract last cert if things get too long (heuristic!)
	if test $(wc -l < $OS_CACERT) -gt 200; then
		LASTLN=$(tac $OS_CACERT | grep -n '^-----BEGIN CERTIFICATE-----$' | head -n1 | sed 's/^\([0-9]*\):.*/\1/')
		CACERT="$(tac $OS_CACERT | head -n $LN | tac)"
	else
		CACERT="$(cat $OS_CACERT)"
	fi
	# Call the helm helper chart now
	helm upgrade -i openstack-secrets -n "$CS_NAMESPACE" --create-namespace https://github.com/SovereignCloudStack/openstack-csp-helper/releases/latest/download/openstack-csp-helper.tgz -f ~/tmp/clouds-$OS_CLOUD.yaml --set cacert="$CACERT" $OCTOVN
else
	helm upgrade -i openstack-secrets -n "$CS_NAMESPACE" --create-namespace https://github.com/SovereignCloudStack/openstack-csp-helper/releases/latest/download/openstack-csp-helper.tgz -f ~/tmp/clouds-$OS_CLOUD.yaml $OCTOVN
fi
