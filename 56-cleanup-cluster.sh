#!/bin/bash
set -e
# Cleaning up inside cluster
# We need to remove the LB and Storage resources
if test -n "$1"; then
	SET="$1"
else
	if test -e cluster-settings.env; then SET=cluster-settings.env;
	else echo "You need to pass a cluster-settings.env file as parameter"; exit 1
	fi
fi
# Read settings -- make sure you can trust it
source "$SET"
kubectl get cluster -A
KCFG=~/.kube/$CS_NAMESPACE.$CL_NAME
export KUBECONFIG=$KCFG
# This is from KaaS v1, thanks for Roman, Matej, ...
echo "Cleaning cluster -n $CS_NAMESPACE $CL_NAME"
# We could prevent the creation of new pods and PVs
# Cordoning all nodes
echo "Note: NOT cordoning all nodes ..."
#kubectl get nodes -o=jsonpath="{'set -x\n'}{range .items[*]}{'kubectl cordon '}{.metadata.name}{'\n'}{end}" | bash
# Delete storage classes (prevents creation of new PVs)
echo "Note: NOT deleting storage classes ..."
#kubectl get storageclasses -o=jsonpath="{'set -x\n'}{range .items[*]}{'kubectl delete storageclass '}{.metadata.name}{' --ignore-not-found=true\n'}{end}" | bash
# Delete nginx ingress
INPODS=$(kubectl --namespace ingress-nginx get pods)
if echo "$INPODS" | grep nginx >/dev/null 2>&1; then
        echo -en " Delete ingress \n "
        timeout 150 kubectl delete -f ~/${CLUSTER_NAME}/deployed-manifests.d/nginx-ingress.yaml
