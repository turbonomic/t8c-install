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

cp /opt/kubespray/roles/download/tasks/download_container.yml /opt/kubespray/roles/download/tasks/download_container.yml.online
sed -i '/- facts/a\
  ignore_errors: yes' /opt/kubespray/roles/download/tasks/download_container.yml
sed -i '/run_once: yes/a\
  ignore_errors: yes' /opt/kubespray/roles/download/tasks/download_container.yml
sed -i '/- group_names/a\
  ignore_errors: yes' /opt/kubespray/roles/download/tasks/download_container.yml
sed -i 's/retries: 4/retries: 1/g' /opt/kubespray/roles/download/tasks/download_container.yml

cp /opt/kubespray/roles/kubernetes/preinstall/tasks/0070-system-packages.yml /opt/kubespray/roles/kubernetes/preinstall/tasks/0070-system-packages.yml.online
sed -i '/- bootstrap-os/a\
  ignore_errors: yes' /opt/kubespray/roles/kubernetes/preinstall/tasks/0070-system-packages.yml
sed -i '/- not is_atomic/a\
  ignore_errors: yes' /opt/kubespray/roles/kubernetes/preinstall/tasks/0070-system-packages.yml
sed -i 's/retries: 4/retries: 1/g' /opt/kubespray/roles/kubernetes/preinstall/tasks/0070-system-packages.yml

cp /opt/kubespray/roles/kubernetes/preinstall/defaults/main.yml /opt/kubespray/roles/kubernetes/preinstall/defaults/main.yml.online
sed -i '/- unzip/a\
ignore_errors: yes' /opt/kubespray/roles/kubernetes/preinstall/defaults/main.yml

cp /opt/kubespray/roles/download/tasks/set_docker_image_facts.yml /opt/kubespray/roles/download/tasks/set_docker_image_facts.yml.online
sed -i 's/pull_args: >-/pull_args: absent#>-/g' /opt/kubespray/roles/download/tasks/set_docker_image_facts.yml

cp /opt/kubespray/roles/network_plugin/calico/tasks/install.yml /opt/kubespray/roles/network_plugin/calico/tasks/install.yml.online
sed -i '/- upgrade/a\
  ignore_errors: yes' /opt/kubespray/roles/network_plugin/calico/tasks/install.yml

cp /opt/kubespray/roles/download/tasks/download_file.yml /opt/kubespray/roles/download/tasks/download_file.yml.online
sed -i '/- group_names/a\
  ignore_errors: yes' /opt/kubespray/roles/download/tasks/download_file.yml

cp /opt/kubespray/roles/download/tasks/sync_container.yml /opt/kubespray/roles/download/tasks/sync_container.yml.online
sed -i 's/retries: 4/retries: 1/g' /opt/kubespray/roles/download/tasks/sync_container.yml

cp /opt/kubespray/roles/download/tasks/download_file.yml /opt/kubespray/roles/download/tasks/download_file.yml.online
sed -i 's/retries: 4/retries: 1/g' /opt/kubespray/roles/download/tasks/download_file.yml

cp /opt/kubespray/roles/kubernetes-apps/helm/tasks/main.yml /opt/kubespray/roles/kubernetes-apps/helm/tasks/main.yml.online 
sed -i '/proxy_env/a\
  ignore_errors: yes' /opt/kubespray/roles/kubernetes-apps/helm/tasks/main.yml

#sudo cp /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.online
#sudo sed -i '/enabled=0/d' /etc/yum.repos.d/CentOS-Base.repo
#sudo sed -i '/gpgkey/i \
#enabled=0' /etc/yum.repos.d/CentOS-Base.repo
#
#sudo cp /etc/yum.repos.d/docker.repo /etc/yum.repos.d/docker.repo.online
#sudo sed -i 's/enabled=1/enabled=0/g' /etc/yum.repos.d/docker.repo
#
#sudo cp /etc/yum.repos.d/epel.repo /etc/yum.repos.d/epel.repo.online
#sudo sed -i 's/enabled=1/enabled=0/g' /etc/yum.repos.d/docker.repo
