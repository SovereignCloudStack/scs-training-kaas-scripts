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
if ! type -p sonobuoy >/dev/null 2>/dev/null; then export PATH="$PATH:~/bin"; fi
SB=$(sonobuoy status)
while true; do
	echo "$SB"
	if ! echo "$SB" | grep "still running" >/dev/null; then break; fi
	sleep 30
	SB=$(sonobuoy status)
done
# Allow for results collection
while true; do
	#echo "$SB"
	if ! echo "$SB" | grep "Preparing results" >/dev/null; then break; fi
	sleep 10
	SB=$(sonobuoy status)
done
sonobuoy retrieve
RES=$(ls -t 20*sonobuoy*.tar.gz | head -n1)
sonobuoy results $RES
NRPASSED=$(echo "$SB" | awk '{ print $3; }' | grep passed | wc -l)
test $NRPASSED = 2
