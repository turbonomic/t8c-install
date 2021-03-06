#!/bin/bash

# Setup network time server using chrony
ntpInfoFile="/tmp/ntp-information"
chronyTemp="/tmp/chrony.conf"
newNtp="/tmp/new-ntp-servers"

# Get current server information
echo "=====================" > ${ntpInfoFile}
echo "Current NTP Servers :" >> ${ntpInfoFile}
echo "=====================" >> ${ntpInfoFile}
grep "^server" /etc/chrony.conf | sed 's/server//g' | sed 's/iburst//g' >> ${ntpInfoFile}
echo "" >> ${ntpInfoFile}
timedatectl status | grep "Time zone" | tr -d '[:space:]' | awk -F: '{print $1,":"}' >> ${ntpInfoFile}
echo "==========" >> ${ntpInfoFile}
timedatectl status | grep "Time zone" | tr -d '[:space:]' | awk -F: '{print $2}' >> ${ntpInfoFile}
echo "" >> ${ntpInfoFile}
echo "" >> ${ntpInfoFile}

cat ${ntpInfoFile}

# Decide what to do with the  current default time servers
read -e -p "Do you want to delete the current NTP servers (y/n) :: " removeServers

sed '/^server/ d' /etc/chrony.conf > ${chronyTemp}

# Declare ntpServer array
declare -a ntpServer
read -e -p "Enter NTP Server(s) IP/DNS for this machine (separated from each other by a space) :: " -a ntpServer
element_count=${#ntpServer[@]}
index=0
echo "" > ${newNtp}
echo "# Time Servers" >> ${newNtp}
if [ "X${removeServers}" = "Xn" ]
then
  grep "^server" /etc/chrony.conf >> ${newNtp}
fi

while [ "$index" -lt "$element_count" ]
do    # List all the elements in the array.
  let "ntpNumber = $index + 1"
  echo "server ${ntpServer[$index]} iburst" >> ${newNtp}
  let "index = $index + 1"
done

cat ${newNtp} >> ${chronyTemp}
rm -rf ${ntpInfoFile}

# Set timezone on local server
read -e -p "Do you want to change the Timezone (y/n) :: " timeZone
if [ "X${timeZone}" = "Xy" ]
then
  echo ""
  echo "If you are unsure of the timezone, exit this script and run the following command to locate the proper timezone:"
  echo "--------------------------"
  echo "timedatectl list-timezones"
  echo "--------------------------"
  read -e -p "What timezone (America/New_York) :: " newTimeZone
  echo ""
fi

read -e -p "Are these settings correct (y/n) :: " changeTime
if [ "X${changeTime}" = "Xy" ]
then
  mv ${chronyTemp} /etc/chrony.conf
  if [ "X${timeZone}" == "Xy" ]
  then
    timedatectl set-timezone ${newTimeZone}
  fi
  systemctl restart chronyd
fi

echo ""
echo "================="
echo "New NTP Servers :"
echo "================="
timedatectl status
echo ""

# Do a little cleanup
rm -rf ${ntpInfoFile} ${newNtp}
