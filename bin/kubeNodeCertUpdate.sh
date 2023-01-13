#!/bin/bash

#Script for updating Kubernetes certificates
echo " "
RED=`tput setaf 1`
WHITE=`tput setaf 7`
GREEN=`tput setaf 2`
BLUE=`tput setaf 4`
NC=`tput sgr0` # No Color
# Run this as the root user
if [[ $(/usr/bin/id -u) -ne 0 ]]
then
  echo "Not running as root, please become the root user"
  exit
fi

echo "*************************************************************"
echo "*This script will restart all Kubernetes and Turbonomic pods*"
echo "*This will take down the Turbonomic instance                *" 
echo "*************************************************************"
read -p "Are you sure you want to continue (y/n)?" CONT
if [[ "$CONT" =~ ^([yY][eE][sS]|[yY])$ ]]
then
  echo "Continuing..."
else
  echo "y not pressed, exiting"
  exit 0
fi

echo "Starting to renew Kubernetes certificates..."
cd /etc/kubernetes/;  ln -s ssl pki;
# Check kubernetes version
kubeVersion=$(/usr/local/bin/kubectl version | awk '{print $4}' | head -1 | awk -F: '{print $2}' | sed 's/"//g' | sed 's/,//g')
if [ $kubeVersion -ge 20 ]
then
  /usr/local/bin/kubeadm certs renew apiserver 2>/dev/null
  /usr/local/bin/kubeadm certs renew apiserver-kubelet-client 2>/dev/null
  /usr/local/bin/kubeadm certs renew front-proxy-client 2>/dev/null
  echo "Certificates renewed...please review above messages for any errors, but warnings are expected"
  echo " "
  echo "Updating Kubernetes configuration with new certificates..."
  cd /etc/kubernetes
  /usr/local/bin/kubeadm init phase kubeconfig admin 2>/dev/null
  /usr/local/bin/kubeadm init phase kubeconfig controller-manager 2>/dev/null
  /usr/local/bin/kubeadm init phase kubeconfig kubelet 2>/dev/null
  /usr/local/bin/kubeadm init phase kubeconfig scheduler 2>/dev/null
  echo "Kubernetes configuration update completed"
  echo " "
else
  /usr/local/bin/kubeadm alpha certs renew apiserver 2>/dev/null
  /usr/local/bin/kubeadm alpha certs renew apiserver-kubelet-client 2>/dev/null
  /usr/local/bin/kubeadm alpha certs renew front-proxy-client 2>/dev/null
  echo "Certificates renewed...please review above messages for any errors, but warnings are expected"
  echo " "
  echo "Updating Kubernetes configuration with new certificates..."
  cd /etc/kubernetes
  /usr/local/bin/kubeadm alpha kubeconfig user --org system:masters --client-name kubernetes-admin  > admin.conf 2>/dev/null
  /usr/local/bin/kubeadm alpha kubeconfig user --client-name system:kube-controller-manager > controller-manager.conf 2>/dev/null
  /usr/local/bin/kubeadm alpha kubeconfig user --org system:nodes --client-name system:node:$(hostname) > kubelet.conf 2>/dev/null
  /usr/local/bin/kubeadm alpha kubeconfig user --client-name system:kube-scheduler > scheduler.conf 2>/dev/null
  echo "Kubernetes configuration update completed"
  echo " "
fi

echo "Restarting Kubernetes kubelet service..."
systemctl restart kubelet
CSTATUS="$(systemctl is-active kubelet)"
if [ "${CSTATUS}" = "active" ]; then
    echo "kubelet service is running now...continuing"
else 
    echo "kubelet service is not running....please check"  
fi

echo " "
echo "Backing up and updating Kubernetes cluster configuration..."
cp /root/.kube/config /root/.kube/config.old
cp /etc/kubernetes/admin.conf /root/.kube/config

cp /opt/turbonomic/.kube/config /opt/turbonomic/.kube/config.old
cp /etc/kubernetes/admin.conf /opt/turbonomic/.kube/config
chown turbo.turbo /opt/turbonomic/.kube/config
sed -i '/user: kubernetes-admin/a \    namespace: turbonomic' /opt/turbonomic/.kube/config
echo "Backup and Kubernetes configuration cluster configuration completed"
echo " "
echo "Checking new expiry date of Kubernetes certificates..."
echo " "
echo "Checking apiserver-kubelet-client.crt file expiry date..."
openssl x509 -noout -enddate -in /etc/kubernetes/ssl/apiserver-kubelet-client.crt
echo " "
echo "Checking apiserver.crt file expiry date..."
openssl x509 -noout -enddate -in /etc/kubernetes/ssl/apiserver.crt
echo " "
echo "Checking front-proxy-client.crt file expiry date..."
openssl x509 -noout -enddate -in /etc/kubernetes/ssl/front-proxy-client.crt
echo " "
echo "All 3 certificates above should have their new expiry date set as a year from now"
echo "If for some reason the certificates are not updated correctly **please contact Turbonomic support**"
echo " "
echo "Please check that all pods are running and ready"
echo "As they were all restarted as part of the update and will take some time before they are all ready"
echo " "
echo "**Kubernetes certificates renewal completed now**"
