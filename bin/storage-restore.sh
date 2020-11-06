#!/bin/bash

# storage-restore.sh
# Fix issues that may be caused by underlying storage layer

# redirect stdout/stderr to a file
current_time=$(date "+%Y.%m.%d-%H.%M.%S")
exec &> /tmp/restore-gluster-${current_time}.log

# Functions

# Run this as the root user
if [[ $(/usr/bin/id -u) -ne 0 ]]
then
  echo "Not running as root, please become the root user, or use sudo"
  exit
fi

# Check to see if kubernetes is up and running
export KUBECONFIG=/root/.kube/config
/usr/local/bin/kubectl get pod -n kube-system
kubectlStatus="$?"
while [ "${kubectlStatus}" -ne "0" ]
do
  /usr/local/bin/kubectl get pod -n kube-system
  kubectlStatus="$?"
#if [ "${kubectlStatus}" -eq "0" ]
#then
#echo "Kubernetes has started"
#exit 1
#fi
  echo "Kubernetes is not ready...."
  sleep 30
done

# Set the initial gluster pod
export GLUSTER_POD=$(/usr/local/bin/kubectl get pods -n default -o json  | jq -r '.items[] | select(.status.phase = "Running" or ([ .status.conditions[] | select(.type == "Ready" and .state == true) ] | length ) == 1 ) | .metadata.namespace + "/" + .metadata.name' | grep gluster | awk -F/ '{print $2}')

export HEKETI_POD=$(/usr/local/bin/kubectl get pods -n default -o json  | jq -r '.items[] | select(.status.phase = "Running" or ([ .status.conditions[] | select(.type == "Ready" and .state == true) ] | length ) == 1 ) | .metadata.namespace + "/" + .metadata.name' | grep heketi | awk -F/ '{print $2}')

echo "Scale down the Operator"
echo "-----------------------"
/usr/local/bin/kubectl scale deployment --replicas=0 t8c-operator -n turbonomic
operatorCount=$(/usr/local/bin/kubectl get pod -n turbonomic | grep t8c-operator | wc -l)
while [ ${operatorCount} -gt 0 ]
do
  operatorCount=$(/usr/local/bin/kubectl get pod -n turbonomic | grep t8c-operator | wc -l)
done
echo

echo "Scale down Turbonomic"
echo "---------------------"
/usr/local/bin/kubectl scale deployment --replicas=0 --all -n turbonomic
turboPodCount=$(/usr/local/bin/kubectl get pod -n turbonomic | wc -l)
while [ ${turboPodCount} -gt 0 ]
do
  turboPodCount=$(/usr/local/bin/kubectl get pod -n turbonomic | egrep -v "prometheus-node-exporter|fluent-bit-loki|loki|elasticsearch|logstash|NAME" | wc -l)
done
echo


# Delete the gluster pod and wait for it to come back.
echo "Restart the Glusterfs Pod"
echo "-------------------------"
/usr/local/bin/kubectl delete pod -n default ${GLUSTER_POD}
echo "** NOTE: This should take about 5 mins."

export NEW_GLUSTER_POD=$(/usr/local/bin/kubectl get pods -n default -o json  | jq -r '.items[] | select(.status.phase = "Running" or ([ .status.conditions[] | select(.type == "Ready" and .state == true) ] | length ) == 1 ) | .metadata.namespace + "/" + .metadata.name' | grep gluster | awk -F/ '{print $2}')

/usr/local/bin/kubectl wait --for=condition=Ready pod/${NEW_GLUSTER_POD} -n default --timeout=600s
printf '\nFinished\n'
echo

# Delete the heketi pod and wait for it to come back.
echo "Restart the Heketi Pod"
echo "----------------------"
# Delete heketi pod and wait for it to come back.
/usr/local/bin/kubectl delete pod -n default ${HEKETI_POD}
echo "** NOTE: This should take about 30 secs."

export NEW_HEKETI_POD=$(/usr/local/bin/kubectl get pods -n default -o json  | jq -r '.items[] | select(.status.phase = "Running" or ([ .status.conditions[] | select(.type == "Ready" and .state == true) ] | length ) == 1 ) | .metadata.namespace + "/" + .metadata.name' | grep heketi | awk -F/ '{print $2}')

/usr/local/bin/kubectl wait --for=condition=Ready pod/${NEW_HEKETI_POD} -n default --timeout=30s
printf '\nFinished\n'
echo

echo "Scale Up Turbonomic"
echo "-------------------"
/usr/local/bin/kubectl scale deployment --replicas=1 t8c-operator -n turbonomic

# Watch the environment to ensure Turbonomic Comes up
echo
echo "Use the following to ensure Turbonomic is healthy:"
echo "------------------------------------"
echo "watch /usr/local/bin/kubectl get pods -n turbonomic"
echo "------------------------------------"

