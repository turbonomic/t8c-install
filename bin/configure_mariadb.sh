#!/bin/bash

# Script to configure MariaDB on the VM

set -euo pipefail

source /opt/local/bin/libs.sh

SRC_MY_CNF="/opt/turbonomic/kubernetes/etc/my.cnf"
MY_CNF="/etc/my.cnf.d/server.cnf"
MYSQL_SERVICE_CNF="/usr/lib/systemd/system/mariadb.service"

# Check if mariadb is installed
yum list --disablerepo=* installed Mariadb-server
if [ "$?" -ne 0 ];
then
    log_msg "Mariadb server package is not installed. Aborting..."
    exit 1
fi

sudo systemctl stop mariadb.service
sudo cp -f $SRC_MY_CNF $MY_CNF

# Set mariadb systemd service timeout to infinity.
if ! sudo grep -q 'TimeoutStartSec=0' $MYSQL_SERVICE_CNF ; then
	sudo sed -i '/^\[Service\]$/a TimeoutStartSec=0' $MYSQL_SERVICE_CNF
fi

if ! sudo grep -q 'TimeoutStopSec=0' $MYSQL_SERVICE_CNF ; then
    sudo sed -i '/^TimeoutStartSec=0$/a TimeoutStopSec=0' $MYSQL_SERVICE_CNF
fi


mariadb_tmp_dir=$(grep tmpdir $MY_CNF  | awk '{print $NF}')
mariadb_data_dir=$(grep datadir $MY_CNF  | awk '{print $NF}')
if [ ! -d "$mariadb_data_dir" ]; then
    sudo ln -s /usr/share/mysql /share
    log_msg "Initializing mariadb "
    sudo mkdir -p -m 700 $mariadb_tmp_dir
    sudo chown -R mysql:mysql $mariadb_tmp_dir
    sudo mysql_install_db --defaults-file=$MY_CNF --user=mysql --basedir="/"
fi

mariadb_log_dir="/var/log/mysql"
sudo mkdir -p $mariadb_log_dir
sudo chown -R mysql:mysql $mariadb_log_dir

#Configure innodb buffer pool
configure_buffer_pool $MY_CNF

log_msg "Starting mariadb service"
sudo systemctl enable mariadb.service
sudo systemctl daemon-reload
sudo systemctl restart mariadb.service
if [ "$?" -ne 0 ];
then
    log_msg "Failed to start Mariadb server. Aborting..."
    exit 1
fi

# Setup permissions for XL access
for i in `seq 1 5`
    do
        echo "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' IDENTIFIED BY 'vmturbo' WITH GRANT OPTION; \
              GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' IDENTIFIED BY 'vmturbo' WITH GRANT OPTION; \
              FLUSH PRIVILEGES; " | /usr/bin/mysql  -uroot
        if [ "$?" -eq 0 ]; then
            log_msg '+++ MariaDB privileges granted successful.'
            break
        fi
        log_msg '*** MariaDB init process in progress...'
        sleep $i
done

log_msg "Successfully configured mariadb."

