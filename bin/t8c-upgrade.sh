#!/bin/bash -x

# Upgrade kubernetes/docker version

# Get the parameters used for kubernetes upgrade
source /opt/local/etc/turbo.conf
kubesprayPath="/opt/kubespray"
inventoryPath="${kubesprayPath}/inventory/turbocluster"

pause()
{
    key=""
    echo
    echo -n "Configuration confirmation, press any key to continue with the install"
    stty -icanon
    key=`dd count=1 2>/dev/null`
    stty icanon
}

# Get current kubernetes version
kubeCurrentVersion=$(kubectl get nodes -o yaml | grep kubeletVersion | uniq | awk -F: '{print $2}' | xargs)

# Unpack the upgrade after making a backup
mv ${kubesprayPath} ${kubesprayPath}-${kubeCurrentVersion}
tar -C /opt/ -xvf /tmp/turbo-kubespray.tar.gz
# Add current turbo inventory
cp -r ${kubesprayPath}-${kubeCurrentVersion}/inventory/turbocluster ${kubesprayPath}/inventory/.
# Adjust for relaxing the number of dns server allowed
cp ${kubesprayPath}/roles/container-engine/docker/defaults/main.yml ${kubesprayPath}/roles/container-engine/docker/defaults/main.yml.orig
dns_strict="docker_dns_servers_strict: true"
dns_not_strick="docker_dns_servers_strict: false"
sed -i "s/${dns_strict}/${dns_not_strick}/g" ${kubesprayPath}/roles/container-engine/docker/defaults/main.yml
# Run ansible kubespray install
cd ${kubesprayPath}
/usr/bin/ansible-playbook upgrade-cluster.yml -i inventory/turbocluster/hosts.yml -b --become-user=root #-e kube_version=v1.14.3
# Check on ansible status and exit out if there are any failures.
ansibleStatus=$?
if [ "X${ansibleStatus}" == "X0" ]
then
  echo ""
  echo ""
  echo "######################################################################"
  echo "           Kubespray Upgrade Completed successfully                   "
  echo "######################################################################"
  echo ""
else
  echo ""
  echo ""
  echo "######################################################################"
  echo "                      Kubespray Failed:                               "
  echo "          Please check the /tmp/install.log                           "
  echo "######################################################################"
  echo ""
  exit 0
fi
