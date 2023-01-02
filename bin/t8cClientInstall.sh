#!/bin/bash

# get config variables
source /opt/local/etc/turbo.conf

main() {

  # Run this as the root user
  if [[ $(/usr/bin/id -u) -ne 0 ]]
  then
    echo "Not running as root, please become the root user"
    exit
  fi

  parse_args $@
  : ${namespace:?"Bad state: namespace not defined"}
  : ${turboVersion:?"Bad state: turboVersion not defined"}
  : ${node:?"Bad state: node not defined"}

  # Check if the root user needs to change their password
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

  # install kubernetes if necessary
  kubectl cluster-info > /dev/null 2>&1 && echo "kubernetes already initialized" || {
    init_kubernetes
  }

  enable_monitoring

  install_operator

  install_operand

  echo
  echo "Installation complete!"
  echo "You can now perform the token exchange to connect to your SaaS instance"

}

parse_args() {
  while [ "${1-}" != "" ]; do
    case $1 in
    -n | --namespace)
      shift
      namespace="${1}"
      ;;
    -v | --version)
      shift
      turboVersion="${1}"
      ;;
    *)
      echo "Invalid option: ${1}" >&2
      exit 1
      ;;
    esac
    shift
  done
}

init_kubernetes() {

  echo
  echo "###############################################################"
  echo "                    Initializing Kubernetes                    "
  echo "###############################################################"
  echo

  # Ask if the ipsetup script has been run
  ipAnswer=$(yes_or_no "Have you run the ipsetup script to setup networking yet? [y/n]")
  if [ "${ipAnswer}" == "no" ]
  then
    export avoidMessaging="true"
    /opt/local/bin/ipsetup
  fi

  # Check /etc/resolv.conf
  if [[ ! -f /etc/resolv.conf || ! -s /etc/resolv.conf ]]
  then
    echo ""
    echo "exiting......"
    echo "Please check there are valid nameservers in the /etc/resolv.conf"
    echo ""
    exit 0
  fi

  oldIP=${node}
  newIP=$(ip address show eth0 | egrep inet | egrep -v inet6 | awk '{print $2}' | awk -F/ '{print$1}')
  : ${oldIP:?"Bad state: oldIP not defined"}
  : ${newIP:?"Bad state: newIP not defined"}

  sed -i "s/${oldIP}/${newIP}/g" /opt/local/etc/turbo.conf
  # Adjust current hosts file
  sed -i "s/${oldIP}/${newIP}/g" /etc/hosts
  sed -i "s/${oldIP}/${newIP}/g" /etc/cni/net.d/10-calico.conflist
  sed -i "s/${oldIP}/${newIP}/g" /etc/kubernetes/manifests/kube-apiserver.yaml
  sed -i "s/${oldIP}/${newIP}/g" /etc/kubernetes/kubeadm-images.yaml
  sed -i "s/${oldIP}/${newIP}/g" /etc/ssl/etcd/openssl.conf
  sed -i "s/${oldIP}/${newIP}/g" /etc/cni/net.d/calico.conflist.template
  sed -i "s/${oldIP}/${newIP}/g" /etc/kubernetes/kubelet-config.yaml

  echo "------------------------------------"
  # Show the ip address adjustment
  echo "Old IP Address: ${oldIP}"
  echo "New IP Address: ${newIP}"
  echo "------------------------------------"
  echo

  # Create the ssh keys to run with
  if [ ! -f ~/.ssh/id_rsa.pub ]
  then
    ssh-keygen -f ~/.ssh/id_rsa -t rsa -N '' > /dev/null 2>&1
    cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
    # Make sure authorized_keys has the appropriate permissions, otherwise sshd does not allow
    # passwordless ssh.
    chmod 600 ~/.ssh/authorized_keys
  fi

  sleep 5

  # Generate new certificates for etcd
  # {
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

  hostName=node1
  mv peer.crt member-${hostName}.pem
  mv peer.key member-${hostName}-key.pem
  mv server.crt node-${hostName}.pem
  mv server.key node-${hostName}-key.pem
  mv healthcheck-client.crt admin-${hostName}.pem
  mv healthcheck-client.key admin-${hostName}-key.pem


  systemctl restart etcd
  # }

  # Generate new certificates for kubernetes
  # {
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
  # }

  # Add the ~/.kube/config file
  # {
  cp /etc/kubernetes/admin.conf /root/.kube/config
  cp /root/.kube/config /opt/turbonomic/.kube/config
  # }

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

  # wait for 2 minutes
  # {
  # ProgressBar Variables (2 min)
  _start=1
  _end=120
  for number in $(seq ${_start} ${_end})
  do
      sleep 1
      ProgressBar ${number} ${_end}
  done
  printf '\nFinished! kubectl apply commands will follow\n'
  # }

  /usr/local/bin/kubectl apply -f /etc/kubernetes/calico-config.yml -n kube-system 2>/dev/null
  /usr/local/bin/kubectl apply -f /etc/kubernetes/calico-kube-controllers.yml -n kube-system 2>/dev/null

  # Update configmaps
  /usr/local/bin/kubectl get cm -n kube-system kubeadm-config -o yaml > /etc/kubernetes/kubeadm-config.yaml
  /usr/local/bin/kubectl get cm -n kube-system kube-proxy -o yaml > /etc/kubernetes/kube-proxy.yaml

  sed -i "s/${oldIP}/${newIP}/g" /etc/kubernetes/kubeadm-config.yaml
  sed -i "s/${oldIP}/${newIP}/g" /etc/kubernetes/kube-proxy.yaml

  /usr/local/bin/kubectl apply -f /etc/kubernetes/kubeadm-config.yaml 2>/dev/null
  /usr/local/bin/kubectl apply -f /etc/kubernetes/kube-proxy.yaml -n kube-system 2>/dev/null

  # Restart Docker
  systemctl restart docker
  sleep 10

  kubectl cluster-info > /dev/null 2>&1
  kStatus=$?
  support=0
  while [ "${kStatus}" -ne "0" ]
  do
    kubectl cluster-info > /dev/null 2>&1
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

  echo "Kubernetes is ready"

  # Update other files, jic
  sed -i "s/${oldIP}/${newIP}/g" /opt/kubespray/inventory/turbocluster/hosts.yml

  # Set turbo kube context
  kubectl config set-context kubernetes-admin@kubernetes --namespace=${namespace}
  su -c "kubectl config set-context $(kubectl config current-context) --namespace=${namespace}" -s /bin/sh turbo
}

