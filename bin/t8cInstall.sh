#!/bin/bash

# Restore from backup
nameSpace="turbonomic"
kubeNameSpace="kube-system"

# Run this as the root user
if [[ $(/usr/bin/id -u) -ne 0 ]]
then
  echo "Not running as root, please become the root user"
  exit
fi

# Check if thr root user needs to change their password
changePW=$(chage -l root | grep "Last password change" | awk -F: '{print $2}' | xargs)
if [ "${changePW}" = "password must be changed" ]
then
  echo ""
  echo "It appears the root password has not been set."
  echo "Please set the root password before"
  echo "running this script again."
  echo "Instructions can be found in the Install Guide"
  echo ""
  exit 10
fi

# Check if the install script has been run already
localStorageDataDirectory="/data/turbonomic/"
if grep -q "$localStorageDataDirectory" /etc/fstab
then
  echo ""
  echo "Detected existing installation..."
  echo "exiting......"
  echo "Please do not re-run on an existing install."
  echo ""
  exit 0
fi

# Ask if the ipsetup script has been run
read -e -p "Have you run the ipsetup script to setup networking yet? [y/n] " ipAnswer

if [ "$ipAnswer" != "${ipAnswer#[Nn]}" ]
then
  export avoidMessaging="true"
  /opt/local/bin/ipsetup
fi

# Variable to use if a non-turbonomic deployment
while getopts b:h: flag
do
    case "${flag}" in
        h) hostName=${OPTARG};;
    esac
done
oldIP=$(grep "externalIP:" /opt/turbonomic/kubernetes/operator/deploy/crds/charts_v1alpha1_xl_cr.yaml | awk '{print $2}')
newIP=$(ip address show eth0 | egrep inet | egrep -v inet6 | awk '{print $2}' | awk -F/ '{print$1}')
serviceAccountFile="/opt/turbonomic/kubernetes/operator/deploy/service_account.yaml"
roleFile="/opt/turbonomic/kubernetes/operator/deploy/cluster_role.yaml"
roleBindingFile="/opt/turbonomic/kubernetes/operator/deploy/cluster_role_binding.yaml"
crdsFile="/opt/turbonomic/kubernetes/operator/deploy/crds/charts_v1alpha1_xl_crd.yaml"
operatorFile="/opt/turbonomic/kubernetes/operator/deploy/operator.yaml"
chartsFile="/opt/turbonomic/kubernetes/operator/deploy/crds/charts_v1alpha1_xl_cr.yaml"
localStorageDataDirectory="/data/turbonomic/"
yamlBasePath="/opt/turbonomic/kubernetes/yaml"
glusterDeployPath="/opt/gluster-kubernetes/deploy"

# Change the node name if it is passed in
if [ ! -z "${hostName}" ]
then
  hostnamectl set-hostname ${hostName}
  pushd /etc/; for i in `grep -lr node1 *`; do sed -i "s/node1/${hostName}/g" $i; done; popd
  sed -i "s/node1/${hostName}/g" ${yamlBasePath}/persistent-volumes/local-storage-pv.yaml
fi

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

# Create the ssh keys to run with
if [ ! -f ~/.ssh/id_rsa.pub ]
then
  ssh-keygen -f ~/.ssh/id_rsa -t rsa -N '' > /dev/null 2>&1
  cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
  # Make sure authorized_keys has the appropriate permissions, otherwise sshd does not allow
  # passwordless ssh.
  chmod 600 ~/.ssh/authorized_keys
fi

usage()
{
  echo "Use: `basename $0`  oldIP newIP"
  exit -1
}

pause()
{
    key=""
    echo -n Hit any key to continue....
    stty -icanon
    key=`dd count=1 2>/dev/null`
    stty icanon
}

ProgressBar()
{
# Process data
  let _progress=(${1}*100/${2}*100)/100
  let _done=(${_progress}*4)/10
  let _left=40-$_done
# Build progressbar string lengths
  _fill=$(printf "%${_done}s")
  _empty=$(printf "%${_left}s")

# Build progressbar strings and print the ProgressBar line
# Output example:
# Progress : [########################################] 100%
printf "\rProgress : [${_fill// /#}${_empty// /-}] ${_progress}%%"
}

