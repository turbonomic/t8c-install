#!/bin/bash

# Get hostname
nodeHostname=$(hostnamectl status | grep "Static hostname:" | awk -F: '{print $2}' | xargs)

# Check if gluster is the default storage class on the ova.  If it is, do nothing.
kubectl get sc --no-headers | grep turbo-local-storage
result="$?"
if [ $result -eq 0 ]
then

  # Check if suspend needs to be implemented

  if [ ! -d "/data/turbonomic/redis-data-redis-master-0" ]
  then
    mkdir -p /data/turbonomic/redis-data-redis-master-0
  fi

  # Set or correct permissions on redis PV directory
  chmod 0777 /data/turbonomic/redis-data-redis-master-0

  cat <<EOF > /opt/turbonomic/kubernetes/yaml/persistent-volumes/suspend-storage.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: local-pv-redis-data-redis-master-0
  labels:
    partition: redis-data-redis-master-0
spec:
  capacity:
    storage: 4Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: turbo-local-storage
  claimRef:
    name: redis-data-redis-master-0
    namespace: turbonomic
  local:
    path: /data/turbonomic/redis-data-redis-master-0
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.io/hostname
              operator: In
              values:
                - ${nodeHostname}
EOF

  # Create the persistent volumes
  suspendPvExists=$(/usr/local/bin/kubectl get pv  | grep local-pv-redis-data-redis-master-0)
  if [ -z "${suspendPvExists}" ]
  then
    kubectl apply -f /opt/turbonomic/kubernetes/yaml/persistent-volumes/suspend-storage.yaml
  fi
fi
