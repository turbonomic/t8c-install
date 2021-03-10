#!/bin/bash

# Run this as the root user
if [[ $(/usr/bin/id -u) -ne 0 ]]
then
  echo "Not running as root, please become the root user"
  exit
fi

# Variable to use if a non-turbonomic deployment
oldIP=$(grep "externalIP:" /opt/turbonomic/kubernetes/operator/deploy/crds/charts_v1alpha1_xl_cr.yaml | awk '{print $2}')
newIP=$(ip address show eth0 | egrep inet | egrep -v inet6 | awk '{print $2}' | awk -F/ '{print$1}')
deploymentBrand=${1}
oldIP=$(grep "externalIP:" /opt/turbonomic/kubernetes/operator/deploy/crds/charts_v1alpha1_xl_cr.yaml | awk '{print $2}')
newIP=$(ip address show eth0 | egrep inet | egrep -v inet6 | awk '{print $2}' | awk -F/ '{print$1}')
serviceAccountFile="/opt/turbonomic/kubernetes/operator/deploy/service_account.yaml"
roleFile="/opt/turbonomic/kubernetes/operator/deploy/cluster_role.yaml"
roleBindingFile="/opt/turbonomic/kubernetes/operator/deploy/cluster_role_binding.yaml"
crdsFile="/opt/turbonomic/kubernetes/operator/deploy/crds/charts_v1alpha1_xl_crd.yaml"
operatorFile="/opt/turbonomic/kubernetes/operator/deploy/operator.yaml"
chartsFile="/opt/turbonomic/kubernetes/operator/deploy/crds/charts_v1alpha1_xl_cr.yaml"
localStorageDataDirectory="/data/turbonomic/"

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
  ssh-keygen -f ~/.ssh/id_rsa -t rsa -N ''
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

/usr/local/bin/kubeadm init phase certs etcd-server
/usr/local/bin/kubeadm init phase certs etcd-peer
/usr/local/bin/kubeadm init phase certs etcd-healthcheck-client

mv peer.crt member-node1.pem
mv peer.key member-node1-key.pem
mv server.crt node-node1.pem
mv server.key node-node1-key.pem
mv healthcheck-client.crt admin-node1.pem
mv healthcheck-client.key admin-node1-key.pem

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
sed -i "s/${oldIP}/${newIP}/g" /etc/kubernetes/kubeadm-config.yaml
sed -i "s/${oldIP}/${newIP}/g" /etc/kubernetes/kubelet.env

/usr/local/bin/kubeadm init phase certs apiserver --config=/etc/kubernetes/kubeadm-config.yaml
/usr/local/bin/kubeadm init phase certs apiserver-kubelet-client --config=/etc/kubernetes/kubeadm-config.yaml
/usr/local/bin/kubeadm init phase certs front-proxy-client --config=/etc/kubernetes/kubeadm-config.yaml

cd /etc/kubernetes
/usr/local/bin/kubeadm alpha kubeconfig user --org system:masters --client-name kubernetes-admin  > admin.conf
/usr/local/bin/kubeadm alpha kubeconfig user --client-name system:kube-controller-manager > controller-manager.conf
/usr/local/bin/kubeadm alpha kubeconfig user --org system:nodes --client-name system:node:$(hostname) > kubelet.conf
/usr/local/bin/kubeadm alpha kubeconfig user --client-name system:kube-scheduler > scheduler.conf

systemctl restart kubelet

# Add the ~/.kube/config file
cp /etc/kubernetes/admin.conf /root/.kube/config
/usr/local/bin/kubectl config set-context kubernetes-admin@kubernetes --namespace=turbonomic
cp /root/.kube/config /opt/turbonomic/.kube/config

# Update calico
sed -i "s/${oldIP}/${newIP}/g" /etc/kubernetes/calico-config.yml
sed -i "s/${oldIP}/${newIP}/g" /etc/kubernetes/calico-kube-controllers.yml
sed -i "s/${oldIP}/${newIP}/g" /etc/cni/net.d/calico.conflist.template

kubeletStatus=$(systemctl is-active kubelet)

while [ "X${kubeletStatus}" != "Xactive" ]
do
  echo kubelet service still starting
  kubeletStatus=$(systemctl is-active kubelet)
  sleep 5
done

# Show progress bar for the 2 min wait
for number in $(seq ${_start} ${_end})
do
    sleep 1
    ProgressBar ${number} ${_end}
done
printf '\nFinished! kubectl apply commands will follow\n'

/usr/local/bin/kubectl apply -f /etc/kubernetes/calico-config.yml -n kube-system
/usr/local/bin/kubectl apply -f /etc/kubernetes/calico-kube-controllers.yml -n kube-system

# Update configmaps
/usr/local/bin/kubectl get cm -n kube-system kubeadm-config -o yaml > /etc/kubernetes/kubeadm-config.yaml
/usr/local/bin/kubectl get cm -n kube-system kube-proxy -o yaml > /etc/kubernetes/kube-proxy.yaml
sed -i "s/${oldIP}/${newIP}/g" /etc/kubernetes/kubeadm-config.yaml
sed -i "s/${oldIP}/${newIP}/g" /etc/kubernetes/kube-proxy.yaml
/usr/local/bin/kubectl apply -f /etc/kubernetes/kubeadm-config.yaml
/usr/local/bin/kubectl apply -f /etc/kubernetes/kube-proxy.yaml -n kube-system

# Restart Docker
systemctl restart docker
sleep 10

kubectl cluster-info
kStatus=$?
while [ "${kStatus}" -ne "0" ]
do
  kubectl cluster-info
  kStatus="$?"
  echo "Kubernetes is not ready...."
  sleep 10
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
   externalIP: ${node}\n" ${chartsFile}
fi

# Set branding if not turbonomic
if [ ! -z "${deploymentBrand}" ]
then
  # Adjust regular installs
  echo "  ui:" >> ${chartsFile}
  echo "    image:" >> ${chartsFile}
  echo "      repository: ${deploymentBrand}" >> ${chartsFile}
  echo "      tag: ${turboVersion}" >> ${chartsFile}
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
chown -R turbo.turbo $localStorageDataDirectory
chmod -R 777 $localStorageDataDirectory

# Create the operator
kubectl create -f ${serviceAccountFile} -n turbonomic
kubectl create -f ${roleFile} -n turbonomic
kubectl create -f ${roleBindingFile} -n turbonomic
kubectl create -f ${crdsFile} -n turbonomic
kubectl create -f ${operatorFile} -n turbonomic
sleep 10
kubectl create -f ${chartsFile} -n turbonomic


# Apply the ip change to the instance
sed -i "s/${oldIP}/${newIP}/g" /opt/turbonomic/kubernetes/operator/deploy/crds/charts_v1alpha1_xl_cr.yaml
/usr/local/bin/kubectl apply -f /opt/turbonomic/kubernetes/operator/deploy/crds/charts_v1alpha1_xl_cr.yaml

# Update other files, jic
sed -i "s/${oldIP}/${newIP}/g" /opt/kubespray/inventory/turbocluster/hosts.yml
sed -i "s/${oldIP}/${newIP}/g" /opt/kubespray/inventory/turbocluster/hosts.yml
sed -i "s/${oldIP}/${newIP}/g" /opt/kubespray/inventory/turbocluster/hosts.yml
sed -i "s/${oldIP}/${newIP}/g" /opt/local/etc/turbo.conf

# Reboot the instance:
echo ""
echo ""
echo "################################################"
echo "Please reboot the server to pick up the changes"
echo "################################################"
