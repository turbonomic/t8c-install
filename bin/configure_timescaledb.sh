#!/bin/bash

# Script to configure Postgres and TimescaleDB on the VM

source /opt/local/bin/libs.sh

PG_CONF="/var/lib/pgsql/12/data/postgresql.conf"
PG_HBA_CONF="/var/lib/pgsql/12/data/pg_hba.conf"

# Check if postgres is installed
yum list --disablerepo=* installed postgresql12-server
if [ "$?" -ne 0 ];
then
    log_msg "Postgres server package is not installed. Aborting..."
    exit 1
fi

# Check if timescaledb is installed
yum list --disablerepo=* installed timescaledb-postgresql-12
if [ "$?" -ne 0 ];
then
    log_msg "TimescaleDB package is not installed. Aborting..."
    exit 1
fi

# stop postgres before configuration
sudo systemctl stop postgresql-12.service

# initialize the database
sudo /usr/pgsql-12/bin/postgresql-12-setup initdb

# amount of memory and cpus used in timescaledb-tune tool for postgres setup.
# number of CPUs used for postgres, try to use provided environment variable first, if it's not
# available, then default to 3
if [[ -z ${PG_CPU_NUM} ]]; then
  PG_CPU_NUM=3
fi
# percentage of the system memory used for postgres, try to use provided environment variable
# first, if it's not available, then default to 10%
if [[ -z ${PG_MEM_PCT} ]]; then
  PG_MEM_PCT=10
fi
# calculate the memory used by postgres in GB, based on defined percentage and total memory.
# float number will be rounded down to the nearest integer.
# for example, if total is 64GB and mem percentage is 10, then it will be 6GB
PG_MEM_GB=$(cat /proc/meminfo | grep MemTotal | awk -v pct="$PG_MEM_PCT" '{print int($2/1024/1024*pct/100)}')

# configuring Postgres & TimescaleDB using timescaledb-tune, which will edit
# /var/lib/pgsql/12/data/postgresql.conf (see https://github.com/timescale/timescaledb-tune)
sudo timescaledb-tune --quiet --yes --pg-config=/usr/pgsql-12/bin/pg_config --memory="${PG_MEM_GB}GB" --cpus=$PG_CPU_NUM

# listen on all IP addresses by uncommenting it and changing localhost to *
sudo sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/g" $PG_CONF

# enable remote access from other hosts (all ipv4 and ipv6 addresses)
echo "# enable remote access from other hosts (all ipv4 and ipv6 addresses)" | sudo tee -a $PG_HBA_CONF > /dev/null
echo "host    all             all             0.0.0.0/0               md5" | sudo tee -a $PG_HBA_CONF > /dev/null
echo "host    all             all             ::/0                    md5" | sudo tee -a $PG_HBA_CONF > /dev/null

# start postgres
log_msg "Starting postgres service"
# enable automatic start when server starts
sudo systemctl enable postgresql-12.service
sudo systemctl restart postgresql-12.service
if [ "$?" -ne 0 ];
then
    log_msg "Failed to start Postgres server. Aborting..."
    exit 1
fi

# set up password for default user postgres
sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD 'vmturbo'"

log_msg "Successfully configured TimescaleDB."
