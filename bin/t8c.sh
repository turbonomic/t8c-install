#!/bin/bash

# Script: t8s.sh
# Author: Billy O'Connell
# Purpose: Setup a kubernetes environment with T8s xl components
# Tools:  Kubespray, Heketi, GlusterFs

# Exit out if running as root or sudo

# Variable to use if a non-turbonomic deployment
while getopts b:h: flag
do
    case "${flag}" in
        h) hostName=${OPTARG};;
    esac
done
serviceAccountFile="/opt/turbonomic/kubernetes/operator/deploy/service_account.yaml"
roleFile="/opt/turbonomic/kubernetes/operator/deploy/cluster_role.yaml"
roleBindingFile="/opt/turbonomic/kubernetes/operator/deploy/cluster_role_binding.yaml"
crdsFile="/opt/turbonomic/kubernetes/operator/deploy/crds/charts_v1alpha1_xl_crd.yaml"
operatorFile="/opt/turbonomic/kubernetes/operator/deploy/operator.yaml"
chartsFile="/opt/turbonomic/kubernetes/operator/deploy/crds/charts_v1alpha1_xl_cr.yaml"
localStorageDataDirectory="/data/turbonomic/"
yamlBasePath="/opt/turbonomic/kubernetes/yaml"
glusterDeployPath="/opt/gluster-kubernetes/deploy"

# Set the ip address for a single node setup.  Multinode should have the
# ip values set manually in /opt/local/etc/turbo.conf
singleNodeIp=$(ip address show eth0 | egrep inet | egrep -v inet6 | awk '{print $2}' | awk -F/ '{print$1}')
sed -i "s/10.0.2.15/${singleNodeIp}/g" /opt/local/etc/turbo.conf
sed -i "s/10.0.2.15/${singleNodeIp}/g" /opt/local/etc/server.properties
for i in $(ls /opt/turbonomic/kubernetes/operator/deploy/crds/)
do
  sed -i "s/10.0.2.15/${singleNodeIp}/g" /opt/turbonomic/kubernetes/operator/deploy/crds/$i
done

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

if grep -q "$localStorageDataDirectory" /etc/fstab
then
  echo ""
  echo "Detected existing installation..."
  echo "exiting......"
  echo "Please do not re-run t8c.sh on an existing install."
  echo ""
  exit 0
fi

# Update the yaml files to run offline
#/opt/local/bin/cleanKube.sh

# Create the ssh keys to run with
if [ ! -f ~/.ssh/id_rsa.pub ]
then
  ssh-keygen -f ~/.ssh/id_rsa -t rsa -N ''
  cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
  # Make sure authorized_keys has the appropriate permissions, otherwise sshd does not allow
  # passwordless ssh.
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


# Setup the node keys for communication
if (( ${tLen} > 1 ))
then
  echo "Setup nodes to communicate using keys"
  /opt/local/bin/multi-node-keygen.sh
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
sed -i "s/${dns_strict}/${dns_not_strick}/g" ${kubesprayPath}/roles/container-engine/docker/defaults/main.yml
sed -i "s/${dns_strict}/${dns_not_strick_group}/g" ${inventoryPath}/group_vars/all/all.yml

# Check if the /tmp/releases directory exists, and kubeadm/calicoctl are available for the offline install
if [[ -d "/tmp/releases" ]]
then
    # Check if the /tmp/releases/kubeadm file exists
    if [[ ! -f "/tmp/releases/kubeadm" ]]; then
      sudo cp /usr/local/bin/{kubeadm,calicoctl} /tmp/releases/.
    fi
else
    sudo mkdir /tmp/releases
    sudo cp /usr/local/bin/{kubeadm,calicoctl} /tmp/releases/.
fi

# Set the hostname if it is passed in
if [ ! -z "${hostName}" ]
then
  sed -i "s/node1/${hostName}/g" ${inventoryPath}/hosts.yml
  sed -i "s/node1/${hostName}/g" ${glusterDeployPath}/topology.json
  sed -i "s/node1/${hostName}/g" ${yamlBasePath}/persistent-volumes/local-storage-pv.yaml
fi

# Run ansible kubespray install
/usr/local/bin/ansible-playbook --flush-cache -i inventory/turbocluster/hosts.yml -b --become-user=root cluster.yml
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
  echo "                Please Contact Support                                "
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

# OM-81849: Fix vulnerability found associated with some Turbo Services running on the CentOS
kubeApiServerPod=$(kubectl get pod -n kube-system  | grep apiserver | awk '{print $1}')
grep "tlsCipherSuites" /var/lib/kubelet/config.yaml
result=$?
if [ ${result} -ne 0 ]
then
  echo "tlsCipherSuites: [TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,TLS_RSA_WITH_AES_256_GCM_SHA384,TLS_RSA_WITH_AES_128_GCM_SHA256]" >> /var/lib/kubelet/config.yaml
