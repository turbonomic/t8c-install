#!/bin/bash

# execute after PostgreSQL is already installed

# default mount points for mysql and postgres
MYSQL_DIR="/var/lib/mysql"
PGSQL_DIR="/var/lib/pgsql"
NEW_DB_MOUNTPOINT="/var/lib/dbs"

# get free memory on the mysql partition
FREE_SPACE=$(sudo df|grep $MYSQL_DIR|awk '{print $4}'|bc -l)
# we require at least 200 gb free
REQUIRED_SPACE=209715200

source /opt/local/bin/libs.sh

log_msg "Starting DBs mountpoint switch..."

# TODO check the mountpoint is the expected one (should be the same as the MYSQL_DIR)

# Exit the script if /var/lib/dbs is already created
ls ${NEW_DB_MOUNTPOINT}
result=$?
if [ $result -eq 0 ]
then
  echo "This script looks like it has already been run, please check ${NEW_DB_MOUNTPOINT}"
  exit 0
fi

# return if mysql dir is not present
if [ ! -d "$MYSQL_DIR" ]
then
  log_msg "Mysql directory not found. Please contact support to proceed."
  exit 1
fi

# return if postgreSQL dir is not present
if [ ! -d "$PGSQL_DIR" ]
then
  log_msg "PostegreSQL directory not found. Please install and configure PostgreSQL before running this script."
  exit 1
fi

# check if there is enough space in the mysql partition
if [ $FREE_SPACE -lt $REQUIRED_SPACE ];
then
  log_msg "Not enough free space in the Mysql partition. Please contact support to proceed."
  exit 1
fi

# stop mysql before continuing
sudo systemctl stop mysql
log_msg "Mysql stopped"

# stop postgres before continuing
sudo systemctl stop postgresql-12.service
log_msg "PostgreSQL stopped"

# copy mysql data into a volume subdir (basically one level deeper)
log_msg "Moving Mysql data (a move error on mysqltmp will appear, it's normal)"
sudo mkdir "$MYSQL_DIR"/mysqltmp
sudo chown mysql:mysql "$MYSQL_DIR"/mysqltmp
sudo mv "$MYSQL_DIR"/* "$MYSQL_DIR"/mysqltmp
sudo mv "$MYSQL_DIR"/mysqltmp "$MYSQL_DIR"/mysql

# copy pgsql data into the same volume mysql is using
log_msg "Moving PostgreSQL data"
sudo cp -rp "$PGSQL_DIR" "$MYSQL_DIR"
# backup the original pgsql data dir
sudo mv "$PGSQL_DIR" "$PGSQL_DIR".bkp

# unmount the current mysql volume, and mount it back in the new mountpoint
log_msg "Change Mysql volume mountpoint"
sudo umount "$MYSQL_DIR"
# create new mountpoint dir
sudo mkdir "$NEW_DB_MOUNTPOINT"
# change the mount options for the mysql volume, in order to support xfs project quota
sudo sed -ie '/^\/dev\/mapper\/turbo-var_lib_mysql/s/defaults/defaults,pquota/' /etc/fstab
# change the mountpoint itself to the new one
# TODO use the variable instead of hardcode it
sudo sed -ie '/^\/dev\/mapper\/turbo-var_lib_mysql/s/\/var\/lib\/mysql/\/var\/lib\/dbs/' /etc/fstab
# re-mount everything
sudo mount -a
# change dir name to mysql (which should be empty at this point)
sudo mv "$MYSQL_DIR" "$MYSQL_DIR".bkp

# create new symlinks
log_msg "Creating new symlinks"
sudo ln -s "$NEW_DB_MOUNTPOINT"/mysql "$MYSQL_DIR"
sudo ln -s "$NEW_DB_MOUNTPOINT"/pgsql "$PGSQL_DIR"

# enable pgsql quota at 200gb
log_msg "Applying xfs quota on PostgreSQL directory"
echo "1:/var/lib/dbs/pgsql" | sudo tee /etc/projects
echo "Postgresql:1" | sudo tee /etc/projid
sudo xfs_quota -x -c 'project -s Postgresql' "$NEW_DB_MOUNTPOINT"
sudo xfs_quota -x -c 'limit -p bhard=200g Postgresql' "$NEW_DB_MOUNTPOINT"
#check new quota
log_msg "Quota applied for PostgreSQL:"
sudo xfs_quota -xc 'report -pbih' "$NEW_DB_MOUNTPOINT"

# restarting dbs
log_msg "Restarting DBs"
sudo systemctl start mysql
sudo systemctl start postgresql-12.service

log_msg "DB mount points successfully switched"