# ProgressBar Variables (2 min)
_start=1
_end=120

# Test variables are not empty.
[ -z "${oldIP}" ] && usage
[ -z "${newIP}" ] && usage

echo "------------------------------------"
# Show the ip address adjustment
echo "Old IP Address: ${oldIP}"
echo "New IP Address: ${newIP}"
echo "------------------------------------"
echo

sleep 5

# Adjust current hosts file
sed -i "s/${oldIP}/${newIP}/g" /etc/hosts
sed -i "s/${oldIP}/${newIP}/g" /etc/cni/net.d/10-calico.conflist
sed -i "s/${oldIP}/${newIP}/g" /etc/kubernetes/manifests/kube-apiserver.yaml
sed -i "s/${oldIP}/${newIP}/g" /etc/kubernetes/kubeadm-images.yaml
sed -i "s/${oldIP}/${newIP}/g" /etc/ssl/etcd/openssl.conf
sed -i "s/${oldIP}/${newIP}/g" /etc/cni/net.d/calico.conflist.template
sed -i "s/${oldIP}/${newIP}/g" /etc/kubernetes/kubelet-config.yaml

# Generate new certificates for etcd
cd /etc/ssl/etcd/ssl/
if [ ! -d "expired" ] 
then
  mkdir expired
fi
mv admin-node1* expired/
mv member-node1* expired/
mv node-node1* expired/
sed -i "s/${oldIP}/${newIP}/g" /etc/etcd.env

cd /etc/kubernetes/ssl/
ln -s /etc/ssl/etcd/ssl/ etcd
cd /etc/kubernetes/ssl/etcd/
ln -s ca.pem ca.crt
ln -s ca-key.pem ca.key

/usr/local/bin/kubeadm init phase certs etcd-server 2>/dev/null
/usr/local/bin/kubeadm init phase certs etcd-peer 2>/dev/null
/usr/local/bin/kubeadm init phase certs etcd-healthcheck-client 2>/dev/null

if [ ! -z "${hostName}" ]
then
  mv peer.crt member-${hostName}.pem
  mv peer.key member-${hostName}-key.pem
  mv server.crt node-${hostName}.pem
  mv server.key node-${hostName}-key.pem
  mv healthcheck-client.crt admin-${hostName}.pem
  mv healthcheck-client.key admin-${hostName}-key.pem
else
  mv peer.crt member-node1.pem
  mv peer.key member-node1-key.pem
  mv server.crt node-node1.pem
  mv server.key node-node1-key.pem
  mv healthcheck-client.crt admin-node1.pem
  mv healthcheck-client.key admin-node1-key.pem
fi

systemctl restart etcd

# Generate new certificates for kubernetes
cd /etc/kubernetes;  ln -s ssl pki;
cd /etc/kubernetes/ssl/
if [ ! -d "expired" ]
then
  mkdir expired
fi
mv apiserver* expired/.
mv front-proxy-client.* expired/.
if [ ! -z "${hostName}" ]
then
  sed -i "s/${oldIP}/${newIP}/g" /etc/kubernetes/kubeadm-config.yaml
  sed -i "s/node1/${hostname}/g" /etc/kubernetes/kubeadm-config.yaml
  sed -i "s/node1/${hostname}/g" /etc/kubernetes/kubelet.conf
  sed -i "s/node1/${hostname}/g" /etc/kubernetes/kubelet.env
else
  sed -i "s/${oldIP}/${newIP}/g" /etc/kubernetes/kubeadm-config.yaml
fi
sed -i "s/${oldIP}/${newIP}/g" /etc/kubernetes/kubelet.env

