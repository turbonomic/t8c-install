#!/bin/bash

set -o errexit

version=$(kubectl get xl xl-release -o template={{.spec.global.tag}})

cat << EOF > /opt/turbonomic/kubernetes/operator/deploy/crds/charts_v1alpha1_xl_cr_client.yaml
apiVersion: charts.helm.k8s.io/v1
kind: Xl
metadata:
  name: xl-release
spec:

  global:
    tag: ${version}
    externalSyslog: remote-rsyslog.turbonomic.svc.cluster.local

  properties:
    global:
      enableComponentStatusNotification: "false"
      enableConsulMigration: "false"
      enableConsulRegistration: "false"
      serverAddress: ws://remote-nginx-tunnel:9080/topology-processor/remoteMediation

  # make vcenter probes standalone
  mediation-vcenter:
    env:
      - name: component_type
        value: mediation-vcenter
      - name: instance_id
        valueFrom:
          fieldRef:
            fieldPath: metadata.name
      - name: standalone
        value: "true"
  mediation-vcenterbrowsing:
    env:
      - name: component_type
        value: mediation-vcenterbrowsing
      - name: instance_id
        valueFrom:
          fieldRef:
            fieldPath: metadata.name
      - name: standalone
        value: "true"

  # enable tunnel (Skupper) in client mode
  tunnel:
    enabled: true
    mode: client

  # disable platform components, UI, nginx etc
  platform:
    enabled: false
  control:
    enabled: false
  ui:
    enabled: false
  nginxingress:
    enabled: false
    
  # enable vcenter probe
  vcenter:
    enabled: true

EOF

kubectl apply -f /opt/turbonomic/kubernetes/operator/deploy/crds/charts_v1alpha1_xl_cr_client.yaml
