#!/bin/bash -x

# t8c-add-node.sh
# Add additional nodes to an existing cluster

# Get the parameters used for kubernetes, gluster, turbo setup
source /opt/local/etc/turbo.conf

# Variables:
kubesprayPath="/opt/kubespray"
inventoryPath="${kubesprayPath}/inventory/turbocluster"

# Get the nodes
declare -a node=(${node})

# Get the current nodes
existingNodes=$(grep access_ip /opt/kubespray/inventory/turbocluster/hosts.yml | awk -F: '{print $2}')

# Add the following node to the cluster
addNode=$(echo ${node[@]} ${existingNodes[@]} | tr ' ' '\n' | sort | uniq -u)

# Add sshkey for the new node
# This is a manual step for the moment
scp -o "StrictHostKeyChecking=no" -r ~/.ssh/authorized_keys turbo@${addNode}:~/.ssh/authorized_keys
ssh -o "StrictHostKeyChecking=no" turbo@${addNode} sudo /usr/local/bin/kubeadm reset -f > /dev/null 2>&1
ssh -o "StrictHostKeyChecking=no" turbo@${addNode} sudo systemctl stop etcd > /dev/null 2>&1
ssh -o "StrictHostKeyChecking=no" turbo@${addNode} sudo rm -rf /var/lib/etcd/member > /dev/null 2>&1
ssh -o "StrictHostKeyChecking=no" turbo@${addNode} sudo rm -rf /etc/ssl/etcd/ssl > /dev/null 2>&1
ssh -o "StrictHostKeyChecking=no" turbo@${addNode} sudo rm -rf /etc/kubernetes/ssl > /dev/null 2>&1
ssh -o "StrictHostKeyChecking=no" turbo@${addNode} sudo rm -rf /root/.kube > /dev/null 2>&1
ssh -o "StrictHostKeyChecking=no" turbo@${addNode} sudo rm -rf /opt/turbonomic/.kube > /dev/null 2>&1

# Create new inventory file
# Run kubespray
pushd ${kubesprayPath} > /dev/null
# Clear old host.ini file
cp -rfp ${inventoryPath}/hosts.yml ${inventoryPath}/hosts.yml.orig
CONFIG_FILE=inventory/turbocluster/hosts.yml python3.6 contrib/inventory_builder/inventory.py ${node[@]}

# Run ansible kubespray install
/usr/bin/ansible-playbook -i inventory/turbocluster/hosts.yml -b --become-user=root scale.yml
# Check on ansible status and exit out if there are any failures.
ansibleStatus=$?

if [ $ansibleStatus -eq 0 ]
then
  echo "Added ${addNode} to the cluster"
fi

