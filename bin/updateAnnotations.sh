#!/bin/bash

# Namespace.. turbonomic by default
nameSpace=turbonomic
if [ $# -eq 1 ]
  then
    nameSpace=$1
fi

# Need to check if the helm release is uid based (xl-release-XXX instead of xl-release)
# and if it is, can convert it before or after the upgrade of the operator
helmRelease=$(kubectl get xls -o yaml -n ${nameSpace} |grep name:|head -1 | awk '{print $2}')
secretName=$(kubectl get pvc -o yaml -n ${nameSpace} | grep "app.kubernetes.io/instance" | uniq | awk '{print $2}')
# Exit if the uid based release has already been converted
if [ "$helmRelease" = "$secretName" ]; then
  echo "helm release has already been converted, nothing to do. Exiting."
  exit 0
fi

echo "-----------------------"
echo "Scale down the Operator"
echo "-----------------------"
kubectl scale deployment --replicas=0 t8c-operator -n ${nameSpace}
operatorCount=$(kubectl get pod -n ${nameSpace} | grep t8c-operator | wc -l)
while [ ${operatorCount} -gt 0 ]
do
 operatorCount=$(kubectl get pod -n ${nameSpace} | grep t8c-operator | wc -l)
done
echo

# Update pvcs
cat << EOF > /tmp/pvc-patch.yml
metadata:
  labels:
    app.kubernetes.io/instance: ${helmRelease}
EOF

echo "----------------------"
echo "pvc update annotations"
echo "----------------------"
for pvc in $(kubectl get pvc -n ${nameSpace} | awk '{print $1}' | egrep -v NAME)
do
  kubectl patch pvc ${pvc} -n ${nameSpace} --type merge --patch "$(cat /tmp/pvc-patch.yml)"
done
echo


# Update deployments
cat << EOF > /tmp/deployment-patch.yml
metadata:
  labels:
    app.kubernetes.io/instance: ${helmRelease}
spec:
  selector:
    matchLabels:
      app.kubernetes.io/instance: ${helmRelease}
  template:
    metadata:
      labels:
        app.kubernetes.io/instance: ${helmRelease}
EOF

cat << EOF > /tmp/3rdParty-deployment-patch.yml
metadata:
  labels:
    app.kubernetes.io/instance: ${helmRelease}
    release: ${helmRelease}
spec:
  selector:
    matchLabels:
      app.kubernetes.io/instance: ${helmRelease}
      release: ${helmRelease}
  template:
    metadata:
      labels:
        app.kubernetes.io/instance: ${helmRelease}
        release: ${helmRelease}
EOF

echo "------------------"
echo "deployment updates"
echo "------------------"
for deployment in $(kubectl get deployment -n ${nameSpace} | awk '{print $1}' | egrep -v NAME)
do
  if [[ X${deployment} = Xgrafana ]] || [[ X${deployment} =~ Xprometheus.* ]]
  then
    kubectl patch deployment ${deployment} -n ${nameSpace} --type merge --patch "$(cat /tmp/3rdParty-deployment-patch.yml)"
  else
    kubectl patch deployment ${deployment} -n ${nameSpace} --type merge --patch "$(cat /tmp/deployment-patch.yml)"
  fi
done
echo

# Update Daemonset
cat << EOF > /tmp/daemonset-patch.yml
metadata:
  labels:
    app.kubernetes.io/instance: ${helmRelease}
    release: ${helmRelease}
spec:
  selector:
    matchLabels:
      app.kubernetes.io/instance: ${helmRelease}
      release: ${helmRelease}
  template:
    metadata:
      labels:
        app.kubernetes.io/instance: ${helmRelease}
        release: ${helmRelease}
EOF

echo "-----------------"
echo "daemonset updates"
echo "-----------------"
for daemonset in $(kubectl get daemonset -n ${nameSpace} | awk '{print $1}' | egrep -v NAME)
do
  kubectl patch daemonset ${daemonset} -n ${nameSpace} --type merge --patch "$(cat /tmp/daemonset-patch.yml)"
done
echo

# Update ConfigMap
cat << EOF > /tmp/cm-patch.yml
  metadata:
    labels:
      app.kubernetes.io/instance: ${helmRelease}
EOF

configMap=$(kubectl get cm -n ${nameSpace} | grep global | awk '{print $1}')

echo "-----------------"
echo "configmap updates"
echo "-----------------"
kubectl patch cm ${configMap} -n ${nameSpace} --type merge --patch "$(cat /tmp/cm-patch.yml)"
echo

# Update secrets
echo "---------------"
echo "secrets updates"
echo "---------------"
kubectl get secrets -n ${nameSpace} $(kubectl get secrets -n ${nameSpace} | grep ${helmRelease} | awk '{print $1}' | tail -1) -o yaml > /tmp/helm-release.yml
sed -i "s/${helmRelease}-[0-9A-Za-z]*/${helmRelease}/g" /tmp/helm-release.yml
kubectl get secrets -n ${nameSpace} $(kubectl get secrets -n ${nameSpace} | grep ${helmRelease} | awk '{print $1}' | tail -1) -o jsonpath={.data.release} | base64 -d | base64 -d |gunzip > /tmp/xl-release
sed -i "s/${helmRelease}-[0-9A-Za-z]*/${helmRelease}/g" /tmp/xl-release
gzip -c /tmp/xl-release | base64 -w 0 | base64 -w 0 > /tmp/xl-updated-release
cat << EOF > /tmp/script.sed
/release:.*/ {
  r  /tmp/xl-updated-release
  d
}
EOF
sed -i "s/release:.*/release:/g" /tmp/helm-release.yml
sed -i '/kind:/i \
' /tmp/helm-release.yml
sed -i -f /tmp/script.sed /tmp/helm-release.yml
sed -i '/^data:/a \
  release:' /tmp/helm-release.yml
sed -i '/^  release/N;s/\n/ /' /tmp/helm-release.yml

# Delete the latest secret and apply the updated one
for secrets in $(kubectl get secrets -n ${nameSpace} | grep ${helmRelease} | awk '{print $1}')
do
  kubectl delete secrets -n ${nameSpace} ${secrets}
done

# Apply the new release
kubectl apply -f /tmp/helm-release.yml -n ${nameSpace}
echo

# Delete existing replica sets
kubectl delete rs --all -n ${nameSpace}
kubectl delete daemonset --all -n ${nameSpace}

# Scale the operator back up
echo "---------------------"
echo "Scale up the Operator"
echo "---------------------"
kubectl scale deployment --replicas=1 t8c-operator -n ${nameSpace}
