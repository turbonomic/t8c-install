#!/bin/bash
#Upgrade pre-check script
echo " "
RED=`tput setaf 1`
WHITE=`tput setaf 7`
GREEN=`tput setaf 2`
BLUE=`tput setaf 4`
NC=`tput sgr0` # No Color
echo "${GREEN}Starting Upgrade Pre-check..."
echo " "
echo "${WHITE}Checking for free disk space..."
df -h | egrep -v "overlay|shm"
echo "${GREEN}Please verify disk space above - ${RED}if any volumes over 80% used - **please contact support**"
echo "${WHITE}***************************"
echo " "
echo "${WHITE}Checking endpoints for ONLINE upgrade ONLY..."
curl index.docker.io --max-time 3 -s -f -o /dev/null && echo "${GREEN}SUCCESSFULLY reached index.docker.io" || echo "${RED}CANNOT REACH index.docker.io - DO NOT PROCEED WITH ONLINE UPGRADE UNTIL THIS IS RESOLVED"
curl auth.docker.io --max-time 3 -s -f -o /dev/null && echo "${GREEN}SUCCESSFULLY reached auth.docker.io" || echo "${RED}CANNOT REACH auth.docker.io - DO NOT PROCEED WITH ONLINE UPGRADE UNTIL THIS IS RESOLVED"
curl registry-1.docker.io --max-time 3 -s -f -o /dev/null && echo "${GREEN}SUCCESSFULLY reached registry-1.docker.io" || echo "${RED}CANNOT REACH registry-1.docker.io - DO NOT PROCEED WITH ONLINE UPGRADE UNTIL THIS IS RESOLVED"
curl production.cloudflare.docker.com --max-time 3 -s -f -o /dev/null && echo "${GREEN}SUCCESSFULLY reached production.cloudflare.docker.com" || echo "${RED}CANNOT REACH production.cloudflare.docker.com - DO NOT PROCEED WITH ONLINE UPGRADE UNTIL THIS IS RESOLVED"
curl raw.githubusercontent.com --max-time 3 -s -f -o /dev/null && echo "${GREEN}SUCCESSFULLY reached raw.githubusercontent.com" || echo "${RED}CANNOT REACH raw.githubusercontent.com - DO NOT PROCEED WITH ONLINE UPGRADE UNTIL THIS IS RESOLVED"
curl github.com --max-time 3 -s -f -o /dev/null && echo "${GREEN}SUCCESSFULLY reached github.com" || echo "${RED}CANNOT REACH github.com - DO NOT PROCEED WITH ONLINE UPGRADE UNTIL THIS IS RESOLVED"
curl https://download.vmturbo.com/appliance/download/updates/8.1.4/onlineUpgrade.sh --max-time 3 -s -f -o /dev/null && echo "${GREEN}SUCCESSFULLY reached download.vmturbo.com" || echo "${RED}CANNOT REACH download.vmturbo.com - DO NOT PROCEED WITH ONLINE UPGRADE UNTIL THIS IS RESOLVED"
curl https://yum.mariadb.org --max-time 3 -s -f -o /dev/null && echo "${GREEN}SUCCESSFULLY reached https://yum.mariadb.org" || echo "${RED}CANNOT REACH https://yum.mariadb.org - DO NOT PROCEED WITH ONLINE UPGRADE UNTIL THIS IS RESOLVED"
curl https://packagecloud.io --max-time 3 -s -f -o /dev/null && echo "${GREEN}SUCCESSFULLY reached https://packagecloud.io" || echo "${RED}CANNOT REACH https://packagecloud.io - DO NOT PROCEED WITH ONLINE UPGRADE UNTIL THIS IS RESOLVED"
curl https://download.postgresql.org --max-time 3 -s -f -o /dev/null && echo "${GREEN}SUCCESSFULLY reached https://download.postgresql.org" || echo "${RED}CANNOT REACH https://download.postgresql.org - DO NOT PROCEED WITH ONLINE UPGRADE UNTIL THIS IS RESOLVED"
echo "${WHITE}****************************"
echo " "
echo "Checking MariaDB status..."
echo "${GREEN}Checking if the MariaDB service is running...${WHITE}"
sudo systemctl status mariadb | grep Active
echo "${GREEN}Checking if the Kubernetes service is running...${WHITE}"
sudo systemctl status kubelet | grep Active
echo "${GREEN}Please ensure the services above are running, ${RED}if they are not please resolve or **please contact support**"
echo "${WHITE}****************************"
echo " "
echo "Checking for expired Kubernetes certificates..."
echo "${GREEN}Checking apiserver-kubelet-client.crt file expiry date...${WHITE}"
openssl x509 -noout -enddate -in /etc/kubernetes/ssl/apiserver-kubelet-client.crt
echo "${GREEN}Checking apiserver.crt file expiry date...${WHITE}"
openssl x509 -noout -enddate -in /etc/kubernetes/ssl/apiserver.crt
echo "${GREEN}Checking front-proxy-client.crt file expiry date...${WHITE}"
openssl x509 -noout -enddate -in /etc/kubernetes/ssl/front-proxy-client.crt
echo "${GREEN}Please validate the expiry dates above, ${RED}if expired or close to expiry **please contact support**"
echo "${WHITE}*****************************"
echo " "
echo "Checking if root password is expired or set to expire..."
echo "${GREEN}root account details below${WHITE}"
sudo chage -l root
echo "${GREEN}Please validate the expiry dates above, ${RED}if expired or close to expiry **please contact support**"
echo "${WHITE}*****************************"
echo " "
echo "${GREEN}Checking if NTP is enabled for timesync...${WHITE}"
timedatectl | grep "NTP enabled"
echo "${GREEN}Checking if NTP is synchronized for timesync...${WHITE}"
timedatectl | grep "NTP sync"
echo "${GREEN}Checking if Chronyd is running for NTP timesync...${WHITE}"
sudo systemctl status chronyd | grep Active
echo "${GREEN}Checking list of NTP servers being used for timesync (if enabled and running)...${WHITE}"
cat /etc/chrony.conf | grep server
echo "${GREEN}Current date, time and timezone configured (default is UTC time)...${WHITE}"
date
echo "${GREEN}Please validate NTP, TIME and DATE configuration above, ${RED}if not correct please resolve or **please contact support**"
echo "${WHITE}*****************************"
echo " "
echo "${GREEN}Checking for any Turbonomic pods not ready and running...${WHITE}"
kubectl get pod -n turbonomic | grep -Pv '\s+([1-9]+)\/\1\s+' | grep -v "NAME"
kubectl get pod -n default | grep -Pv '\s+([1-9]+)\/\1\s+' | grep -v "NAME"
echo "${GREEN}Please resolve issues with the pods listed above (if any), ${RED}if you cannot resolve **please contact support**"
echo "${WHITE}*****************************"
echo " "
echo "${GREEN}Please take time to review and resolve any issues above before proceeding with the upgrade, ${RED}if you cannot resolve **please contact support**"
echo " "
echo "${GREEN}End of Upgrade Pre-Check${WHITE}"
