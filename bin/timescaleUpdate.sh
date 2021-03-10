#!/bin/bash

# Script to upgrade existing timescaledb to 2.x on the VM.
# Note: It assumes timescaledb 1.7.4 is running on the VM. Otherwise use `install_timescaledb.sh`.

source /opt/local/bin/libs.sh

# Stop Postgres in case it's running.
sudo systemctl stop postgresql-12
if [ "$?" -ne 0 ];
then
    log_msg "Failed to stop Postgres server. Aborting..."
    exit 1
fi
log_msg "Stopped timescale DB"

# remove 1.7.5 loader package if it's installed to prevent 2.0.1 installation failure. See https://github.com/timescale/timescaledb/issues/2967
log_msg "Trying to remove timescaledb 1.7.5 loader package to prevent 2.0.1 installation failure, see timescale issue 2967."
sudo yum erase -y --disablerepo="*" timescaledb-loader-postgresql-12-1.7.5-0.el7.x86_64

sudo yum install --disablerepo="*" --enablerepo="timescale_timescaledb" -y timescaledb-2-postgresql-12-2.0.1-0.el7.x86_64 timescaledb-2-loader-postgresql-12-2.0.1-0.el7.x86_64 timescaledb-tools-0.10.1-0.el7.x86_64
log_msg "Installed timescaledb 2"

sudo systemctl start postgresql-12
if [ "$?" -ne 0 ];
then
    log_msg "Failed to start Postgres server. Aborting..."
    exit 1
fi
log_msg "Started timescaledb 2."

sudo -iu postgres psql -d extractor -X -c "\dx timescaledb"
if [ "$?" -ne 0 ];
then
    log_msg "Database extractor doesn't exist, skiping updating timescaledb extension on this database."
    exit 0
fi

# update timescaledb extension
sudo -iu postgres psql -d extractor -X -c "ALTER EXTENSION timescaledb UPDATE;"

# confirm timescaledb extension on extrator database is updated to 2.0.1.
timescaleVersion=$(sudo -iu postgres psql -d extractor -X -c "\dx timescaledb" | sed '4!d' | awk -F"|" '{print $2}' | xargs)

if [ "$timescaleVersion" = "2.0.1" ]
then
  log_msg "Updated timescaledb 2 extension."
else
  log_msg "Failed to update timescaledb 2 extension. Current extension is $timescaleVersion."
  exit 1
fi
