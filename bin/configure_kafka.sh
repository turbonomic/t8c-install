#!/bin/bash

# Script to configure Kafka and Zookeeper on the VM

set -euo pipefail

source /opt/local/bin/libs.sh

service_exists() {
    local n=$1
    if [[ $(systemctl list-units --all -t service --full --no-legend "$n.service" | cut -f1 -d' ') == $n.service ]]; then
        return 0
    else
        return 1
    fi
}

# It's important to use /opt/local (rather than /opt/turbonomic) as the source for these files
# Because the IP address substitutions in the t8c.sh script are only performed in /opt/local
# and the kafka configuration contains the IP of the VM (which requires substitution).
SRC_ZOOKEEPER_CONFIG="/opt/local/etc/zookeeper.properties"
DEST_ZOOKEEPER_CONFIG="/opt/kafka/config/zookeeper.properties"
SRC_KAFKA_CONFIG="/opt/local/etc/server.properties"
DEST_KAFKA_CONFIG="/opt/kafka/config/server.properties"

# Check if Zookeeper is installed
if service_exists zookeeper.service
then
    log_msg "Zookeeper is not installed. Aborting..."
    exit 1
fi

sudo systemctl stop zookeeper.service

# Configure/start zookeeper before trying to start kafka

# Copy custom zookeeper config
sudo cp -f $SRC_ZOOKEEPER_CONFIG $DEST_ZOOKEEPER_CONFIG

sudo systemctl enable zookeeper.service
sudo systemctl restart zookeeper.service

# Check if Kafka is installed
if service_exists kafka.service
then
    log_msg "Kafka is not installed. Aborting..."
    exit 1
fi

sudo systemctl stop kafka.service

# Replace the default kafka configuration file with our custom file
sudo cp -f $SRC_KAFKA_CONFIG $DEST_KAFKA_CONFIG

log_msg "Starting Kafka service"
sudo systemctl enable kafka.service
sudo systemctl restart kafka.service
if [ "$?" -ne 0 ];
then
    log_msg "Failed to start Kafka server. Aborting..."
    exit 1
fi

log_msg "Successfully configured Kafka."

