#!/bin/bash

# start or stop t8c
ACTION=$1
# use turbonomic namespace by default
NAMESPACE=turbonomic
if [ $# -eq 2 ]
  then
    NAMESPACE=$2
fi

# Scale DOWN all turbo pods to 0
function turbo_stop_all_pods {
    turbo_stop_all_pods=$(kubectl get deploy -n ${NAMESPACE} --no-headers=true | cut -d ' ' -f1 | xargs -I % kubectl scale --replicas=0 deployment/% -n ${NAMESPACE})
    until [[ `kubectl get pods -n ${NAMESPACE} | grep -v STATUS | wc -l` -eq 0  ]] ; do
        echo -e "turbo_STOP_all_pods: Waiting on Turbonetes POD(s) to TERMINATE, so far: \n`kubectl get pods -n ${NAMESPACE} | grep -v NAME`"
        sleep 3
    done
    echo "All Turbonetes PODs are Terminated - Done waiting, exiting"
}

# Scale UP all Turbonetes PODs to 1
function turbo_start_all_pods {
    turbo_start_all_pods=$(kubectl get deploy -n ${NAMESPACE} --no-headers=true | cut -d ' ' -f1 | xargs -I % kubectl scale --replicas=1 deployment/% -n ${NAMESPACE})
    until [[ `kubectl get pods -n ${NAMESPACE} | grep -v STATUS | grep -i "Running" | wc -l` -ge 30  ]] ; do
        echo -e "turbo_START_all_pods: Waiting on Turbonetes POD(s) to come up, so far: \n`kubectl get pods -n ${NAMESPACE} | grep -v NAME`"
        sleep 3
    done
    echo -e "turbo_START_all_pods: All Turbonetes POD(s) are Running: \n `kubectl get pods -n ${NAMESPACE} | grep -v NAME`"
    echo "All Turbonetes PODs are Running - Done waiting, exiting"
}

case $ACTION in
start)
  # Start the pods
  #echo "Bring up the pods"
  turbo_start_all_pods;;
stop)
  # Bring down the pods to recover the data
  turbo_stop_all_pods;;
*)
  echo "$0 [start|stop] <namespace>"
esac