/usr/local/bin/kubeadm init phase certs apiserver --config=/etc/kubernetes/kubeadm-config.yaml 2>/dev/null
/usr/local/bin/kubeadm init phase certs apiserver-kubelet-client --config=/etc/kubernetes/kubeadm-config.yaml 2>/dev/null
/usr/local/bin/kubeadm init phase certs front-proxy-client --config=/etc/kubernetes/kubeadm-config.yaml 2>/dev/null

cd /etc/kubernetes
# Replace 127.0.0.1 with the Server IP
sed -i "s/127.0.0.1/${newIP}/g" /etc/kubernetes/admin.conf
sed -i "s/127.0.0.1/${newIP}/g" /etc/kubernetes/controller-manager.conf
sed -i "s/127.0.0.1/${newIP}/g" /etc/kubernetes/scheduler.conf
sed -i "s/127.0.0.1/${newIP}/g" /etc/kubernetes/kubelet.conf

/usr/local/bin/kubeadm init phase kubeconfig admin 2>/dev/null
/usr/local/bin/kubeadm init phase kubeconfig controller-manager 2>/dev/null
/usr/local/bin/kubeadm init phase kubeconfig kubelet 2>/dev/null
/usr/local/bin/kubeadm init phase kubeconfig scheduler 2>/dev/null

systemctl restart kubelet

# Add the ~/.kube/config file
cp /etc/kubernetes/admin.conf /root/.kube/config
/usr/local/bin/kubectl config set-context kubernetes-admin@kubernetes --namespace=${nameSpace}
cp /root/.kube/config /opt/turbonomic/.kube/config

# Update calico
sed -i "s/${oldIP}/${newIP}/g" /etc/kubernetes/calico-config.yml
sed -i "s/${oldIP}/${newIP}/g" /etc/kubernetes/calico-kube-controllers.yml
sed -i "s/${oldIP}/${newIP}/g" /etc/cni/net.d/calico.conflist.template

kubeletStatus=$(systemctl is-active kubelet)
support=0
while [ "X${kubeletStatus}" != "Xactive" ]
do
  echo kubelet service still starting
  kubeletStatus=$(systemctl is-active kubelet)
  support=$(($support+1))
  if [ "X${kubeletStatus}" = "Xactive" ]
  then
    break
  else
    sleep 5
  fi
  # Call support if the kubelet service has not started.
  if [ "${support}" -ge "5" ]
  then
    echo "============================================"
    echo "Something went wrong, please contact Support"
    echo "============================================"
    exit
  fi
done

# Show progress bar for the 2 min wait
for number in $(seq ${_start} ${_end})
do
    sleep 1
    ProgressBar ${number} ${_end}
done
printf '\nFinished! kubectl apply commands will follow\n'

/usr/local/bin/kubectl apply -f /etc/kubernetes/calico-config.yml -n ${kubeNameSpace} 2>/dev/null
/usr/local/bin/kubectl apply -f /etc/kubernetes/calico-kube-controllers.yml -n ${kubeNameSpace} 2>/dev/null

# Update configmaps
/usr/local/bin/kubectl get cm -n ${kubeNameSpace} kubeadm-config -o yaml > /etc/kubernetes/kubeadm-config.yaml
/usr/local/bin/kubectl get cm -n ${kubeNameSpace} kube-proxy -o yaml > /etc/kubernetes/kube-proxy.yaml
if [ ! -z "${hostName}" ]
then
  sed -i "s/${oldIP}/${newIP}/g" /etc/kubernetes/kubeadm-config.yaml
  sed -i "s/node1/${hostname}/g" /etc/kubernetes/kubeadm-config.yaml
  sed -i "s/${oldIP}/${newIP}/g" /etc/kubernetes/kube-proxy.yaml
  sed -i "s/node1/${hostname}/g" /etc/kubernetes/kube-proxy.yaml
else
  sed -i "s/${oldIP}/${newIP}/g" /etc/kubernetes/kubeadm-config.yaml
  sed -i "s/${oldIP}/${newIP}/g" /etc/kubernetes/kube-proxy.yaml
fi
/usr/local/bin/kubectl apply -f /etc/kubernetes/kubeadm-config.yaml 2>/dev/null
/usr/local/bin/kubectl apply -f /etc/kubernetes/kube-proxy.yaml -n ${kubeNameSpace}  2>/dev/null

