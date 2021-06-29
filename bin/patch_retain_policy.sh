#!/bin/bash

# For local storage installations, patch the reclaim policy to be 'Retain' as needed

# Only run if there are unpatched PVs in the environment (with reclaim policy still set to 'Delete')
# No harm is done if some of the PVs are already patched; this will only affect the ones that aren't
if kubectl get pv | awk '{print $7}' |  grep -q "turbo-local-storage"
then
  if kubectl get pv | awk '{print $4}' |  grep -q "Delete"
  then
    kubectl patch pv local-pv-api-certs                   -p '{"spec": {"persistentVolumeReclaimPolicy":"Retain"}}'
    kubectl patch pv local-pv-api                         -p '{"spec": {"persistentVolumeReclaimPolicy":"Retain"}}'
    kubectl patch pv local-pv-auth                        -p '{"spec": {"persistentVolumeReclaimPolicy":"Retain"}}'
    kubectl patch pv local-pv-consul-data                 -p '{"spec": {"persistentVolumeReclaimPolicy":"Retain"}}'
    kubectl patch pv local-pv-kafka-log                   -p '{"spec": {"persistentVolumeReclaimPolicy":"Retain"}}'
    kubectl patch pv local-pv-zookeeper-data              -p '{"spec": {"persistentVolumeReclaimPolicy":"Retain"}}'
    kubectl patch pv local-pv-rsyslog-syslogdata          -p '{"spec": {"persistentVolumeReclaimPolicy":"Retain"}}'
    kubectl patch pv local-pv-rsyslog-auditlogdata        -p '{"spec": {"persistentVolumeReclaimPolicy":"Retain"}}'
    kubectl patch pv local-pv-topology-processor          -p '{"spec": {"persistentVolumeReclaimPolicy":"Retain"}}'
    kubectl patch pv local-pv-prometheus-alertmanager     -p '{"spec": {"persistentVolumeReclaimPolicy":"Retain"}}'
    kubectl patch pv local-pv-prometheus-server           -p '{"spec": {"persistentVolumeReclaimPolicy":"Retain"}}'
    kubectl patch pv local-pv-graphstate-datacloud-graph  -p '{"spec": {"persistentVolumeReclaimPolicy":"Retain"}}'
  fi
fi