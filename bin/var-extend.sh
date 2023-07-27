#!/bin/bash

# Script to extend a partition

# Bail out of not run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

set -e

# Check if /dev/sdc is already in use
if lsblk -no MOUNTPOINT /dev/sdc | grep -q .; then
    echo "/dev/sdc is already in use"
    exit 1
fi

# Partition the device
echo -e "n\np\n1\n\n\nw" | fdisk /dev/sdc

# Create a physical volume
pvcreate /dev/sdc1

# Extend the volume group
vgextend turbo /dev/sdc1

# Extend the logical volume
lvextend -l +100%FREE /dev/turbo/var

# Resize the XFS file system
xfs_growfs /dev/turbo/var
