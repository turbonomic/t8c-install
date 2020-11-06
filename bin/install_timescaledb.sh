#!/bin/bash

# Script to install Postgres & TimescaleDB on the VM.
# Note: This is usually packaged in the OVA, so if you deploy a VM with OVA, it should
# automatically have postgres and timescaledb. This script is provided just in case manual
# installation is needed.

set -euo pipefail

source /opt/local/bin/libs.sh

# install the repository RPM
sudo yum install --disablerepo="mariadb" -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm

# install the client packages
sudo yum install --disablerepo="mariadb" -y postgresql12

# install the server packages
sudo yum install --disablerepo="mariadb" -y postgresql12-server

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

# Now install appropriate package for PG version
sudo yum install --disablerepo="mariadb" -y timescaledb-postgresql-12

log_msg "Successfully installed TimescaleDB."