# Restart Docker
systemctl restart docker
sleep 10

kubectl cluster-info
kStatus=$?
support=0
while [ "${kStatus}" -ne "0" ]
do
  kubectl cluster-info
  kStatus="$?"
  support=$(($support+1))
  if [ "${kStatus}" -ne "0" ]
  then
    echo "Kubernetes is not ready...."
    sleep 10
  else
    break
  fi
  if [ "${support}" -ge "5" ]
  then
    echo "============================================"
    echo "Something went wrong, please contact Support"
    echo "============================================"
    exit
  fi
done

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
# Set up Auth encryption keys before bringing up XL components (if so configured)
# Check to see if kubernetes auth secrets are being used.  If so, pre-generate the keys and
# load them into secrets.
# This must be done after installing Kubernetes, but before running the operator.
egrep "enableExternalSecrets" ${chartsFile} > /dev/null 2>&1
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
grep -r "externalIP:" ${chartsFile} > /dev/null 2>&1
result="$?"
if [ $result -ne 0 ]; then
  sed -i "/tag:/a\
   externalIP: ${node}\n" ${chartsFile}
fi

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
  /opt/local/bin/configure_mariadb.sh 2>/dev/null
fi

# Setup timescaledb before bringing up XL components
# ./configure_timescaledb.sh
# Check to see if an external timescaledb is being used. If so, do not run timescaledb locally
egrep "externalTimescaleDBName" ${chartsFile} > /dev/null 2>&1
externalTimescaleDB=$(echo $?)
if [ X${externalTimescaleDB} = X0 ]
then
  externalTimescaleDB=$(egrep "externalTimescaleDBName" ${chartsFile})
  echo "The TimescaleDB database is external from this server"
  echo "${externalTimescaleDB}"
else
  /opt/local/bin/configure_timescaledb.sh 2>/dev/null
  # Create mount point for both pgsql and mariadb
  /opt/local/bin/switch_dbs_mount_point.sh 2>/dev/null
fi


# Setup kafka/zookeeper before bringing up XL components (if so configured)
# Check to see if an external kafka is being used.  If so, do not run kafka locally
# We have to do two checks because the external kafka variable ("externalKafka") is a substring of
# the alternative configuration ("externalKafkaIp") that runs Kafka in the VM.
egrep "externalKafka" ${chartsFile} > /dev/null 2>&1
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
  /opt/local/bin/configure_kafka.sh 2>/dev/null
else
  echo "Kafka is configured to run as a container, skipping configuration for the VM service."
fi

# Setup Consul before bringing up XL components (if so configured)
# Check to see if our Kubernetes deployment is configured to use an external Consul
# If so, run Consul in the VM
egrep "externalConsulIP" ${chartsFile} > /dev/null 2>&1
externalConsulIP=$(echo $?)

if [ X${externalConsulIP} = X0 ]
then
  echo "Consul is configured to run in the VM, configuring..."
  /opt/local/bin/configure_consul.sh 2>/dev/null
else
  echo "Consul is configured to run as a container, skipping configuration for the VM service."
fi

# Format the partition and mount it in the desired data directory
disk1=$(echo ${device} | awk -F/ '{print $3}')
mkfs.xfs -f ${device}
mkdir -p $localStorageDataDirectory
chown -R turbo.turbo $localStorageDataDirectory
echo "${device} $localStorageDataDirectory                     xfs     defaults        0 0" | tee --append /etc/fstab
sudo mount -a
# This check needs to be better. But no time right now
localStatus=$?

