#!/bin/bash

set -e

namespace=olm
crdsFile="/opt/turbonomic/kubernetes/yaml/olm/crds.yaml"
olmFile="/opt/turbonomic/kubernetes/yaml/olm/olm.yaml"

if kubectl get deployment olm-operator -n ${namespace} > /dev/null 2>&1; then
    echo "OLM is already installed in ${namespace} namespace. Exiting..."
    exit 0
fi

kubectl create -f "${crdsFile}"
kubectl wait --for=condition=Established -f "${crdsFile}"
kubectl create -f "${olmFile}"

# wait for deployments to be ready
kubectl rollout status -w deployment/olm-operator --namespace="${namespace}"
kubectl rollout status -w deployment/catalog-operator --namespace="${namespace}"

retries=30
until [[ $retries == 0 ]]; do
    new_csv_phase=$(kubectl get csv -n "${namespace}" packageserver -o jsonpath='{.status.phase}' 2>/dev/null || echo "Waiting for CSV to appear")
    if [[ $new_csv_phase != "$csv_phase" ]]; then
        csv_phase=$new_csv_phase
        echo "Package server phase: $csv_phase"
    fi
    if [[ "$new_csv_phase" == "Succeeded" ]]; then
	break
    fi
    sleep 10
    retries=$((retries - 1))
done

if [ $retries == 0 ]; then
    echo "CSV \"packageserver\" failed to reach phase succeeded"
    exit 1
fi

kubectl rollout status -w deployment/packageserver --namespace="${namespace}"
