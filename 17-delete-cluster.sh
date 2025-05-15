
#!/bin/bash
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
# Sanity checks 
if test -z "$CS_MAINVER"; then echo "Configure CS_MAINVER"; exit 2; fi
if test -z "$CS_VERSION"; then echo "Configure CS_VERSION"; exit 3; fi
if test -z "$CL_PATCHVER"; then echo "Configure CL_PATCHVER"; exit 4; fi
if test -z "$CL_NAME"; then echo "Configure CL_NAME"; exit 5; fi
if test -z "$CL_PODDIDR"; then echo "Configure CL_PODCIDR"; exit 6; fi
if test -z "$CL_SVCCIDR"; then echo "Configure CL_SVCCIDR"; exit 7; fi
if test -z "$CL_CTRLNODES"; then echo "Configure CL_CTRLNODES"; exit 8; fi
if test -z "$CL_WRKRNODES"; then echo "Configure CL_WRKRNODES"; exit 9; fi
# Delete Cluster
kubectl delete -n "$CS_NAMESPACE" cluster "$CL_NAME"