# Create the subdirectories for each PV and fix the ownership/permissions
# These directories are needed to enable local storage class in Kubernetes.
mkdir -p ${localStorageDataDirectory}api-certs
mkdir -p ${localStorageDataDirectory}api
mkdir -p ${localStorageDataDirectory}auth
mkdir -p ${localStorageDataDirectory}consul-data
mkdir -p ${localStorageDataDirectory}kafka-log
mkdir -p ${localStorageDataDirectory}zookeeper-data
mkdir -p ${localStorageDataDirectory}rsyslog-syslogdata
mkdir -p ${localStorageDataDirectory}rsyslog-auditlogdata
mkdir -p ${localStorageDataDirectory}rsyslog-auditlogdata
mkdir -p ${localStorageDataDirectory}topology-processor
mkdir -p ${localStorageDataDirectory}prometheus-alertmanager
mkdir -p ${localStorageDataDirectory}prometheus-server
mkdir -p ${localStorageDataDirectory}graphstate-datacloud-graph
mkdir -p ${localStorageDataDirectory}data-postgres
mkdir -p ${localStorageDataDirectory}redis-data-xl-release-redis-master-0
mkdir -p ${localStorageDataDirectory}redis-data-xl-release-redis-replicas-0
mkdir -p ${localStorageDataDirectory}redis-data-xl-release-redis-replicas-1
mkdir -p ${localStorageDataDirectory}redis-data-xl-release-redis-replicas-2
chown -R turbo.turbo $localStorageDataDirectory
chmod -R 777 $localStorageDataDirectory

# Create the operator
kubectl create -f ${serviceAccountFile} -n ${nameSpace}
kubectl create -f ${roleFile} -n ${nameSpace}
kubectl create -f ${roleBindingFile} -n ${nameSpace}
kubectl create -f ${crdsFile} -n ${nameSpace}
kubectl create -f ${operatorFile} -n ${nameSpace}
sleep 10
kubectl create -f ${chartsFile} -n ${nameSpace}


# Apply the ip change to the instance
sed -i "s/${oldIP}/${newIP}/g" /opt/turbonomic/kubernetes/operator/deploy/crds/charts_v1alpha1_xl_cr.yaml
/usr/local/bin/kubectl apply -f /opt/turbonomic/kubernetes/operator/deploy/crds/charts_v1alpha1_xl_cr.yaml 2>/dev/null

# Update other files, jic
sed -i "s/${oldIP}/${newIP}/g" /opt/kubespray/inventory/turbocluster/hosts.yml
sed -i "s/${oldIP}/${newIP}/g" /opt/kubespray/inventory/turbocluster/hosts.yml
sed -i "s/${oldIP}/${newIP}/g" /opt/kubespray/inventory/turbocluster/hosts.yml
sed -i "s/${oldIP}/${newIP}/g" /opt/local/etc/turbo.conf

# If the hostname changes, run these to disable node1 and make ${hostName} the master
if [ ! -z "${hostName}" ]
then
  /usr/local/bin/kubectl delete node node1
  /usr/local/bin/kubectl label nodes ${hostName} kubernetes.io/role=master
  /usr/local/bin/kubectl label nodes ${hostName} kubernetes.io/role=control-plane
fi

# Set turbo kube context
su -c "kubectl config set-context $(kubectl config current-context) --namespace=${nameSpace}" -s /bin/sh turbo

# Status
echo ""
echo ""
echo "############################"
echo "Start the deployment rollout"
echo "############################"
echo "The installation process is complete, waiting for all the components to start up."
echo "** The script will wait for as long as 30 minutes. **"
echo ""
# Wait for the api pod to become healthy
support=0
while [ "$(kubectl get pods -l=app.kubernetes.io/name='api' -o jsonpath='{.items[*].status.containerStatuses[0].ready}')" != "true" ]
do
  support=$(($support+1))
  sleep 120
  echo "Waiting for Deployment to be ready."
  if [ "${support}" -ge "15" ]
  then
    echo "==========================================================================="
    echo "One or more of your deployments has not started up yet."
    echo "** Please give your environment another 30 minutes to stablize. **"
    echo "To check the status of your components, execute the following command:"
    echo "kubectl get pods"
    echo "If some components are still not ready, contact your support representative"
    echo ""
    echo "Deployments not Ready:"
    echo "**********************"
    /usr/local/bin/kubectl get pods -n ${nameSpace} -o json  | jq -r '.items[] | select(.status.phase != "Running" or ([ .status.conditions[] | select(.type == "Ready" and .status == "False") ] | length ) == 1 ) | .metadata.namespace + "/" + .metadata.name'
    echo "**********************"
    echo ""
    echo "==========================================================================="
    exit
  fi