fi
# Delete deployments with persistent volume claims
echo "Deleting deployments with persistent volume claims ..."
kubectl get deployments --all-namespaces -o=jsonpath="{'set -x\n'}{range .items[?(@.spec.template.spec.volumes[*].persistentVolumeClaim.claimName)]}{'kubectl delete deployment '}{.metadata.name}{' -n '}{.metadata.namespace}{' --grace-period=0 --ignore-not-found=true\n'}{end}" | bash
# Delete daemonsets with persistent volume claims
echo "Deleting daemonsets with persistent volume claims ..."
kubectl get daemonsets --all-namespaces -o=jsonpath="{'set -x\n'}{range .items[?(@.spec.template.spec.volumes[*].persistentVolumeClaim.claimName)]}{'kubectl delete daemonset '}{.metadata.name}{' -n '}{.metadata.namespace}{' --grace-period=0 --ignore-not-found=true\n'}{end}" | bash
# Delete statefulsets with persistent volume claims
echo "Deleting statefulsets with persistent volume claims ..."
kubectl get statefulsets --all-namespaces -o=jsonpath="{'set -x\n'}{range .items[?(@.spec.template.spec.volumes[*].persistentVolumeClaim.claimName)]}{'kubectl delete statefulset '}{.metadata.name}{' -n '}{.metadata.namespace}{' --grace-period=0 --ignore-not-found=true\n'}{end}" | bash
# Delete all CronJobs
echo "Deleting all CronJobs ..."
kubectl get cronjobs --all-namespaces -o=jsonpath="{'set -x\n'}{range .items[*]}{'kubectl delete cronjob '}{.metadata.name}{' -n '}{.metadata.namespace}{' --grace-period=0 --force\n'}{end}" | bash
# Delete all Jobs
echo "Deleting all Jobs ..."
kubectl get jobs --all-namespaces -o=jsonpath="{'set -x\n'}{range .items[*]}{'kubectl $KCONTEXT delete job '}{.metadata.name}{' -n '}{.metadata.namespace}{' --grace-period=0 --force\n'}{end}" | bash
# Delete pods with persistent volume claims
echo "Deleting pods with persistent volume claims ..."
kubectl get pods --all-namespaces -o=jsonpath="{'set -x\n'}{range .items[?(@.spec.volumes[*].persistentVolumeClaim.claimName)]}{'kubectl $KCONTEXT delete pod '}{.metadata.name}{' -n '}{.metadata.namespace}{' --grace-period=0 --ignore-not-found=true\n'}{end}" | bash
# Delete persistent volume claims
echo "Delete persistent volume claims"
kubectl get pvc --all-namespaces -o=jsonpath="{'set -x\n'}{range .items[*]}{'kubectl delete pvc '}{.metadata.name}{' -n '}{.metadata.namespace}{' --grace-period=0 --ignore-not-found=true --wait\n'}{end}" | bash
# Delete Persistent Volumes
echo "Deleting all Persistent Volumes..."
kubectl get pv -o=jsonpath="{'set -x\n'}{range .items[*]}{'kubectl $KCONTEXT delete pv '}{.metadata.name}{'  --grace-period=0 --ignore-not-found=true --wait\n'}{end}" | bash
# Delete all Ingress
echo "Deleting all Ingress ..."
kubectl get ingress --all-namespaces -o=jsonpath="{'set -x\n'}{range .items[*]}{'kubectl delete ingress '}{.metadata.name}{' -n '}{.metadata.namespace}{' --grace-period=0 --ignore-not-found=true\n'}{end}" | bash
# Delete all deployments
echo "Deleting all deployments (but kube-system) ..."
kubectl get deployments --all-namespaces --field-selector metadata.namespace!=kube-system -o=jsonpath="{'set -x\n'}{range .items[*]}{'kubectl delete deployment '}{.metadata.name}{' -n '}{.metadata.namespace}{' --grace-period=0 --ignore-not-found=true\n'}{end}" | bash
# Delete all daemonsets - avoid hitting OCCM, CSI
echo "Deleting all daemonsets (but kube-system) ..."
kubectl get daemonsets --all-namespaces --field-selector metadata.namespace!=kube-system -o=jsonpath="{'set -x\n'}{range .items[*]}{'kubectl delete daemonset '}{.metadata.name}{' -n '}{.metadata.namespace}{' --grace-period=0 --ignore-not-found=true\n'}{end}" | bash
# Delete all statefulsets - avoid hitting OCCM, CSI
echo "Deleting all statefulsets (but kube-system) ..."
kubectl get statefulsets --all-namespaces --field-selector metadata.namespace!=kube-system -o=jsonpath="{'set -x\n'}{range .items[*]}{'kubectl $KCONTEXT delete statefulset '}{.metadata.name}{' -n '}{.metadata.namespace}{' --grace-period=0 --ignore-not-found=true\n'}{end}" | bash
# Delete all Services (except `kubernetes` service in `default` namespace)
echo "Deleting all Services (but kube-system, kubernetes) ..."
kubectl get services --all-namespaces --field-selector metadata.namespace!=kube-system,metadata.name!=kubernetes -o=jsonpath="{'set -x\n'}{range .items[*]}{'kubectl delete service '}{.metadata.name}{' -n '}{.metadata.namespace}{' --grace-period=0 --ignore-not-found=true\n'}{end}" | bash
# Delete workload pods
echo "Deleting pods (but kube-system) ..."
kubectl get pods --all-namespaces --field-selector metadata.namespace!=kube-system -o=jsonpath="{'set -x\n'}{range .items[*]}{'kubectl $KCONTEXT delete pod '}{.metadata.name}{' -n '}{.metadata.namespace}{' --grace-period=0 --ignore-not-found=true\n'}{end}" | bash
# TODO:
# - Delete ingress-nginx config map and secret and ingressclass
# - Delete helm release secret
echo "# Note: You may need to delete a helm secret to be able to install ingress-nginx via helm again"
kubectl get secrets -A
# DONE
echo "Cluster should be empty now and ready for deletion"
kubectl get pods -A
