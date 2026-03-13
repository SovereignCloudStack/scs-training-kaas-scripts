#!/bin/bash
# (c) Kurt Garloff <s7n@garloff.de>, 11/2025
# SPDX-License-Identifier: CC-BY-SA-4.0
set -e
THISDIR=$(dirname $0)
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
# Use workload cluster
export KUBECONFIG=~/.kube/$CS_NAMESPACE.$CL_NAME
# Install sonobuoy into ~/bin/ if needed
if ! type -p "sonobuoy" >/dev/null 2>&1; then
	cd ~
	curl -LO https://github.com/vmware-tanzu/sonobuoy/releases/download/v0.57.3/sonobuoy_0.57.3_linux_amd64.tar.gz
	tar xvzf sonobuoy_0.57.3_linux_amd64.tar.gz
	mkdir -p bin
	sudo mv sonobuoy bin
	if ! echo "$PATH" | grep "$HOME/bin" >/dev/null; then export PATH="$PATH:~/bin"; fi
fi
# See also https://github.com/SovereignCloudStack/standards/issues/982
sonobuoy run --plugin-env=e2e.E2E_PROVIDER=openstack --e2e-parallel=true --e2e-skip="\[Disruptive\]|NoExecuteTaintManager|HostPort validates that there is no conflict between pods with same hostPort but different hostIP and protocol"
