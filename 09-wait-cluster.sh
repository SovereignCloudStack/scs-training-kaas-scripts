#!/bin/bash
# Wait for cluster
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
#kubectl get cluster -A
#set -x
echo "# Wait for certificates for cluster -n $CS_NAMESPACE $CL_NAME"
TSTMP1=$(date +%s)
kubectl wait --timeout=8m --for=condition=certificatesavailable -n "$CS_NAMESPACE" kubeadmcontrolplanes -l cluster.x-k8s.io/cluster-name=$CL_NAME
TSTMP2=$(date +%s)
if test $((TSTMP2-TSTMP1)) -gt 1; then echo "# Waited $((TSTMP2-TSTMP1))s"; fi
kubectl get -n "$CS_NAMESPACE" cluster $CL_NAME
kubectl wait --timeout=12m --for=condition=Ready -n "$CS_NAMESPACE" machine -l cluster.x-k8s.io/control-plane,cluster.x-k8s.io/cluster-name=${CL_NAME}
TSTMP3=$(date +%s)
if test $((TSTMP3-TSTMP2)) -gt 1; then echo "# Waited $((TSTMP3-TSTMP2))s"; fi
clusterctl describe cluster -n "$CS_NAMESPACE" $CL_NAME --grouping=false
KCFG=~/.kube/$CS_NAMESPACE.$CL_NAME
OLDUMASK=$(umask)
umask 0077
clusterctl get kubeconfig -n "$CS_NAMESPACE" $CL_NAME > $KCFG
umask $OLDUMASK
WAIT=0
while test $WAIT -lt 200; do
	KUBECONFIG=$KCFG kubectl get nodes -o wide >/dev/null 2>&1 && break
	let WAIT+=10
	sleep 10
done
KUBECONFIG=$KCFG kubectl get nodes -o wide
KUBECONFIG=$KCFG kubectl get pods -A
echo "# Hint: Use KUBECONFIG=$KCFG kubectl ... to access your workload cluster -n $CS_NAMESPACE $CL_NAME"