done

# Wait for the topology-processor  pod to become healthy
support=0
while [ "$(kubectl get pods -l=app.kubernetes.io/name='topology-processor' -o jsonpath='{.items[*].status.containerStatuses[0].ready}')" != "true" ]
do
  sleep 120 
  echo "Waiting for Deployment to be ready."
  if [ "${support}" -ge "5" ]
  then
    echo "==========================================================================="
    echo "One or more of your deployments has not started up yet."
    echo "** Please give your environment another 30 minutes to stablize. **"
    echo "To check the status of your components, execute the following command:"
    echo "kubectl get pods"
    echo "If some components are still not ready, contact your support representative"
    echo ""
    echo "Deployments not Ready:"
    echo "**********************"
    /usr/local/bin/kubectl get pods -n ${nameSpace} -o json  | jq -r '.items[] | select(.status.phase != "Running" or ([ .status.conditions[] | select(.type == "Ready" and .status == "False") ] | length ) == 1 ) | .metadata.namespace + "/" + .metadata.name'
    echo "**********************"
    echo ""
    echo "==========================================================================="
    exit
  fi
done

# Wait for the cost pod to become healthy
support=0
while [ "$(kubectl get pods -l=app.kubernetes.io/name='cost' -o jsonpath='{.items[*].status.containerStatuses[0].ready}')" != "true" ]
do
  sleep 60
  echo "Waiting for Deployment to be ready."
  if [ "${support}" -ge "5" ]
  then
    echo "==========================================================================="
    echo "One or more of your deployments has not started up yet."
    echo "** Please give your environment another 30 minutes to stablize. **"
    echo "To check the status of your components, execute the following command:"
    echo "kubectl get pods"
    echo "If some components are still not ready, contact your support representative"
    echo "Deployments not ready:"
    echo ""
    echo "Deployments not Ready:"
    echo "**********************"
    /usr/local/bin/kubectl get pods -n ${nameSpace} -o json  | jq -r '.items[] | select(.status.phase != "Running" or ([ .status.conditions[] | select(.type == "Ready" and .status == "False") ] | length ) == 1 ) | .metadata.namespace + "/" + .metadata.name'
    echo "**********************"
    echo ""
    echo "==========================================================================="
    exit
  fi
done

# Wait for the history pod to become healthy
support=0
while [ "$(kubectl get pods -l=app.kubernetes.io/name='history' -o jsonpath='{.items[*].status.containerStatuses[0].ready}')" != "true" ]
do
  sleep 60
  echo "Waiting for Deployment to be ready."
  if [ "${support}" -ge "5" ]
  then
    echo "==========================================================================="
    echo "One or more of your deployments has not started up yet."
    echo "** Please give your environment another 30 minutes to stablize. **"
    echo "To check the status of your components, execute the following command:"
    echo "kubectl get pods"
    echo "If some components are still not ready, contact your support representative"
    echo "Deployments not ready:"
    echo ""
    echo "Deployments not Ready:"
    echo "**********************"
    /usr/local/bin/kubectl get pods -n ${nameSpace} -o json  | jq -r '.items[] | select(.status.phase != "Running" or ([ .status.conditions[] | select(.type == "Ready" and .status == "False") ] | length ) == 1 ) | .metadata.namespace + "/" + .metadata.name'
    echo "**********************"
    echo ""
    echo "==========================================================================="
    exit
  fi
done

# Check on the rollout status
for deploy in $(/usr/local/bin/kubectl get deploy --no-headers | awk '{print $1}')
do 
  kubectl rollout status deployment/${deploy} -n ${nameSpace}
done
echo
echo "#################################################"
echo "Deployment Completed, please login through the UI"
echo "https://${newIP}"
echo "#################################################"
