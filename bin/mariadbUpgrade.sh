#!/bin/bash

# mariadbUpgrade.sh

# Check if the database is hosted on this kubernetes node
# Not external to the instance, or as a docker image
serverIp=$(ifconfig eth0 | grep 'inet' |egrep -v 'inet6' | cut -d: -f2 | awk '{ print $2}')
databaseIp=$(grep externalDbIP /opt/turbonomic/kubernetes/operator/deploy/crds/charts_v1alpha1_xl_cr.yaml | egrep -v '#' | awk '{print $2}')
databaseName=$(grep externalDBName /opt/turbonomic/kubernetes/operator/deploy/crds/charts_v1alpha1_xl_cr.yaml | egrep -v '#' | awk '{print $2}')
databaseUpgradeVersion="10.5.18"

# Check to see if the database is remote from the server
if [ -z "${databaseIp+x}" ]
then
  if [ -z "${databaseName}" ]
  then
    echo "Exiting, the database server does not appear to be hosted on this kubernetes node"
    exit 1
  fi
else
  if [ X${serverIp} != X${databaseIp} ]
  then
    echo "Exiting, the database server does not appear to be hosted on this kubernetes node"
    exit 1
  fi
fi

# Check the version installed
dbVersion=$(rpm -qi MariaDB-server | grep Version | head -1| awk -F: '{print $2}' | xargs)
if [ X${dbVersion} = "X${databaseUpgradeVersion}" ]
then
  echo "MariaDB version ${dbVersion} is already installed"
  exit 0
fi

# Change the mariadb.repo to support the upgrade
sudo rm -rf /etc/yum.repos.d/mariadb.repo

sudo bash -c "cat <<EOF > /etc/yum.repos.d/mariadb.repo
[mariadb]
name = MariaDB-$databaseUpgradeVersion
baseurl = https://archive.mariadb.org/mariadb-${databaseUpgradeVersion}/yum/rhel7-amd64/
#baseurl=https://yum.mariadb.org/${databaseUpgradeVersion}/centos7-amd64
# alternative: baseurl=https://archive.mariadb.org/mariadb-${databaseUpgradeVersion}/yum/centos7-amd64
gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1
EOF"

sudo yum clean all

# Check if we are doing an offline or online upgrade
if [ -d /mnt/iso/mariadb_rpm ]
then
  echo "This is going to be on offline mariadb upgrade"
else
  # Check if the mariadb is reachable
  sudo yum repolist mariadb > /tmp/yumcheck
  result=$(grep repolist /tmp/yumcheck | awk '{print $2}')
  echo $result
  if [ $result -eq 0 ]
  then
    echo "***********************************************************"
    echo "You seem to not have access to the mariadb yum repository." 
    echo "Please open the firewall or use the offline upgrade method!"
    echo "***********************************************************"
    exit 1
  else
    echo "This is going to be on online mariadb upgrade"
  fi
fi

# Run the upgrade script
echo
echo "Enter the mysql password:"
dbPassword=$(systemd-ask-password password:)

# Get Major DB version
dbMajorVersion=$(mysql -u root --password=${dbPassword} -e "SHOW VARIABLES LIKE 'version';"  | grep 10 | awk '{print $2}' | awk -F. '{print $1$2}')

# Check to ensure the password is correct
mysql -uroot -p${dbPassword} -e"quit" > /dev/null 2>&1
result=$?
if [ $result -ne 0 ]
then
  echo "You have entered an invalid database password"
  exit 1
fi

# Upgrade Mariadb - Requires the Turbonomic system to be stopped
# Scale down the operator
echo "Scale down the Operator"
echo "-----------------------"
/usr/local/bin/kubectl scale deployment --replicas=0 t8c-operator -n turbonomic
operatorCount=$(/usr/local/bin/kubectl get pod -n turbonomic | grep t8c-operator | wc -l)
while [ ${operatorCount} -gt 0 ]
do
  operatorCount=$(/usr/local/bin/kubectl get pod -n turbonomic | grep t8c-operator | wc -l)
done
echo

# Scale down the turbonomic pods
echo "Scale down Turbonomic"
echo "---------------------"
/usr/local/bin/kubectl scale deployment --replicas=0 --all -n turbonomic
turboPodCount=$(/usr/local/bin/kubectl get pod -n turbonomic | wc -l)
while [ ${turboPodCount} -gt 0 ]
do
  turboPodCount=$(/usr/local/bin/kubectl get pod -n turbonomic | egrep -v "prometheus-node-exporter|fluent-bit-loki|loki|elasticsearch|logstash|datacloud|NAME" | wc -l)
done
echo

# Continue with the upgrade
sudo systemctl stop mariadb
if [ X${dbMajorVersion} = "X101" ]
then
  echo "run uninstall"
  sudo yum erase --disablerepo=* MariaDB-server MariaDB-shared -y >/dev/null
