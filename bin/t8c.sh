#!/bin/bash

# Script: t8s.sh
# Author: Billy O'Connell
# Purpose: Setup a kubernetes environment with T8s xl components
# Tools:  Kubespray, Heketi, GlusterFs

# Set the ip address for a single node setup.  Multinode should have the
# ip values set manually in /opt/local/etc/turbo.conf
singleNodeIp=$(ip address show eth0 | egrep inet | egrep -v inet6 | awk '{print $2}' | awk -F/ '{print$1}')
sed -i "s/10.0.2.15/${singleNodeIp}/g" /opt/local/etc/turbo.conf

# Check /etc/resolv.conf
if [[ ! -f /etc/resolv.conf || ! -s /etc/resolv.conf ]]
then
  echo ""
  echo "exiting......"
  echo "Please check there are valid nameservers in the /etc/resolv.conf"
  echo ""
  exit 0
fi

# Get the parameters used for kubernetes, gluster, turbo setup
source /opt/local/etc/turbo.conf

# Update the yaml files to run offline
/opt/local/bin/offlineUpdate.sh

# Create the ssh keys to run with
if [ ! -f ~/.ssh/authorized_keys ]
then
  ssh-keygen -f ~/.ssh/id_rsa -t rsa -N ''
  cat ~/.ssh/id_rsa.pub > ~/.ssh/authorized_keys
  chmod 600 ~/.ssh/authorized_keys
fi

# Functions
usage()
{
        echo "Use: `basename $0`"
        exit -1
}

pause()
{
    key=""
    echo
    echo -n "Configuration confirmation, press any key to continue with the install"
    stty -icanon
    key=`dd count=1 2>/dev/null`
    stty icanon
}

# Variables:
kubesprayPath="/opt/kubespray"
inventoryPath="${kubesprayPath}/inventory/turbocluster"
glusterStorage="/opt/gluster-kubernetes"
glusterStorageJson="${glusterStorage}/deploy/topology.json"
declare -a node=(${node})

