#!/bin/bash

# turboEnv.sh
# Set up the kubernetes namespace, network policies and registry to use.

# Get the parameters used for kubernetes, gluster, turbo setup
source /opt/local/etc/turbo.conf

# Set basepath for xl yaml
yamlBasePath="/opt/turbonomic/kubernetes/yaml"
imageBasePath="/opt/turbonomic/kubernetes/images"

declare -a node=(${node})

# Build the node array to pass into kubespray
for i in "${node[@]}"; do
  export node${#node[@]}=${i}
done
# get length of an array
tLen=${#node[@]}

# Set up the storage class for gluster
echo "Check if the storage class exists"
echo "============================================="
storageClass=$(kubectl get sc)
if [ -z "${storageClass}" ]; then
  # Check whether the local storage class is enabled
  # If so, configure for local storage and make this the default storage class (instead of Gluster)
  # This must be done after installing Kubernetes, but before running the operator.
  # Case-insensitive comparsion (due to the use of ',,')
  if [ X${storage,,} = "Xlocal" ]; then
    echo "The local storage driver is enabled, configuring..."
    kubectl create -f ${yamlBasePath}/storage-class/local-storage-sc.yaml
    # Set local storage as the default storage class
    kubectl patch storageclass turbo-local-storage -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
    echo "The local storage class has been created and set as the default."
    # Create the local storage persistent volumes
    kubectl create -f ${yamlBasePath}/persistent-volumes/local-storage-pv.yaml
    echo "The local storage persistent volumes have been created."
  elif [ X${storage,,} = "Xshared" ]; then
    # Create the Gluster storage class and make it the default storage class.
    echo "Create Gluster StorageClass"
    echo "-------------------"
    export HEKETI_CLI_SERVER=$(kubectl get svc/heketi --template 'http://{{.spec.clusterIP}}:{{(index .spec.ports 0).port}}')
    cp ${yamlBasePath}/storage-class/gluster-heketi-sc.yaml.template ${yamlBasePath}/storage-class/gluster-heketi-sc.yaml
    sed -i "s#HEKETI_CLI_SERVER#${HEKETI_CLI_SERVER}#g" ${yamlBasePath}/storage-class/gluster-heketi-sc.yaml
    sed -i "s#ADMIN_KEY#${ADMIN_KEY}#g" ${yamlBasePath}/storage-class/gluster-heketi-sc.yaml
    if [ ${tLen} = 1 ]; then
      sed -i "s#GLUSTER_REPLICA#none#g" ${yamlBasePath}/storage-class/gluster-heketi-sc.yaml
    else
      sed -i "s#GLUSTER_REPLICA#replicate:${tLen}#g" ${yamlBasePath}/storage-class/gluster-heketi-sc.yaml
    fi
    kubectl create -f ${yamlBasePath}/storage-class/gluster-heketi-sc.yaml
    echo "heketi api server = ${HEKETI_CLI_SERVER}"
    echo

    # Set gluster as the default storage class
    kubectl patch storageclass gluster-heketi -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
  else
    echo "Could not detect the desired StorageClass. Please set the 'storage' property in turbo.conf to either 'shared' or 'local'."
  fi
fi

# Set namespace
echo ""
echo "Check if the namespace exists"
echo "============================="
checkNameSpace=$(kubectl config get-contexts turbo | grep turbo)
if [ -z "${checkNameSpace}" ]; then
  echo "Create Namespace"
  echo "----------------"
  kubectl create -f ${yamlBasePath}/namespace/turbo.yaml
  kubectl config set-context $(kubectl config current-context) --namespace=turbonomic
  echo
fi
