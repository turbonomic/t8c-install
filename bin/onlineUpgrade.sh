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

# Upgrade non-xl application code
if [ ! -d /mnt/iso ]
then
  sudo mkdir /mnt/iso
else
  sudo rm -rf /mnt/iso/*
fi
pushd /mnt/iso/
sudo curl -o /mnt/iso/online-packages.tar http://download.vmturbo.com/appliance/download/updates/${turboVersion}/online-packages.tar
sudo tar -xvf online-packages.tar
/mnt/iso/turboupgrade.sh
