#!/bin/bash
set -e
# Detect MTU of interface with default route
DEV=$(ip route show default | head -n1 | sed 's/^.*dev \([^ ]*\).*$/\1/')
CLOUDMTU=$(ip link show $DEV | head -n1 | sed 's/^.*mtu \([0-9]*\) .*$/\1/')
DOCKERMTU=$(ip link show docker0 | head -n1 | sed 's/^.*mtu \([0-9]*\) .*$/\1/')
if test $DOCKERMTU -gt $CLOUDMTU; then
	echo "WARNING: Consider setting { \"mtu\": $((8*($CLOUDMTU/8))) } in /etc/docker/daemon.json"
	echo "  and restart docker and do docker network rm kind ..."
	echo "If you see ImagePullBackOff and ImagePullErrors, you now know why."
	sudo ip link set dev docker0 mtu $((8*($CLOUDMTU/8)))
	# Just in case ...
	sudo sysctl net.ipv4.tcp_mtu_probing=1
fi
# Create kind cluster
if test "$(kind get clusters)" != "kind"; then
	unset KUBECONFIG
	kind create cluster
else
	echo "kind cluster already running"
fi
kubectl cluster-info
KINDMTU=$(docker network inspect kind | jq -r '.[] | .Options."com.docker.network.driver.mtu"')
if test $KINDMTU -gt $DOCKERMTU; then
	echo -e "\e[0;31mWARNING: Found kind MTU $KINDMTU > docker0 $DOCKERMTU\e[0;0m"
	echo "  Consider setting { \"mtu\": $((8*($CLOUDMTU/8))) } in /etc/docker/daemon.json"
	echo "  and restart docker and do docker network rm kind ..."
	echo "If you see ImagePullBackOff and ImagePullErrors, you now know why."
fi