fi

# Perform the Mariadb upgrade
mariadbRpms="/mnt/iso/mariadb_rpm"
if [ -d ${mariadbRpms} ]
then
  sudo yum install --disablerepo=* -y /mnt/iso/mariadb_rpm/*.rpm
  result=$?
  if [ $result -ne 0 ]
  then
    echo "Something went wrong with the Mariadb upgrade, please contact support"
    exit 1
  fi
else
  # Stop and Remove the existing mariadb server package
  sudo yum repolist | grep docker-engine >/dev/null
  deRepo=$?
  if [ $deRepo -eq 0 ]
  then
    sudo yum install --disablerepo=docker-engine MariaDB-server MariaDB-shared MariaDB-client MariaDB-common -y
    result=$?
    if [ $result -ne 0 ]
    then
      echo "Something went wrong with the Mariadb upgrade, please contact support"
     exit 1
    fi
    else
    sudo yum install MariaDB-server MariaDB-shared MariaDB-client MariaDB-common -y
    result=$?
    if [ $result -ne 0 ]
    then
      echo "Something went wrong with the Mariadb upgrade, please contact support"
     exit 1
    fi
  fi
fi

# Put the server.cnf into place
sudo cp /etc/my.cnf.d/server.cnf.rpmsave /etc/my.cnf.d/server.cnf

# Make sure ownership is proper
sudo chown -R mysql.mysql /var/lib/mysql

# Enable the mariadb server to start at boot time
sudo systemctl enable mariadb
sudo systemctl daemon-reload

# Start the upgraded version
sudo sed -i "/event_scheduler/s/ON/OFF/" /etc/my.cnf.d/server.cnf
sudo systemctl start mariadb

# Test the database is running
mariadbStatus=$(systemctl is-active mariadb)
if [ "X$mariadbStatus" = "Xactive" ]
then
  echo
  echo "MariaDB process started properly, continuing"
else
  echo
  echo "*MariaDB did not start properly, please check the logs and the daemon status*"
  echo "Logging at /var/log/mysql"
  echo "System Daemon: sudo systemctl status mariadb"
  exit 1
fi

LISTENING=$(netstat -an|grep LISTEN| grep -w 3306 | wc -l)
if [ "$LISTENING" -eq '1' ]
then
  echo
  echo "Mariadb process is listening on a proper port, continuing"
else
  echo
  echo "*MariaDB seems to not be listening on a proper port*"
  echo "Logging at /var/log/mysql"
  echo "System Daemon: sudo systemctl status mariadb"
  exit 1
fi


sudo /usr/bin/mysql_upgrade -uroot -p${dbPassword}

sudo systemctl stop mariadb

# Start the upgraded version
sudo sed -i "/event_scheduler/s/OFF/ON/" /etc/my.cnf.d/server.cnf
sudo systemctl start mariadb

# Test the database is running
mariadbStatus=$(systemctl is-active mariadb)
if [ "X$mariadbStatus" = "Xactive" ]
then
  echo
  echo "MariaDB process started properly, continuing"
else
  echo
  echo "*MariaDB did not start properly, please check the logs and the daemon status*"
  echo "Logging at /var/log/mysql"
  echo "System Daemon: sudo systemctl status mariadb"
  exit 1
fi

# Add check for db process running, including some testing in case of start timing issues.
LISTENING=$(netstat -an| grep LISTEN | grep -w 3306 | wc -l)
if [ "$LISTENING" -ne '1' ]
then
  increment=1
  while [ $increment -le 5 ]
  do
    LISTENING=$(netstat -an|grep LISTEN| grep -w 3306 | wc -l)
    if [ "$LISTENING" -ne '1' ]
    then
      sleep 5
      increment=$(( $increment + 1 ))
    else
      break
    fi
  done
fi

LISTENING=$(netstat -an|grep LISTEN | grep -w 3306 | wc -l)
if [ "$LISTENING" -eq '1' ]
then
  echo
  echo "Mariadb process is listening on a proper port, continuing"
else
  echo
  echo "*MariaDB seems to not be listening on a proper port*"
  echo "Logging at /var/log/mysql"
  echo "System Daemon: sudo systemctl status mariadb"
  exit 1
fi

# Test the database
# Show the database version now running
echo "Running mariadb version:"
mysql -u root --password=${dbPassword} -e "SHOW VARIABLES LIKE 'version';"

# Scale Up Turbonomic Application when it is confirmed the database is running properly
echo
echo "########################################################################"
echo "When confirmed the mariadb has be upgraded and is properly working, run:"
echo "kubectl scale deployment --replicas=1 t8c-operator -n turbonomic"
echo "########################################################################"