# Repeatedly prompts the user for input until the user provides a valid yes or no input.
# Prints "yes" if the user gave a yes input. Prints "no" if the user gave a no input.
# Example: answer=$(yes_or_no "Is today Friday?")
yes_or_no() {
  local prompt=${1:?"First arg should be prompt"}
  local answer

  while :; do
    read -e -p "${prompt} " answer
    case $answer in
      y | Y | yes)
        echo yes
        return
        ;;
      n | N | no)
        echo no
        return
        ;;
      esac
  done
}

# Show progress bar when waiting
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

enable_monitoring() {
  cat << EOF > /etc/cron.d/tsc_monitor_${namespace}
*/5 * * * * turbo PATH="$PATH:/usr/local/bin" /opt/local/bin/tsc_monitor.py --namespace ${namespace} >> /tmp/tsc_monitor_${namespace}.log
0 0 * * * turbo [[ -e /tmp/tsc_monitor_${namespace}.log ]] && mv /tmp/tsc_monitor_${namespace}.log /tmp/tsc_monitor_${namespace}.log.1
EOF
}

install_operator() {

  echo
  echo "###############################################################"
  echo "             Installing Turbonomic Client Operator             "
  echo "###############################################################"
  echo

  operatorFile=/opt/turbonomic/kubernetes/yaml/t8c-client-operator/operator.yaml

  # create the namespace (if it doesn't already exist)
  kubectl get ns ${namespace} > /dev/null 2>&1 && echo "Namespace ${namespace} already exists." || kubectl create ns ${namespace}

  kubectl apply -n ${namespace} -f $operatorFile

  echo "Waiting for operator to become ready"
  kubectl wait deployment t8c-client-operator-controller-manager -n ${namespace} --for condition=Available=true --timeout=300s || {
    echo "Operator failed to become ready after 300s"
    exit 1
  }

  echo "Operator is ready"
}

install_operand() {

  echo
  echo "###############################################################"
  echo "            Installing Turbonomic Client Deployment            "
  echo "###############################################################"
  echo

  turbonomicclientFile=/opt/turbonomic/kubernetes/yaml/t8c-client-operator/turbonomicclient.yaml
  versionmanagerFile=/opt/turbonomic/kubernetes/yaml/t8c-client-operator/versionmanager.yaml

  sed -i "s/__VERSION__/${turboVersion}/g" $turbonomicclientFile
  kubectl apply -f $turbonomicclientFile -n $namespace  

  echo "Waiting for Turbonomic Client deployment to become ready"

  retry_until_successful "kubectl get deployment skupper-router -n ${namespace}" 600 || {
    echo "skupper-router did not appear after 600s"
    exit 1
  }

  kubectl wait deployment skupper-router -n $namespace --for condition=Available=true --timeout=600s || {
    echo "skupper-router did not ready after 600s"
    exit 1
  }

  echo "Turbonomic Client was installed successfully!"

  answer=$(yes_or_no "Would you like to enable automatic version updates? [y/n]")
  if [ "${answer}" == "yes" ]
  then
    kubectl apply -f $versionmanagerFile -n $namespace
  else
    # Delete the version manager if it already exists. This can happen if the script is run multiple times
    kubectl delete -f $versionmanagerFile -n $namespace > /dev/null 2>&1
  fi
}

retry_until_successful() {
  local cmd=${1:?"First arg should be command to execute"}
  local timeout=${2:?"Second arg should be timeout in seconds"}

  local start_time=$(date +%s)

  while [[ $(($(date +%s)-start_time)) -lt $timeout ]]
  do
    eval $cmd > /dev/null 2>&1 && return 0
    sleep 1
  done

  return 1
}

main $@
