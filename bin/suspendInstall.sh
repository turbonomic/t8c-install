#!/bin/bash

# Check if suspend needs to be implemented

if [ ! -d "/data/turbonomic/redis-data-xl-release-redis-master-0" ]
then
  mkdir -p /data/turbonomic/redis-data-xl-release-redis-master-0
  chmod 7777 /data/turbonomic/redis-data-xl-release-redis-master-0
fi

if [ ! -d "/data/turbonomic/redis-data-xl-release-redis-replicas-0" ]
then
  mkdir -p /data/turbonomic/redis-data-xl-release-redis-replicas-0
  chmod 7777 /data/turbonomic/redis-data-xl-release-redis-replicas-0
fi

if [ ! -d "/data/turbonomic/redis-data-xl-release-redis-replicas-1" ]
then
  mkdir -p /data/turbonomic/redis-data-xl-release-redis-replicas-1
  chmod 7777 /data/turbonomic/redis-data-xl-release-redis-replicas-1
fi

if [ ! -d "/data/turbonomic/redis-data-xl-release-redis-replicas-2" ]
then
  mkdir -p /data/turbonomic/redis-data-xl-release-redis-replicas-2
  chmod 7777 /data/turbonomic/redis-data-xl-release-redis-replicas-2
fi

cat <<EOF > /opt/turbonomic/kubernetes/yaml/persistent-volumes/suspend-storage.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: local-pv-redis-data-xl-release-redis-master-0
  labels:
    partition: redis-data-xl-release-redis-master-0
spec:
  capacity:
    storage: 4Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: turbo-local-storage
  claimRef:
    name: redis-data-xl-release-redis-master-0
    namespace: turbonomic
  local:
    path: /data/turbonomic/redis-data-xl-release-redis-master-0
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.io/hostname
              operator: In
              values:
                - node1
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: local-pv-redis-data-xl-release-redis-replicas-0
  labels:
    partition: redis-data-xl-release-redis-replicas-0
spec:
  capacity:
    storage: 4Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: turbo-local-storage
  claimRef:
    name: redis-data-xl-release-redis-replicas-0
    namespace: turbonomic
  local:
    path: /data/turbonomic/redis-data-xl-release-redis-replicas-0
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.io/hostname
              operator: In
              values:
                - node1
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: local-pv-redis-data-xl-release-redis-replicas-1
  labels:
    partition: redis-data-xl-release-redis-replicas-1
spec:
  capacity:
    storage: 4Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: turbo-local-storage
  claimRef:
    name: redis-data-xl-release-redis-replicas-1
    namespace: turbonomic
  local:
    path: /data/turbonomic/redis-data-xl-release-redis-replicas-1
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.io/hostname
              operator: In
              values:
                - node1
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: local-pv-redis-data-xl-release-redis-replicas-2
  labels:
    partition: redis-data-xl-release-redis-replicas-2
spec:
  capacity:
    storage: 4Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: turbo-local-storage
  claimRef:
    name: redis-data-xl-release-redis-replicas-2
    namespace: turbonomic
  local:
    path: /data/turbonomic/redis-data-xl-release-redis-replicas-2
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.io/hostname
              operator: In
              values:
                - node1
EOF

# Create the persistent volumes
suspendPvExists=$(/usr/local/bin/kubectl get pv  | grep local-pv-redis-data-xl-release-redis-master-0)
if [ -z "${suspendPvExists}" ]
then
  kubectl apply -f /opt/turbonomic/kubernetes/yaml/persistent-volumes/suspend-storage.yaml
fi
