#!/bin/bash

# Allow kubernetes to do an offline update with no internet access.

source /opt/local/etc/turbo.conf

sudo /usr/local/bin/kubeadm reset -f > /dev/null 2>&1
sudo systemctl stop etcd > /dev/null 2>&1
sudo rm -rf /var/lib/etcd/member > /dev/null 2>&1
sudo rm -rf /etc/ssl/etcd/ssl > /dev/null 2>&1
sudo rm -rf /etc/kubernetes/ssl > /dev/null 2>&1
pushd /etc/; for i in `sudo grep -lr 10.0.2.15 *`; do sudo sed -i "s/10.0.2.15/${node}/g" $i; done; popd
sudo rm -rf /root/.kube > /dev/null 2>&1
sudo rm -rf /opt/turbonomic/.kube > /dev/null 2>&1

FILE_007=/opt/kubespray/roles/kubernetes/preinstall/tasks/0070-system-packages.yml
ONLINE_FILE_007=/opt/kubespray/roles/kubernetes/preinstall/tasks/0070-system-packages.yml.online
OFFLINE_FILE_007=/opt/kubespray/roles/kubernetes/preinstall/tasks/0070-system-packages.yml.offline
if [ ! -f "${ONLINE_FILE_007}" ]
then
    cp ${FILE_007} ${ONLINE_FILE_007}
    cp ${OFFLINE_FILE_007} ${FILE_007}
fi

CONT_MAIN_FILE="/opt/kubespray/roles/container-engine/docker/tasks/main.yml"
CONT_MAIN_ONLINE_FILE="/opt/kubespray/roles/container-engine/docker/tasks/main.yml.online"
CONT_MAIN_OFFLINE_FILE="/opt/kubespray/roles/container-engine/docker/tasks/main.yml.offline"
if [ ! -f "${CONT_MAIN_ONLINE_FILE}" ]
then
    cp ${CONT_MAIN_FILE} ${CONT_MAIN_ONLINE_FILE}
    cp ${CONT_MAIN_OFFLINE_FILE} ${CONT_MAIN_FILE}
fi
