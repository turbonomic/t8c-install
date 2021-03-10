#!/bin/bash

# exit when any command fails
#set -e

# keep track of the last executed command
#trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG
# echo an error message before exiting
#trap 'echo "\"${last_command}\" command failed with exit code $?."' EXIT

turboVersion=${1}

usage()
{
  echo
  echo "======"
  echo "USAGE:"
  echo "======"
  echo "`basename $0` <turboVersion>"
  echo
  exit -1
}

# Test variables are not empty.
[ -z "${turboVersion}" ] && usage

# Make sure the turbo version is greater than what is currently deployed
versionTag=$(grep 'tag' /opt/turbonomic/kubernetes/operator/deploy/crds/charts_v1alpha1_xl_cr.yaml | head -n1 | awk '{print $2}')
versionTag=${versionTag/-SNAPSHOT/}
currentTag=$(echo ${versionTag} | sed 's/\.//g')
updateTag=$(echo ${turboVersion} | sed 's/\.//g')
if [[ "${updateTag}" < "${currentTag}" ]] || [[ "${updateTag}" = "${currentTag}" ]]
then
  echo "Exiting....."
  echo "Ensure that the OpsManager is upgraded to a newer version than the current version"
  exit 1
fi

# Check for mount image on /mnt/iso
mount | grep "/mnt/iso" > /dev/null
result=$?
if [ x${result} = x0 ]
then
  echo "Exiting....."
  echo "It appears there is something mounted on /mnt/iso"
  echo "Please run: umount /mnt/iso and try again"
  exit 1
fi

# Upgrade non-xl application code
if [ ! -d /mnt/iso ]
then
  sudo mkdir /mnt/iso
else
  sudo rm -rf /mnt/iso/*
fi
pushd /mnt/iso/
sudo curl -o /mnt/iso/online-packages.tar https://download.vmturbo.com/appliance/download/updates/${turboVersion}/online-packages.tar
sudo tar -xvf online-packages.tar
/mnt/iso/turboupgrade.sh
