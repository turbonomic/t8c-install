#!/bin/bash

# Script to prepare a disk for storing mariadb database.

set -euo pipefail

MARIADB_DISK="/dev/sdc"
MARIADB_DISK_PART="/dev/sdc1"
VOLUME_GROUP="vg_turbo_db"
LVM="lv_turbo_db"
DB_LVM_PATH="/dev/mapper/$VOLUME_GROUP-$LVM"
DB_MOUNT_PATH="/var/lib/mysql"
FSTAB="/etc/fstab"
FS_LABEL="XL_MARIADB"
DISK_SIZE=500

source /opt/local/bin/libs.sh

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

log_msg "Preparing mariadb disk"

if [[ ! -b $MARIADB_DISK ]];
then
    log_msg "Disk: $MARIADB_DISK not available"
    exit 1
fi

if [[ -b $MARIADB_DISK_PART ]];
then
    log_msg "Warning: Partition already exists: $MARIADB_DISK_PART "
    # Check if it's a valid mariadb partition that we can use.
    if ! [[ $(blkid $MARIADB_DISK_PART | grep 'LVM2_member') \
        &&  `parted /dev/sdc print | grep -i '^Partition Table' | awk '{print $3}'` == "gpt"  \
        && `lsblk $MARIADB_DISK_PART | grep part | awk '{print $4}'`  == "$DISK_SIZE"G ]];
    then
            log_msg "Wrong partition type detected. Aborting."
            exit 1
    fi
else
    log_msg "Creating lvm partition on $MARIADB_DISK"
    /sbin/parted $MARIADB_DISK mklabel gpt --script
    /sbin/parted $MARIADB_DISK mkpart primary 0% 100% set 1 lvm on --script
fi

log_msg "Creating Physical Volume $MARIADB_DISK_PART"
[[ $(pvs | grep $MARIADB_DISK_PART) ]] || pvcreate $MARIADB_DISK_PART

log_msg "Creating Volume Group $MARIADB_DISK_PART"
[[ $(vgs | grep $VOLUME_GROUP) ]]  || vgcreate $VOLUME_GROUP $MARIADB_DISK_PART

log_msg "Creating Logical Volume $LVM"
[[ $(lvs | grep $LVM) ]] || lvcreate -n $LVM -l 100%FREE $VOLUME_GROUP

log_msg "Creating XFS filesystem on the LVM"
[[ $(blkid $DB_LVM_PATH | grep xfs) ]] || mkfs.xfs -L $FS_LABEL $DB_LVM_PATH

if ! grep -q $DB_MOUNT_PATH $FSTAB ; then
    echo "$DB_LVM_PATH $DB_MOUNT_PATH xfs defaults 0 0" >> $FSTAB
fi

log_msg "Mounting fileystem"
mkdir -p $DB_MOUNT_PATH
mount -a

log_msg "Successfully setup disk for mariadb."
