#!/bin/bash
set -e
# Detect MTU of interface with default route
DEV=$(ip route show default | head -n1 | sed 's/^.*dev \([^ ]*\).*$/\1/')
CLOUDMTU=$(ip link show $DEV | head -n1 | sed 's/^.*mtu \([0-9]*\) .*$/\1/')
DOCKERMTU=$(ip link show docker0 | head -n1 | sed 's/^.*mtu \([0-9]*\) .*$/\1/')
if test $((DOCKERMTU+50)) -gt $CLOUDMTU; then
	echo "WARNING: Consider ip link set dev docker0 mtu $((CLOUDMTU-50))"
	echo "   ... and you may want to do the same for kind's bridge device br-*"
fi
# Create kind cluster
if test "$(kind get clusters)" != "kind"; then
	kind create cluster
else
	echo "kind cluster already running"
fi
