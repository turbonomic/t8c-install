#!/bin/bash

# Install the offline updates from a mounted iso.

# Mount the iso
if [ ! -d /mnt/iso ]
then
  sudo mkdir /mnt/iso
fi
log_filename=/tmp/t8c_upgrade_$(date +%Y-%m-%d_%H_%M_%S).log
sudo mount /dev/cdrom /mnt/iso | tee -a $log_filename 2>&1

/mnt/iso/turboload.sh | tee -a $log_filename 2>&1
isoResult=$?
if [ $isoResult -ne 0 ]; then
  echo ""
  echo "Please check on the mounted ISO image, the turboload.sh script encountered an error"
  exit 1
fi

/mnt/iso/turboupgrade.sh | tee -a $log_filename 2>&1
upgradeResult=$?
if [ $upgradeResult -ne 0 ]; then
  echo ""
  echo "Please check the upgrade log at ${log_filename}, a failure was encountered during this process"
else
  sudo umount /mnt/iso | tee -a $log_filename 2>&1
  echo "The ISO image has been unmounted"
fi
