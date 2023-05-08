#!/bin/bash

# Script to install Postgres & TimescaleDB on the VM.
# Note: This is usually packaged in the OVA, so if you deploy a VM with OVA, it should
# automatically have postgres and timescaledb. This script is provided just in case manual
# installation is needed.

set -euo pipefail

source /opt/local/bin/libs.sh

# install the repository RPM
if [ -d /mnt/iso/rpm/ ]
then
  sudo yum localinstall --disablerepo="*" -q -y /mnt/iso/rpm/pgdg-redhat-repo-latest.noarch.rpm > /dev/null 2>&1
else
  sudo yum install --disablerepo="mariadb" -q -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm > /dev/null 2>&1
fi

# Check if the RPMs are on the mounted iso
if [ -d /mnt/iso/rpm/ ]
then
  # install the client, libs and server packages
  sudo yum localinstall --disablerepo="*" -y /mnt/iso/rpm/postgresql12*.rpm
else
  # install the client, libs and server packages
  sudo yum install --disablerepo="mariadb" -y postgresql12-libs-12.6-1PGDG.rhel7.x86_64 postgresql12-12.6-1PGDG.rhel7.x86_64 postgresql12-server-12.6-1PGDG.rhel7.x86_64
fi

log_msg "Successfully installed Postgres."

# Add TimescaleDB's third party repository and install TimescaleDB, which will download any
# dependencies it needs from the PostgreSQL repo
# Add our repo
sudo tee /etc/yum.repos.d/timescale_timescaledb.repo <<EOL
[timescale_timescaledb]
name=timescale_timescaledb
baseurl=https://packagecloud.io/timescale/timescaledb/el/7/\$basearch
repo_gpgcheck=1
gpgcheck=0
enabled=1
gpgkey=https://packagecloud.io/timescale/timescaledb/gpgkey
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
metadata_expire=300
EOL

# Check if the RPMs are on the mounted iso
if [ -d /mnt/iso/rpm/ ]
then
  # Now install appropriate package for PG version
  sudo yum localinstall --disablerepo="*" -y /mnt/iso/rpm/timescaledb*.rpm
else
  # Now install appropriate package for PG version
  sudo yum install --disablerepo="mariadb" -y timescaledb-2-postgresql-12-2.10.2-0.el7.x86_64 timescaledb-2-loader-postgresql-12-2.10.2-0.el7.x86_64 timescaledb-tools-0.14.3-0.el7.x86_64
fi

log_msg "Successfully installed TimescaleDB."

