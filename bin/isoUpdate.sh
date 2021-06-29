#!/bin/bash

# Install the offline updates from a mounted iso.

# Mount the iso
if [ ! -d /mnt/iso ]
then
  sudo mkdir /mnt/iso
fi
sudo mount /dev/cdrom /mnt/iso > /dev/null 2>&1

/mnt/iso/turboload.sh
isoResult=$?
if [ $isoResult -ne 0 ]; then
  echo ""
  echo "Please check on the mounted iso, something went wrong with the turboload.sh script"
  exit 1
fi

/mnt/iso/turboupgrade.sh  | tee -a /tmp/t8c_upgrade_$(date +%Y-%m-%d_%H_%M_%S).log
upgradeResult=$?
if [ $upgradeResult -ne 0 ]; then
  echo ""
  echo "Please check on the upgrade, as something seems to have gone wrong"
else
  sudo umount /mnt/iso
  echo "The iso has been unmounted"
fi
