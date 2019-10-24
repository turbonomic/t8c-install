#!/bin/bash

# SSH keys for kubernetes
source /opt/local/etc/turbo.conf
kubesprayPath="/opt/kubespray"
declare -a node=(${node})
for i in "${node[@]}"
do
  ssh -o "StrictHostKeyChecking=no" turbo@$i "echo -e 'y\n' | ssh-keygen -f $HOME/.ssh/id_rsa -t rsa -b 4096 -N ''"
  scp -o "StrictHostKeyChecking=no" -r ~/.ssh/id_rsa.pub turbo@$i:/tmp/.
  ssh -o "StrictHostKeyChecking=no" turbo@$i "cat /tmp/id_rsa.pub > ~/.ssh/authorized_keys"
  ssh -o "StrictHostKeyChecking=no" turbo@$i rm -rf /tmp/id_rsa.pub
  ssh -o "StrictHostKeyChecking=no" turbo@$i chmod 600 ~/.ssh/authorized_keys
  scp -o "StrictHostKeyChecking=no" -r ~/.ssh/authorized_keys turbo@$i:~/.ssh/authorized_keys
  ssh -o "StrictHostKeyChecking=no" turbo@$i sudo /usr/local/bin/kubeadm reset -f > /dev/null 2>&1
  ssh -o "StrictHostKeyChecking=no" turbo@$i sudo systemctl stop etcd > /dev/null 2>&1
  ssh -o "StrictHostKeyChecking=no" turbo@$i sudo rm -rf /var/lib/etcd/member > /dev/null 2>&1
  ssh -o "StrictHostKeyChecking=no" turbo@$i sudo rm -rf /etc/ssl/etcd/ssl > /dev/null 2>&1
  ssh -o "StrictHostKeyChecking=no" turbo@$i sudo rm -rf /etc/kubernetes/ssl > /dev/null 2>&1
  ssh -o "StrictHostKeyChecking=no" turbo@$i sudo rm -rf /root/.kube > /dev/null 2>&1
  ssh -o "StrictHostKeyChecking=no" turbo@$i sudo rm -rf /opt/turbonomic/.kube > /dev/null 2>&1
done
