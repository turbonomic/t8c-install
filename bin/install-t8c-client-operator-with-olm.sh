#!/bin/bash
retry_until_successful() {
  local cmd=${1:?"First arg should be command to execute"}
  local timeout=${2:?"Second arg should be timeout in seconds"}

  local start_time=$(date +%s)

  while [[ $(($(date +%s)-start_time)) -lt $timeout ]]
  do
    eval $cmd > /dev/null 2>&1 && return 0
    sleep 1
  done

  return 1
}

echo
echo "###############################################################"
echo "             Installing Turbonomic Client Operator             "
echo "###############################################################"
echo

echo "Install t8c-client-operator in the namespace: $T8C_CLIENT_NAMESPACE"

cat <<EOF | kubectl apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: turbonomic-operators
  namespace: $T8C_CLIENT_NAMESPACE
spec:
  targetNamespaces:
  - $T8C_CLIENT_NAMESPACE 
EOF

cat <<EOF | kubectl apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: t8c-client-operator-catalog
  namespace: olm
spec:
  grpcPodConfig:
    securityContextConfig: restricted
  displayName: Turbonomic Client Operator
  image: icr.io/cpopen/t8c-client-operator-catalog
  publisher: Turbonomic.com
  sourceType: grpc
  updateStrategy:
    registryPoll:
      interval: 60m
EOF

cat <<EOF | kubectl apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: t8c-client-operator
  namespace: $T8C_CLIENT_NAMESPACE 
spec:
  channel: stable
  name: t8c-client-operator
  source: t8c-client-operator-catalog
  sourceNamespace: olm
  installPlanApproval: Automatic
EOF

echo "Waiting for CSV to be created"
retry_until_successful "[[ \$(kubectl get Subscription t8c-client-operator -n $T8C_CLIENT_NAMESPACE -o jsonpath='{.status.currentCSV}') != '' ]]" 120 || {
  echo "CSV did not appear after 120s"
  exit 1
}
csv=$(kubectl get Subscription t8c-client-operator -n $T8C_CLIENT_NAMESPACE -o jsonpath='{.status.currentCSV}')
 
echo "CSV has been created: ${csv}"

echo "Waiting for operator to install"
retry_until_successful "[[ \$(kubectl get csv ${csv} -n $T8C_CLIENT_NAMESPACE -o jsonpath='{.status.phase}') == 'Succeeded' ]]" 300 || {
  echo "Operator did not successfully install after 300s"
  exit 1
}

echo "Operator is ready"