fi
grep "\-\-tls\-cipher" /etc/kubernetes/manifests/kube-apiserver.yaml
result=$?
if [ ${result} -ne 0 ]
then
  sed -i "/apiserver.key/a\
\    \- --tls-cipher-suites=TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,TLS_RSA_WITH_AES_256_GCM_SHA384,TLS_RSA_WITH_AES_128_GCM_SHA256" /etc/kubernetes/manifests/kube-apiserver.yaml
fi
kubectl delete pod -n kube-system ${kubeApiServerPod}
grep "OM-81849" /etc/rc.local
result=$?
if [ ${result} -ne 0 ]
then
  cat << EOF >> /etc/rc.local
# OM-81849: Fix vulnerability found associated with some Turbo Services running on the CentOS
iptables -A INPUT -p tcp --destination-port 10250 -j DROP
iptables -A INPUT -p tcp --destination-port 6443 -j DROP
iptables -A INPUT -p tcp --destination-port 3306 -j DROP
EOF
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
# Wipe the pod storage partition
sudo /usr/sbin/wipefs -a /dev/sdb

# Check for local or shared storage
# Case-insensitive comparsion (due to the use of ',,')
if [ X${storage,,} = "Xlocal" ]
then
  # Perform the initial setup for local storage
  # Local storage should be used when shared storage (Gluster) is not desired.
  # This should *only* be run once, before the installation of the Kubernetes environment (i.e., within t8c.sh).
  sudo umount ${localStorageDataDirectory}
  sudo /usr/sbin/wipefs -a /dev/sdb

  # Format the partition and mount it in the desired data directory
  disk1=$(echo ${device} | awk -F/ '{print $3}')
  sudo mkfs.xfs -f ${device}
  sudo mkdir -p $localStorageDataDirectory
  sudo chown -R turbo.turbo $localStorageDataDirectory
  if ! grep -q "$localStorageDataDirectory" /etc/fstab
  then
    echo "${device} $localStorageDataDirectory                     xfs     defaults        0 0" | sudo tee --append /etc/fstab
  fi
  sudo mount -a
  # This check needs to be better. But no time right now
  localStatus=$?
  if [ "X${localStatus}" == "X0" ]
  then
    # Create the subdirectories for each PV and fix the ownership/permissions
    # These directories are needed to enable local storage class in Kubernetes.
    sudo mkdir -p ${localStorageDataDirectory}api-certs
    sudo mkdir -p ${localStorageDataDirectory}api
    sudo mkdir -p ${localStorageDataDirectory}auth
    sudo mkdir -p ${localStorageDataDirectory}consul-data
    sudo mkdir -p ${localStorageDataDirectory}kafka-log
    sudo mkdir -p ${localStorageDataDirectory}zookeeper-data
    sudo mkdir -p ${localStorageDataDirectory}rsyslog-syslogdata
    sudo mkdir -p ${localStorageDataDirectory}rsyslog-auditlogdata
    sudo mkdir -p ${localStorageDataDirectory}rsyslog-auditlogdata
    sudo mkdir -p ${localStorageDataDirectory}topology-processor
    sudo mkdir -p ${localStorageDataDirectory}prometheus-alertmanager
    sudo mkdir -p ${localStorageDataDirectory}prometheus-server
    sudo mkdir -p ${localStorageDataDirectory}graphstate-datacloud-graph
    sudo mkdir -p ${localStorageDataDirectory}data-postgres
    sudo mkdir -p ${localStorageDataDirectory}redis-data-redis-master-0
    sudo chown -R turbo.turbo $localStorageDataDirectory
    sudo chmod -R 777 $localStorageDataDirectory
    echo ""
    echo ""
    echo "######################################################################"
    echo "               Local Storage  Completed Successfully                  "
    echo "######################################################################"
    echo ""
    echo ""
  else
    echo ""
    echo ""
    echo "######################################################################"
    echo "                 Local Storage Failed                                 "
    echo "                Please Contact Support                                "
    echo "######################################################################"
    echo ""
    echo ""
   exit 0
  fi
elif [ X${storage,,} = "Xshared" ]
then
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

  # This is commented out to use a specific private ip to set the storage ep
  # If a multi-node env is required, this will have to be revisited.
  #cp "${glusterStorageJson}.template" "${glusterStorageJson}"
  #sed -i '/nodes/r /tmp/topology.json' "${glusterStorageJson}"
  #rm -rf /tmp/topology.json

  # Set the heketi admin key (used also in the turboEnv.sh script
  export ADMIN_KEY=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)

  # Run the heketi/gluster setup
  pushd ${glusterStorage}/deploy > /dev/null
  if (( ${tLen} >= 1 ))
  then
    # This is for a single node setup.
    /opt/gluster-kubernetes/deploy/gk-deploy --single-node -gyv --admin-key ${ADMIN_KEY}
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
      echo "                 Please Contact Support                               "
      echo "######################################################################"
      echo ""
      echo ""
      exit 0
    fi
  else
    /opt/gluster-kubernetes/deploy/gk-deploy -gyv --admin-key ${ADMIN_KEY}
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
      echo "                 Please Contact Support                               "
      echo "######################################################################"
      echo ""
      echo ""
      exit 0
    fi
  fi
  popd > /dev/null
