# scs-training-kaas-scripts
Some helpful snippets of code to automate the creation of Cluster-Stacks

## Goals
Creating cluster stacks and cluster based on these takes a significant
number of stacks that are hard to remember correctly for people that are
not cluster-API and Cluster Class expert.

We this hide them in a number of distinct steps that are in numbered scripts.
The reason for not doing everything in one script is that you do register
cloud secrets or install capi much less often than install cluster classses
which happens much less often than creating clusters.

## Settings
There is a [cluster-settings-template.env](cluster-settings-template.env) file
that contains the parameters typically adjusted by users. Please create a
copy, fill it in, and pass it to the scripts.

## Scripts
### Once per management host
* 00-bootstrap-vm-cs.sh: Install the needed software to be able to do
  cluster management on this host. (Developed for Debian 12.)
  This is only needed if you do not have the needed tools preinstalled.
* 01-kind-cluster.sh: Create kind cluster
* 02-deploy-capi.sh: Install ORC and CAPI.
* 03-deploy-cso.sh: Install the Cluster Stack Operator.

### Once per OpenStack Project in which we want to install clusters (NS)
* 04-cloud-secret.sh: Create namespace and secrets to work with the
  wanted OpenStack project.

### Once per Kubernetes aka CS version (maj.min)
* 05-deploy-cstack.sh: Create the Cluster Stack which is a template
  for various clusters with the same major minor version of k8s.
  Should trigger cluster class creation and image registration.
* 06-wait-clusterclass.sh: Wait for the cluster class (not yet implemented)

### Once per cluster
* 07-create-cluster.sh: Create a workload cluster as per all the settings
  that are passed.
* 08-wait-cluster.sh: Wait for the workload cluster (not yet implemented)

* 17-delete-cluster.sh: Remove cluster again.


  
