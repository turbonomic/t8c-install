#!/bin/bash

# incremental or full backup of t8c
ACTION=incremental
if [ $# -eq 1 ]
  then
    ACTION=$1
fi

# Get all the pv's for turbo
PVC_NAME=($(kubectl get pv | egrep -v POLICY | awk '{print $6}'| awk -F/ '{print $2}'))
PV_NAME=($(kubectl get pv | egrep -v NAME | awk '{print $1}'))

# Scale DOWN all turbo pods to 0
function turbo_stop_all_pods {
    turbo_stop_all_pods=$(kubectl get deploy -n turbonomic --no-headers=true | cut -d ' ' -f1 | xargs -I % kubectl scale --replicas=0 deployment/% -n turbonomic)
    until [[ `kubectl get pods -n turbonomic | grep -v STATUS | wc -l` -eq 0  ]] ; do
        echo -e "turbo_STOP_all_pods: Waiting on Turbonetes POD(s) to TERMINATE, so far: \n`kubectl get pods -n turbonomic | grep -v NAME`"
        sleep 3
    done
    echo "All Turbonetes PODs are Terminated - Done waiting, exiting"
}

echo "Scale the deployments down to backup the pv's"
turbo_stop_all_pods
echo
sudo systemctl stop mariadb
if pgrep -x mysqld >/dev/null
then
  echo "Please make sure the database has stopped"
  exit 0
fi

# Backup the current pvc's
echo "Creating Backups"
for ((i=0;i<${#PVC_NAME[@]};i++))
do
  echo "${PVC_NAME[i]}"
  VOL_NAME=($(kubectl describe pv ${PV_NAME[i]} | grep vol_ | awk -F: '{print $2}' | sed -e 's/^[[:space:]]*//'))
  echo ${VOL_NAME}
  sudo mkdir -p /opt/pv
  sudo mkdir -p /mnt/${PVC_NAME[i]}
  sudo mount -t glusterfs localhost:${VOL_NAME} /mnt/${PVC_NAME[i]}
  pushd /mnt
  case $ACTION in
  incremental)
    sudo rsync -a --info=progress2 ${PVC_NAME[i]} /opt/pv/;;
  full)
    sudo tar cf /opt/pv/${PVC_NAME[i]}.tar ${PVC_NAME[i]};;
  *)
    echo "$0 [incremental|full]"
    exit 0
  esac
  popd
  sudo umount /mnt/${PVC_NAME[i]}
  sudo rm -rf /mnt/${PVC_NAME[i]}
  echo
done

# Delete the helm install
#echo "Deleting the xl-release helm version"
#/usr/local/bin/helm del --purge xl-release
#echo

# Check and wait for the pv's to be deleted
#PV_ALIVE=$(kubectl get pv | wc -l)
#while [ ! $PV_ALIVE = 0 ]
#do
#  echo "Still deleting volumes"
#  sleep 30
#  PV_ALIVE=$(kubectl get pv | wc -l)
#done
