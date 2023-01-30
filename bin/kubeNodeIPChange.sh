#!/bin/bash

# Run this as the root user
if [[ $(/usr/bin/id -u) -ne 0 ]]
then
  echo "Not running as root, please become the root user"
  exit
fi

oldIP=$(grep KUBELET_ADDRESS /etc/kubernetes/kubelet.env | grep -oP "[0-9.]+")
newIP=$(ip address show eth0 | egrep inet | egrep -v inet6 | awk '{print $2}' | awk -F/ '{print$1}')

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

read -p "Is the server information correct? (y/n) " ANSWER
shopt -s nocasematch

if [[ ${ANSWER} == y ]]
then
  echo "**** LAST CHANCE **** "
  echo "Use ^c to exit"
  echo "********************* "
  pause
else
  echo "The script will now exit, please enter the proper information."
  exit 0
fi

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
mkdir expired
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
mkdir expired
mv apiserver* expired/
mv front-proxy-client.* expired/
sed -i "s/${oldIP}/${newIP}/g" /etc/kubernetes/kubeadm-config.yaml
sed -i "s/${oldIP}/${newIP}/g" /etc/kubernetes/kubelet.env

# Check kubernetes version
kubeVersion=$(/usr/local/bin/kubectl version | awk '{print $4}' | head -1 | awk -F: '{print $2}' | sed 's/"//g' | sed 's/,//g')
if [ $kubeVersion -ge 20 ]
then 
  sed -i "s/${oldIP}/${newIP}/g" /etc/kubernetes/admin.conf
  sed -i "s/${oldIP}/${newIP}/g" /etc/kubernetes/controller-manager.conf
  sed -i "s/${oldIP}/${newIP}/g" /etc/kubernetes/scheduler.conf
  sed -i "s/${oldIP}/${newIP}/g" /etc/kubernetes/kubelet.conf
  /usr/local/bin/kubeadm init phase certs apiserver --apiserver-cert-extra-sans 10.233.0.1,127.0.0.1,localhost,lb-apiserver.kubernetes.local,$(hostname).cluster.local 2>/dev/null
  /usr/local/bin/kubeadm init phase certs apiserver-kubelet-client 2>/dev/null
  /usr/local/bin/kubeadm init phase certs front-proxy-client 2>/dev/null
else
  /usr/local/bin/kubeadm init phase certs apiserver --config=/etc/kubernetes/kubeadm-config.yaml 2>/dev/null
  /usr/local/bin/kubeadm init phase certs apiserver-kubelet-client --config=/etc/kubernetes/kubeadm-config.yaml 2>/dev/null
  /usr/local/bin/kubeadm init phase certs front-proxy-client --config=/etc/kubernetes/kubeadm-config.yaml 2>/dev/null
fi

cd /etc/kubernetes
if [ $kubeVersion -ge 20 ]
then 
  /usr/local/bin/kubeadm init phase kubeconfig admin 2>/dev/null
  /usr/local/bin/kubeadm init phase kubeconfig kubelet 2>/dev/null
  /usr/local/bin/kubeadm init phase kubeconfig controller-manager 2>/dev/null
  /usr/local/bin/kubeadm init phase kubeconfig scheduler 2>/dev/null
else
  /usr/local/bin/kubeadm alpha kubeconfig user --org system:masters --client-name kubernetes-admin  > admin.conf 2>/dev/null
  /usr/local/bin/kubeadm alpha kubeconfig user --client-name system:kube-controller-manager > controller-manager.conf 2>/dev/null
  /usr/local/bin/kubeadm alpha kubeconfig user --org system:nodes --client-name system:node:$(hostname) > kubelet.conf 2>/dev/null
  /usr/local/bin/kubeadm alpha kubeconfig user --client-name system:kube-scheduler > scheduler.conf 2>/dev/null
fi
systemctl restart kubelet

# Add the ~/.kube/config file
cp /etc/kubernetes/admin.conf /root/.kube/config
/usr/local/bin/kubectl config set-context kubernetes-admin@kubernetes --namespace=turbonomic 2>/dev/null
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
/usr/local/bin/kubectl apply -f /etc/kubernetes/kubeadm-config.yaml -n kube-system
/usr/local/bin/kubectl apply -f /etc/kubernetes/kube-proxy.yaml -n kube-system

# Apply the ip change to the instance
sed -i "s/${oldIP}/${newIP}/g" /opt/turbonomic/kubernetes/operator/deploy/crds/charts_v1alpha1_xl_cr.yaml
/usr/local/bin/kubectl apply -f /opt/turbonomic/kubernetes/operator/deploy/crds/charts_v1alpha1_xl_cr.yaml -n turbonomic

# Update other files, jic
sed -i "s/${oldIP}/${newIP}/g" /opt/kubespray/inventory/turbocluster/hosts.yml
sed -i "s/${oldIP}/${newIP}/g" /opt/kubespray/inventory/turbocluster/hosts.yml
sed -i "s/${oldIP}/${newIP}/g" /opt/kubespray/inventory/turbocluster/hosts.yml
sed -i "s/${oldIP}/${newIP}/g" /opt/local/etc/turbo.conf

# Set turbo kube context
su -c "/usr/local/bin/kubectl config set-context $(/usr/local/bin/kubectl config current-context) --namespace=turbonomic" -s /bin/sh turbo

# Reboot the instance:
echo "#############################################"
echo "Change Completed, please login through the UI"
echo "https://${newIP}"
echo "#############################################"
echo ""
echo ""
echo "############################################################"
echo "Please reboot the server to pick up the changes, if required"
echo "############################################################"
