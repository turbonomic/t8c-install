#!/bin/bash -x

# Run this as the root user
if [[ $(/usr/bin/id -u) -ne 0 ]]
then
  echo "Not running as root, please become the root user"
  exit
fi

oldIP=${1}
newIP=${2}

usage()
{
  echo "Use: `basename $0`  oldIP newIP"
  exit -1
}

# Test variables are not empty.
[ -z "${oldIP}" ] && usage
[ -z "${newIP}" ] && usage

# Adjust current hosts file
sed -i "s/${oldIP}/${newIP}/g" /etc/hosts
sed -i "s/${oldIP}/${newIP}/g" /etc/cni/net.d/10-calico.conflist
sed -i "s/${oldIP}/${newIP}/g" /etc/kubernetes/manifests/kube-apiserver.yaml
sed -i "s/${oldIP}/${newIP}/g" /etc/kubernetes/kubeadm-images.yaml
sed -i "s/${oldIP}/${newIP}/g" /etc/ssl/etcd/openssl.conf
sed -i "s/${oldIP}/${newIP}/g" /etc/cni/net.d/calico.conflist.template

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
mkdir expired
mv apiserver* expired/
mv front-proxy-client.* expired/
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

sleep 120

/usr/local/bin/kubectl apply -f /etc/kubernetes/calico-config.yml -n kube-system
/usr/local/bin/kubectl apply -f /etc/kubernetes/calico-kube-controllers.yml -n kube-system

# Apply the ip change to the instance
sed -i "s/${oldIP}/${newIP}/g" /opt/turbonomic/kubernetes/operator/deploy/crds/charts_v1alpha1_xl_cr.yaml
/usr/local/bin/kubectl apply -f /opt/turbonomic/kubernetes/operator/deploy/crds/charts_v1alpha1_xl_cr.yaml
