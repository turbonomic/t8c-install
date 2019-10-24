#!/bin/bash

# incremental or complete restore of t8c
ACTION=incremental
if [ $# -eq 1 ]
  then
    ACTION=$1
fi

# Scale DOWN all turbo pods to 0
function turbo_stop_all_pods {
    turbo_stop_all_pods=$(kubectl get deploy -n turbonomic --no-headers=true | cut -d ' ' -f1 | xargs -I % kubectl scale --replicas=0 deployment/% -n turbonomic)
    until [[ `kubectl get pods -n turbonomic | grep -v STATUS | wc -l` -eq 0  ]] ; do
        echo -e "turbo_STOP_all_pods: Waiting on Turbonetes POD(s) to TERMINATE, so far: \n`kubectl get pods -n turbonomic | grep -v NAME`"
        sleep 3
    done
    echo "All Turbonetes PODs are Terminated - Done waiting, exiting"
}

# Scale UP all Turbonetes PODs to 1
function turbo_start_all_pods {
    turbo_start_all_pods=$(kubectl get deploy -n turbonomic --no-headers=true | cut -d ' ' -f1 | xargs -I % kubectl scale --replicas=1 deployment/% -n turbonomic)
    until [[ `kubectl get pods -n turbonomic | grep -v STATUS | grep -i "Running" | wc -l` -ge 30  ]] ; do
        echo -e "turbo_START_all_pods: Waiting on Turbonetes POD(s) to come up, so far: \n`kubectl get pods -n turbonomic | grep -v NAME`"
        sleep 3
    done
    echo -e "turbo_START_all_pods: All Turbonetes POD(s) are Running: \n `kubectl get pods -n turbonomic | grep -v NAME`"
    echo "All Turbonetes PODs are Running - Done waiting, exiting"
}

# Install the t8c operator and environment
kubectl create -f /opt/turbonomic/kubernetes/operator/deploy/service_account.yaml -n turbonomic
kubectl create -f /opt/turbonomic/kubernetes/operator/deploy/role.yaml -n turbonomic
kubectl create -f /opt/turbonomic/kubernetes/operator/deploy/role_binding.yaml -n turbonomic
kubectl create -f /opt/turbonomic/kubernetes/operator/deploy/crds/charts_v1alpha1_xl_crd.yaml -n turbonomic
kubectl create -f /opt/turbonomic/kubernetes/operator/deploy/operator.yaml -n turbonomic
kubectl create -f /opt/turbonomic/kubernetes/operator/deploy/crds/charts_v1alpha1_xl_cr.yaml -n turbonomic

# Wait until the pv's are up
sleep 30
PV_ALIVE=$(kubectl get pvc | grep Pending | wc -l)
while [ ! $PV_ALIVE = 0 ]
do
  echo "still creating pv's"
  sleep 30
  PV_ALIVE=$(kubectl get pvc | grep Pending | wc -l)
done

# Get all the pv's for turbo
PVC_NAME=($(kubectl get pv | egrep -v POLICY | awk '{print $6}'| awk -F/ '{print $2}'))
PV_NAME=($(kubectl get pv | egrep -v NAME | awk '{print $1}'))

# Bring down the pods to recover the data
turbo_stop_all_pods


# Restore the current pvc's
echo "Restoring Backups"
for ((i=0;i<${#PVC_NAME[@]};i++))
do
  echo "${PVC_NAME[i]}"
  VOL_NAME=($(kubectl describe pv ${PV_NAME[i]} | grep vol_ | awk -F: '{print $2}' | sed -e 's/^[[:space:]]*//'))
  echo ${VOL_NAME}
  sudo mkdir -p /mnt/${PVC_NAME[i]}
  sudo mount -t glusterfs localhost:${VOL_NAME} /mnt/${PVC_NAME[i]}
  case $ACTION in
  incremental)
    pushd /mnt/${PVC_NAME[i]}
    sudo rsync -a --info=progress2 /opt/pv/${PVC_NAME[i]}/ . --delete;;
  full)
    pushd /mnt/
    sudo tar xf /opt/pv/${PVC_NAME[i]}.tar;;
  *)
    echo "$0 [incremental|full]"
  esac
  if [ ${PVC_NAME[i]} = consul-data ]
  then
    case $ACTION in
    incremental)
      sudo rsync -a --info=progress2 /opt/pv/consuldata/ . --delete;;
    full)
      sudo tar xf /opt/pv/consuldata.tar;;
    *)
      echo "$0 [incremental|full]"
    esac
  fi
  if [ ${PVC_NAME[i]} = arangodb ]
  then
    sudo chgrp -R 2001 /mnt/${PVC_NAME[i]}
  fi
  if [ ${PVC_NAME[i]} = reporting ]
  then
    sudo chgrp -R 2009 /mnt/${PVC_NAME[i]}
  fi
  popd
  sudo umount /mnt/${PVC_NAME[i]}
  sudo rm -rf /mnt/${PVC_NAME[i]}
  echo
done

# Start the pods
echo "Bring up the pods"
turbo_start_all_pods

sudo systemctl start mariadb