else
  echo "Could not detect the desired storage setting. Please set the 'storage' property in turbo.conf to either 'shared' or 'local'."
fi

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
    echo "Please Contact Support       "
    echo "============================="
    echo ""
    exit 0
  fi
  # Set up Auth encryption keys before bringing up XL components (if so configured)
  # Check to see if kubernetes auth secrets are being used.  If so, pre-generate the keys and
  # load them into secrets.
  # This must be done after installing Kubernetes, but before running the operator.
  egrep "enableExternalSecrets" ${chartsFile}
  enableExternalSecrets=$(echo $?)

  if [ X${enableExternalSecrets} = X0 ]
  then
    echo "Auth is configured to access Kubernetes secrets, configuring..."
    /opt/local/bin/configure_auth_secrets.sh
  else
    echo "Auth is configured to run with persistent volumes, skipping secrets configuration."
  fi
  echo "######################################################################"
  echo "                   Operator Installation                              "
  echo "######################################################################"
  # See if the operator has an external ip
  sed -i "s/tag:.*/tag: ${turboVersion}/g" ${chartsFile}
  grep -r "externalIP:" ${chartsFile}
  result="$?"
  if [ $result -ne 0 ]; then
    sed -i "/tag:/a\
\    externalIP: ${node}\n" ${chartsFile}
  fi

  # Enable services for gluster
  sudo sed -i '/^After=.*/i Before=gfsck.service' /etc/systemd/system/kubelet.service
  sudo systemctl enable gfsck.service
  sudo systemctl daemon-reload

  # Setup mariadb before bringing up XL components
  #./mariadb_storage_setup.sh
  # Check to see if an external db is being used.  If so, do not run mariadb locally
  egrep "externalDBName" ${chartsFile}
  externalDB=$(echo $?)
  if [ X${externalDB} = X0 ]
  then
    externalDB=$(egrep "externalDBName" ${chartsFile})
    echo "The database is external from this server"
    echo "${externalDB}"
  else
    /opt/local/bin/configure_mariadb.sh
  fi

  # Setup timescaledb before bringing up XL components
  # ./configure_timescaledb.sh
  # Check to see if an external timescaledb is being used. If so, do not run timescaledb locally
  egrep "externalTimescaleDBName" ${chartsFile}
  externalTimescaleDB=$(echo $?)
  if [ X${externalTimescaleDB} = X0 ]
  then
    externalTimescaleDB=$(egrep "externalTimescaleDBName" ${chartsFile})
    echo "The TimescaleDB database is external from this server"
    echo "${externalTimescaleDB}"
  else
    /opt/local/bin/configure_timescaledb.sh
    # Create mount point for both pgsql and mariadb
    /opt/local/bin/switch_dbs_mount_point.sh
  fi

  # Setup kafka/zookeeper before bringing up XL components (if so configured)
  # Check to see if an external kafka is being used.  If so, do not run kafka locally
  # We have to do two checks because the external kafka variable ("externalKafka") is a substring of
  # the alternative configuration ("externalKafkaIp") that runs Kafka in the VM.
  egrep "externalKafka" ${chartsFile}
  externalKafka=$(echo $?)
  egrep "externalKafkaIP" ${chartsFile}
  runKafkaInVM=$(echo $?)

  if [ X${externalKafka} = X0 ] && [ X${runKafkaInVM} != X0 ]
  then
    externalKafkaName=$(egrep "externalKafka" ${chartsFile})
    echo "Kafka is external from this server:"
    echo "${externalKafkaName}"
  elif [ X${runKafkaInVM} = X0 ]
  then
    echo "Kafka is configured to run in the VM, configuring..."
    /opt/local/bin/configure_kafka.sh
  else
    echo "Kafka is configured to run as a container, skipping configuration for the VM service."
  fi

  # Setup Consul before bringing up XL components (if so configured)
  # Check to see if our Kubernetes deployment is configured to use an external Consul
  # If so, run Consul in the VM
  egrep "externalConsulIP" ${chartsFile}
  externalConsulIP=$(echo $?)

  if [ X${externalConsulIP} = X0 ]
  then
    echo "Consul is configured to run in the VM, configuring..."
    /opt/local/bin/configure_consul.sh
  else
    echo "Consul is configured to run as a container, skipping configuration for the VM service."
  fi

  # Create the operator
  kubectl create -f ${serviceAccountFile} -n turbonomic
  kubectl create -f ${roleFile} -n turbonomic
  kubectl create -f ${roleBindingFile} -n turbonomic
  kubectl create -f ${crdsFile} -n turbonomic
  kubectl create -f ${operatorFile} -n turbonomic
  sleep 10
  kubectl create -f ${chartsFile} -n turbonomic
fi