# Build the node array to pass into kubespray
for i in "${node[@]}"
do
  export node${#node[@]}=${i}
done
# get length of an array
tLen=${#node[@]}

# Check that the proper amount of ip addresses were used.
if (( ${tLen} > ${nodeAnswer} ))
then
  echo "===================================================================================="
  echo "The number of ip addresses given is greater than the total amount of nodes provided."
  echo "===================================================================================="
  exit
fi
if (( ${tLen} < ${nodeAnswer} ))
then
  echo "====================================================================="
  echo "The number of ip addresses given does not meet the node requirements."
  echo "====================================================================="
  exit
fi


# List the master nodes:
echo
echo
echo "Master Node(s)"
echo "++++++++++++"
if (( ${tLen} > 1 ))
then
  for ((i=0,j=1; i<2; i++,j++));
  do
    echo node${j} ${node[i]}
  done
  echo
  echo
else
  echo node1 ${node[0]}
  echo
  echo
fi
echo "++++++++++++"
echo

# List the kubelet nodes
echo "Worker Nodes"
echo "++++++++++++"
for ((i=0,j=1; i<${#node[*]}; i++,j++));
do
    echo node${j} ${node[i]}
done
echo "++++++++++++"
echo

# Run kubespray
pushd ${kubesprayPath} > /dev/null

# Clear old host.ini file
rm -rf ${kubesprayPath}/inventory/turbocluster
cp -rfp ${kubesprayPath}/inventory/sample ${inventoryPath}
CONFIG_FILE=inventory/turbocluster/hosts.yml python3.6 contrib/inventory_builder/inventory.py ${node[@]}

# Adjust for relaxing the number of dns server allowed
cp ${kubesprayPath}/roles/container-engine/docker/defaults/main.yml ${kubesprayPath}/roles/container-engine/docker/defaults/main.yml.orig
dns_strict="docker_dns_servers_strict: true"
dns_not_strick="docker_dns_servers_strict: false"
dns_not_strick_group="#docker_dns_servers_strict: false"
helm_enabled="helm_enabled: false"
helm_enabled_group="helm_enabled: true"
sed -i "s/${dns_strict}/${dns_not_strick}/g" ${kubesprayPath}/roles/container-engine/docker/defaults/main.yml
sed -i "s/${dns_strict}/${dns_not_strick_group}/g" ${inventoryPath}/group_vars/all/all.yml
sed -i "s/${helm_enabled}/${helm_enabled_group}/g" ${inventoryPath}/group_vars/k8s-cluster/addons.yml

# Run ansible kubespray install
/usr/bin/ansible-playbook -i inventory/turbocluster/hosts.yml -b --become-user=root cluster.yml
# Check on ansible status and exit out if there are any failures.
ansibleStatus=$?
# Reset the kubespray yaml back to the original source
pushd /opt/kubespray/; for i in $(find . -name *.online); do j=$(echo $i | sed 's/.online//'); cp $j $i;done;popd
if [ "X${ansibleStatus}" == "X0" ]
then
  echo ""
  echo ""
  echo "######################################################################"
  echo "                   Kubespray Completed successfully                   "
  echo "######################################################################"
  echo ""
else
  echo ""
  echo ""
  echo "######################################################################"
  echo "                   Kubespray Failed:                                  "
  echo "       Please check the /opt/local/etc/turbo.conf settings            "
  echo "######################################################################"
  echo ""
  exit 0
fi
popd > /dev/null

# Setup storage with heketi/gluster
# These need to be done on each node
if [ ${nodeAnswer} = 1 ]
then
   sudo /usr/sbin/modprobe dm_thin_pool
   sudo /usr/sbin/modprobe dm_snapshot
   sudo /usr/sbin/setsebool -P virt_sandbox_use_fusefs on
else
for ((i=0,j=1; i<(${#node[*]}-1); i++,j++));
do
   ssh turbo@${node[$i]} sudo /usr/sbin/modprobe dm_thin_pool
   ssh turbo@${node[$i]} sudo /usr/sbin/modprobe dm_snapshot
   ssh turbo@${node[$i]} sudo /usr/sbin/setsebool -P virt_sandbox_use_fusefs on
done
fi

# Setup Secure kubernetes api
echo "export KUBECONFIG=/opt/turbonomic/.kube/config" >> /opt/turbonomic/.bashrc
if [ ! -d /opt/turbonomic/.kube/ ]
then 
  mkdir /opt/turbonomic/.kube/
fi

sudo cp /etc/kubernetes/admin.conf /opt/turbonomic/.kube/config
sudo chown $(id -u):$(id -g) /opt/turbonomic/.kube/config
export KUBECONFIG=/opt/turbonomic/.kube/config

# For new installs, make sure disk is clean
vgroup=$(sudo /usr/sbin/vgdisplay | grep "VG Name" | awk '{print $3}')
for i in ${vgroup[@]}
do
  if [ $i != turbo ]
  then
    sudo /usr/sbin/vgremove -f ${i}
  fi
done
sudo /usr/sbin/wipefs -a /dev/sdb

# Setup GlusterFS Native Storage Service for Kubernetes
if (( ${tLen} > 1 ))
then
  for ((i=0,j=1; i<(${#node[*]}-1); i++,j++));
  do
    cat << EOF >> /tmp/topology.json
        {
          "node": {
            "hostnames": {
              "manage": [
                "node${j}"
              ],
              "storage": [
                "${node[i]}"
              ]
            },
            "zone": 1
          },
          "devices": [
            "${device}"
          ]
        },
EOF
  done
fi
# For the last node, leave out the comma for valid json file
lastNodeElement="${node[-1]}"
cat << EOF >> /tmp/topology.json
        {
          "node": {
            "hostnames": {
              "manage": [
                "node${tLen}"
              ],
              "storage": [
                "${lastNodeElement}"
              ]
            },
            "zone": 1
          },
          "devices": [
            "${device}"
          ]
        }
EOF

cp "${glusterStorageJson}.template" "${glusterStorageJson}"
sed -i '/nodes/r /tmp/topology.json' "${glusterStorageJson}"
rm -rf /tmp/topology.json

# Run the heketi/gluster setup
pushd ${glusterStorage}/deploy > /dev/null
if (( ${tLen} >= 1 ))
then
  # This is for a single node setup.
  /opt/gluster-kubernetes/deploy/gk-deploy --single-node -gyv
  heketiStatus=$?
  if [ "X${heketiStatus}" == "X0" ]
  then
    echo ""
    echo ""
    echo "######################################################################"
    echo "             Gluster-Heketi Completed Successfully                    "
    echo "######################################################################"
    echo ""
    echo ""
  else
    echo ""
    echo ""
    echo "######################################################################"
    echo "                 Gluster-Heketi Failed                                "
    echo "       Please check the /opt/local/etc/turbo.conf settings            "
    echo "######################################################################"
    echo ""
    echo ""
    exit 0
  fi
else
  /opt/gluster-kubernetes/deploy/gk-deploy -gyv
  heketiStatus=$?
  if [ "X${heketiStatus}" == "X0" ]
  then
    echo ""
    echo ""
    echo "######################################################################"
    echo "             Gluster-Heketi  Completed successfully                   "
    echo "######################################################################"
    echo ""
    echo ""
  else
    echo ""
    echo ""
    echo "######################################################################"
    echo "                 Gluster-Heketi Failed                                "
    echo "       Please check the /opt/local/etc/turbo.conf settings            "
    echo "######################################################################"
    echo ""
    echo ""
    exit 0
  fi
fi
popd > /dev/null

# Start Turbonomic installation
if [ "x${node[0]}" != "x10.0.2.15" ]
then
  # Install pre-turbonomic environmental requirementes
  echo
  echo
  echo "######################################################################"
  echo "                 Prepare Turbonomic Appliance                         "
  echo "######################################################################"
  /opt/local/bin/turboEnv.sh
  envStatus=$?
  if [ "X${envStatus}" == "X0" ]
  then
    echo ""
    echo "==========================================="
    echo "Turbonomic Environment Applied Successfully"
    echo "==========================================="
    echo ""
  else
    echo ""
    echo "============================="
    echo "Turbonomic Environment Failed"
    echo "============================="
    echo ""
    exit 0
  fi
  echo "######################################################################"
  echo "                 Helm Chart Installation                              "
  echo "######################################################################"
   /usr/local/bin/helm init --client-only --skip-refresh
   cp /opt/turbonomic/kubernetes/yaml/offline/offline-repository.yaml /opt/turbonomic/.helm/repository/repositories.yaml
   /usr/local/bin/helm init
   /usr/local/bin/kubectl apply -f /opt/turbonomic/kubernetes/yaml/helm/rbac_service_account.yaml
   /usr/local/bin/helm dependency build /opt/turbonomic/kubernetes/helm/xl
   /usr/local/bin/helm init --service-account tiller --upgrade
   /usr/local/bin/helm install /opt/turbonomic/kubernetes/helm/xl --name xl-release --namespace ${namespace} \
                                                                    --set-string global.tag=${turboVersion} \
                                                                    --set-string global.externalIP=${node} \
                                                                    --set vcenter.enabled=true \
                                                                    --set hyperv.enabled=true \
                                                                    --set actionscript.enabled=true \
                                                                    --set netapp.enabled=true \
                                                                    --set pure.enabled=true \
                                                                    --set oneview.enabled=true \
                                                                    --set ucs.enabled=true \
                                                                    --set hpe3par.enabled=true \
                                                                    --set vmax.enabled=true \
                                                                    --set vmm.enabled=true \
                                                                    --set appdynamics.enabled=true
fi
