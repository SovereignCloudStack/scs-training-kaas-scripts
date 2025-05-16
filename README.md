# scs-training-kaas-scripts
Some helpful snippets of code to automate the creation of Cluster-Stacks

## Goals
Creating cluster stacks and cluster based on these takes a significant
number of steps that are hard to remember correctly for people that are
not cluster-API and Cluster Class experts.

We hide them in a number of distinct scripts. The reason for not doing
everything in one script is that you register cloud secrets or install CAPI
much less often than install cluster classes, which happens much less often
than creating clusters.

## Settings
There is a [cluster-settings-template.env](cluster-settings-template.env) file
that contains the parameters typically adjusted by users. Please create a
copy, fill it in, and pass it to the scripts. You can also use the 
[cluster-settings.env.sample](cluster-settings.env.sample) file as a reference, 
which includes example values for all parameters.

### Configuration Parameters

#### Registry and Repository Settings
- `CS_REGISTRY=registry.scs.community/kaas/cluster-stacks`: Registry for cluster stacks
- `CSO_HELM_REPO=oci://registry.scs.community/cluster-stacks/cso`: Helm chart repository for CSO

#### Namespace and Project Settings
- `CS_NAMESPACE=cluster`: Namespace for cluster resources
- `CLOUDS_YAML=~/.config/openstack/clouds.yaml`: Path to OpenStack credentials file
- `OS_CLOUD=${OS_CLOUD:-openstack}`: Name of the cloud in the clouds.yaml file

#### Cluster Stack Settings
- `CS_MAINVER=`: Kubernetes major.minor version (e.g., 1.32)
- `CS_VERSION=`: Cluster stack template version (e.g., v1 or v0-sha.XXXXXXX)
- `CS_CHANNEL=custom`: Update channel for ClusterStack
- `CS_AUTO_SUBSCRIBE=false`: Whether to automatically subscribe to updates

#### Workload Cluster Settings
- `CL_PATCHVER=`: Full Kubernetes version (e.g., 1.32.3)
- `CL_NAME=`: Cluster name
- `CL_PODCIDR=172.16.0.0/18`: Pod CIDR range
- `CL_SVCCIDR=10.96.0.0/14`: Service CIDR range
- `CL_CTRLNODES=1`: Number of control plane nodes
- `CL_WRKRNODES=1`: Number of worker nodes
- `CL_WORKER_CLASS=default-worker`: Worker class used for machine deployments
- `CL_LB_TYPE=octavia-ovn`: Load balancer type (depends on OpenStack environment)
- `CL_WAIT_TIMEOUT=3600`: Timeout for waiting on cluster provisioning (seconds)

## Scripts
### Once per management host
* `00-bootstrap-vm-cs.sh`: Install the needed software to be able to do
  cluster management on this host. (Developed for Debian and Ubuntu.)
  This is only needed if you do not have the needed tools preinstalled.
* `01-kind-cluster.sh`: Create kind cluster
* `02-deploy-capi.sh`: Install ORC and CAPI.
* `03-deploy-cso.sh`: Install the Cluster Stack Operator.

### Once per OpenStack Project in which we want to install clusters (NS)
* `04-cloud-secret.sh`: Create namespace and secrets to work with the
  wanted OpenStack project.

### Once per Kubernetes aka CS version (maj.min)
* `05-deploy-cstack.sh`: Create the Cluster Stack which is a template
  for various clusters with the same major minor version of k8s.
  Should trigger cluster class creation and image registration.
* `06-wait-clusterclass.sh`: Wait for the cluster class to be ready

### Once per cluster
* `07-create-cluster.sh`: Create a workload cluster as per all the settings
  that are passed.
* `08-wait-cluster.sh`: Wait for the workload cluster to be ready and save kubeconfig

* `17-delete-cluster.sh`: Remove cluster when no longer needed.
