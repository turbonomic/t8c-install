#!/bin/bash

# Script to configure Consul on the VM

set -euo pipefail

source /opt/local/bin/libs.sh

service_exists() {
    local service=$1
    if [ -f "/etc/systemd/system/$service" ]; then
        # service exists
        return 0
    else
        return 1
    fi
}

SRC_CONSUL_CONFIG="/opt/local/etc/consul.hcl"
DEST_CONSUL_CONFIG="/opt/consul/config/consul.hcl"
DEST_CONSUL_DIR="/opt/consul/config/"

# Check if Consul is installed
if service_exists consul.service
then
    log_msg "Consul is installed"
else
    log_msg "Consul is not installed. Aborting..."
    exit 1
fi

sudo systemctl stop consul.service

# Create a consul configuration file using our custom file
mkdir $DEST_CONSUL_DIR
sudo cp -f $SRC_CONSUL_CONFIG $DEST_CONSUL_CONFIG

log_msg "Starting Consul service"
sudo systemctl enable consul.service
sudo systemctl restart consul.service
if [ "$?" -ne 0 ];
then
    log_msg "Failed to start Consul server. Aborting..."
    exit 1
fi

log_msg "Successfully configured Consul."