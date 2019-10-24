#!/bin/bash

# Script to externalize MariaDB : migrate from k8s and gluster volume to run outside
# k8s environment on the VM with local storage.

set -eou pipefail
CODE_DIR="/opt/local/bin"
MY_CNF="/etc/my.cnf.d/server.cnf"
MYSQL_MOUNT_DIR="/var/lib/mysql"
MYSQL_DATA_DIR="$MYSQL_MOUNT_DIR/mysql"
TMP_GLUSTER_MOUNT_LOC="/mnt/mariadb-gluster"
RSYNC_LOG_FILE="/var/log/mariadb_migrate_rsync.log"
# Cookie file to indicate that there was a migration which was
# interrupted and the script can be safely retried if the cookie
# file exists.
DB_COPY_COOKIE_FILE="$MYSQL_MOUNT_DIR/db_data_migration.cookie"
MYSQL_SERVICE_CNF="/usr/lib/systemd/system/mariadb.service"

source $CODE_DIR/libs.sh

function umount_gluster {
    if mountpoint -q $TMP_GLUSTER_MOUNT_LOC;then
        log_msg  "Unmounting glusterfs"
        sudo umount $TMP_GLUSTER_MOUNT_LOC
    fi
    [[ -d $TMP_GLUSTER_MOUNT_LOC ]] && sudo rmdir $TMP_GLUSTER_MOUNT_LOC
}

trap umount_gluster EXIT

echo
log_msg "------Migrating MariaDB data from glusterfs to local disk.----"
# Check if mariadb is installed
if ! yum list -q installed Mariadb-server 2>/dev/null
then
    log_msg "Mariadb server package is not installed. Aborting."
    exit 1
fi

# Set mariadb systemd service timeout to infinity.
if ! sudo grep -q 'TimeoutStartSec=0' $MYSQL_SERVICE_CNF ; then
	sudo sed -i '/^\[Service\]$/a TimeoutStartSec=0' $MYSQL_SERVICE_CNF
fi

if ! sudo grep -q 'TimeoutStopSec=0' $MYSQL_SERVICE_CNF ; then
    sudo sed -i '/^TimeoutStartSec=0$/a TimeoutStopSec=0' $MYSQL_SERVICE_CNF
fi

if [[ ! -z "$(sudo ls -A $MYSQL_DATA_DIR 2>/dev/null)" ]] && [[ ! -f $DB_COPY_COOKIE_FILE ]]; then
    log_msg "Error: Mariadb data directory already exists and is not empty. Aborting."
    exit 1
fi

# For safety, stop mariadb service before starting the migration.
[[ $(sudo systemctl -q list-unit-files mariadb.service) ]] && sudo systemctl stop mariadb

# Get the gluster volume where the existing db data is stored.
# If the db container is scaled down, we can't get the volume info(incase,
# script is re-execute due to an error or ssh timeout etc.). So we store the
# db gluster volumen info in a temp file the 1st time this script is executed
# and for subsequent runs, we will get this info from the file.
# we append the current date
gluster_db_volume=$(kubectl get pvc | egrep 'db-data|mysql-data' | awk '{print $3}')
gluster_db_volume_info_file="/tmp/gluster_db_volume.info"
if [[ ! -f $gluster_db_volume_info_file ]]; then
    gluster_volume_path=$(mount | grep $gluster_db_volume | awk  '{print $1}')
    echo $gluster_volume_path > $gluster_db_volume_info_file
else
    gluster_volume_path=$(cat $gluster_db_volume_info_file)
fi

# Shutdown all XL pods including the DB pod so that no DB transactions are on-going.
for pod in $(kubectl get deployments -n turbonomic | awk '{print $1}' | egrep -v 'NAME|t8c-operator' )
do
    kubectl scale deployment $pod --replicas=0
done
echo
log_msg "Waiting for the pods to terminate..."
sleep 60

#Verify that the db deployment is shutdown
db_ready=$(kubectl get deployments -n turbonomic | awk '$1=="db" && $3==0' | wc -l)
if [[ $db_ready -ne 1 ]]; then
    log_msg "DB deployment is still running even after shutdown. Aborting."
    exit 1
fi

sudo mkdir -p $TMP_GLUSTER_MOUNT_LOC
if ! mountpoint -q $TMP_GLUSTER_MOUNT_LOC; then
    log_msg "Mounting mariadb gluster volume"
    # Mount read-only for safety
    sudo mount -t glusterfs $gluster_volume_path $TMP_GLUSTER_MOUNT_LOC  -o ro
fi

# Create data dir
sudo mkdir -p -m 700 $MYSQL_DATA_DIR
sudo chown -R mysql:mysql $MYSQL_DATA_DIR

# Move my.cnf to server.conf
sudo cp $TMP_GLUSTER_MOUNT_LOC/my.cnf $MY_CNF
sudo chown -R mysql:mysql $MY_CNF
if ! sudo grep $MYSQL_DATA_DIR $MY_CNF ; then
    sudo sed -i  's/\/var\/lib\/mysql/\/var\/lib\/mysql\/mysql/g' $MY_CNF
fi
sudo sed -i  's/\/var\/run\/mysqld/\/var\/lib\/mysql\/mysql/g' $MY_CNF

sudo chmod 700 $MY_CNF
sudo touch $DB_COPY_COOKIE_FILE
log_msg "Copying DB data from gluster volume to local disk on the VM."
sudo rsync -a --info=progress2  --log-file=$RSYNC_LOG_FILE $TMP_GLUSTER_MOUNT_LOC/ $MYSQL_DATA_DIR/
sudo chown -R mysql:mysql $MYSQL_DATA_DIR

mariadb_tmp_dir=$(sudo grep tmpdir $MY_CNF  | awk '{print $NF}')
sudo mkdir -p -m 700 $mariadb_tmp_dir
sudo chown -R mysql:mysql $mariadb_tmp_dir

mariadb_log_dir="/var/log/mysql"
sudo mkdir -p $mariadb_log_dir
sudo chown -R mysql:mysql $mariadb_log_dir

configure_buffer_pool $MY_CNF
[[ -L /share ]] ||  sudo ln -s  /usr/share /share

log_msg "Starting MariaDB server."
sudo systemctl enable mariadb
sudo systemctl daemon-reload
sudo systemctl restart  mariadb

log_msg "Successfully migrated mariadb."
sudo rm -f $DB_COPY_COOKIE_FILE
rm -f $gluster_db_volume_info_file

