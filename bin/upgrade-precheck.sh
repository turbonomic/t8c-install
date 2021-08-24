#!/bin/bash
#Upgrade pre-check script - Aug 27, 2021
echo " "
RED=`tput setaf 1`
WHITE=`tput setaf 7`
GREEN=`tput setaf 2`
BLUE=`tput setaf 4`
YELLOW=`tput setaf 3`
NC=`tput sgr0` # No Color
echo "${GREEN}Starting Upgrade Pre-check..."
echo " "
echo "${WHITE}Checking for free disk space..."
if [[ $(df | egrep -v "overlay|shm" | grep "/var$" | awk {'print $4'}) > 15728640 ]]; then
    df -h | egrep -v "overlay|shm"
    echo "${GREEN}PASSED - There's more than 15GB free disk space in /var to proceed with the upgrade"
    echo "${WHITE}***************************"
else
    df -h | egrep -v "overlay|shm"
    echo "${WHITE}***************************"
    echo "${RED}FAILED - /var has less than 15GB free - disk space will need to be cleared up before upgrading"
    echo "${WHITE}***************************"
    echo " "
    echo "${WHITE}Reclaimable space list below - By deleting un-used docker images${WHITE}"
    sudo docker system df
    echo "${WHITE}To reclaim space from un-used docker images above you need to confirm the previous version of Turbonomic images installed"
    echo "Run the command ${YELLOW}'sudo docker images | grep turbonomic/auth'${WHITE} to find the previous versions"
    echo "Run the command ${YELLOW}'for i in \`sudo docker images | grep 7.22.0 | awk '{print $3}'\`; do sudo docker rmi \$i;done'${WHITE} replacing ${YELLOW}'7.22.0'${YELLOW} with the old previous versions of the docker images installed to be removed to clear up the required disk space"
    echo "${WHITE}***************************"
fi
echo " "
read -p "${GREEN}Are you using a proxy to connect to the internet on this Turbonomic instance (y/n)? " CONT
if [[ "$CONT" =~ ^([yY][eE][sS]|[yY])$ ]]
then
    read -p "${WHITE}What is the proxy name or IP and port you use?....example https://proxy.server.com:8080 " P_NAME_PORT
    echo " "
    echo "${WHITE}Checking endpoints for ONLINE upgrade ONLY using proxy provided..."
    if [[ $(curl --proxy $P_NAME_PORT https://index.docker.io --max-time 30 -s -o /dev/null -w "%{http_code}") != @(000|407|502) ]]; then echo "${GREEN}SUCCESSFULLY reached index.docker.io"; else echo "${RED}CANNOT REACH index.docker.io - DO NOT PROCEED WITH ONLINE UPGRADE UNTIL THIS IS RESOLVED"; fi
    if [[ $(curl --proxy $P_NAME_PORT auth.docker.io --max-time 30 -s -o /dev/null -w "%{http_code}") != @(000|407|502) ]]; then echo "${GREEN}SUCCESSFULLY reached auth.docker.io"; else echo "${RED}CANNOT REACH auth.docker.io - DO NOT PROCEED WITH ONLINE UPGRADE UNTIL THIS IS RESOLVED"; fi
    if [[ $(curl --proxy $P_NAME_PORT https://registry-1.docker.io --max-time 30 -s -o /dev/null -w "%{http_code}") != @(000|407|502) ]]; then echo "${GREEN}SUCCESSFULLY reached registry-1.docker.io"; else echo "${RED}CANNOT REACH registry-1.docker.io - DO NOT PROCEED WITH ONLINE UPGRADE UNTIL THIS IS RESOLVED"; fi
    if [[ $(curl --proxy $P_NAME_PORT production.cloudflare.docker.com --max-time 30 -s -o /dev/null -w "%{http_code}") != @(000|407|502) ]]; then  echo "${GREEN}SUCCESSFULLY reached production.cloudflare.docker.com"; else echo "${RED}CANNOT REACH production.cloudflare.docker.com - DO NOT PROCEED WITH ONLINE UPGRADE UNTIL THIS IS RESOLVED"; fi
    if [[ $(curl --proxy $P_NAME_PORT https://raw.githubusercontent.com --max-time 30 -s -o /dev/null -w "%{http_code}") != @(000|407|502) ]]; then echo "${GREEN}SUCCESSFULLY reached raw.githubusercontent.com"; else echo "${RED}CANNOT REACH raw.githubusercontent.com - DO NOT PROCEED WITH ONLINE UPGRADE UNTIL THIS IS RESOLVED"; fi
    if [[ $(curl --proxy $P_NAME_PORT https://github.com --max-time 30 -s -o /dev/null -w "%{http_code}") != @(000|407|502) ]]; then echo "${GREEN}SUCCESSFULLY reached github.com"; else echo "${RED}CANNOT REACH github.com - DO NOT PROCEED WITH ONLINE UPGRADE UNTIL THIS IS RESOLVED"; fi
    if [[ $(curl --proxy $P_NAME_PORT https://download.vmturbo.com/appliance/download/updates/8.2.0/onlineUpgrade.sh --max-time 30 -s -o /dev/null -w "%{http_code}") != @(000|407|502) ]]; then echo "${GREEN}SUCCESSFULLY reached download.vmturbo.com"; else echo "${RED}CANNOT REACH download.vmturbo.com - DO NOT PROCEED WITH ONLINE UPGRADE UNTIL THIS IS RESOLVED"; fi
    if [[ $(curl --proxy $P_NAME_PORT https://yum.mariadb.org --max-time 30 -s -o /dev/null -w "%{http_code}") != @(000|407|502) ]]; then echo "${GREEN}SUCCESSFULLY reached https://yum.mariadb.org"; else echo "${RED}CANNOT REACH https://yum.mariadb.org - DO NOT PROCEED WITH ONLINE UPGRADE UNTIL THIS IS RESOLVED"; fi
    if [[ $(curl --proxy $P_NAME_PORT https://packagecloud.io --max-time 30 -s -o /dev/null -w "%{http_code}") != @(000|407|502) ]]; then echo "${GREEN}SUCCESSFULLY reached https://packagecloud.io"; else echo "${RED}CANNOT REACH https://packagecloud.io - DO NOT PROCEED WITH ONLINE UPGRADE UNTIL THIS IS RESOLVED"; fi
    if [[ $(curl --proxy $P_NAME_PORT https://download.postgresql.org --max-time 30 -s -o /dev/null -w "%{http_code}") != @(000|407|502) ]]; then echo "${GREEN}SUCCESSFULLY reached https://download.postgresql.org"; else echo "${RED}CANNOT REACH https://download.postgresql.org - DO NOT PROCEED WITH ONLINE UPGRADE UNTIL THIS IS RESOLVED"; fi
    if [[ $(curl --proxy $P_NAME_PORT https://yum.postgresql.org --max-time 30 -s -o /dev/null -w "%{http_code}") != @(000|407|502) ]]; then echo "${GREEN}SUCCESSFULLY reached https://yum.postgresql.org"; else echo "${RED}CANNOT REACH https://yum.postgresql.org - DO NOT PROCEED WITH ONLINE UPGRADE UNTIL THIS IS RESOLVED"; fi
    echo "${WHITE}****************************"
else
    echo "${WHITE}Checking endpoints for ONLINE upgrade ONLY..."
    if [[ $(curl https://index.docker.io --max-time 30 -s -o /dev/null -w "%{http_code}") != @(000|407|502) ]]; then echo "${GREEN}SUCCESSFULLY reached index.docker.io"; else echo "${RED}CANNOT REACH index.docker.io - DO NOT PROCEED WITH ONLINE UPGRADE UNTIL THIS IS RESOLVED"; fi
    if [[ $(curl auth.docker.io --max-time 30 -s -o /dev/null -w "%{http_code}") != @(000|407|502) ]]; then echo "${GREEN}SUCCESSFULLY reached auth.docker.io"; else echo "${RED}CANNOT REACH auth.docker.io - DO NOT PROCEED WITH ONLINE UPGRADE UNTIL THIS IS RESOLVED"; fi
    if [[ $(curl https://registry-1.docker.io --max-time 30 -s -o /dev/null -w "%{http_code}") != @(000|407|502) ]]; then echo "${GREEN}SUCCESSFULLY reached registry-1.docker.io"; else echo "${RED}CANNOT REACH registry-1.docker.io - DO NOT PROCEED WITH ONLINE UPGRADE UNTIL THIS IS RESOLVED"; fi
    if [[ $(curl production.cloudflare.docker.com --max-time 30 -s -o /dev/null -w "%{http_code}") != @(000|407|502) ]]; then echo "${GREEN}SUCCESSFULLY reached production.cloudflare.docker.com"; else echo "${RED}CANNOT REACH production.cloudflare.docker.com - DO NOT PROCEED WITH ONLINE UPGRADE UNTIL THIS IS RESOLVED"; fi
    if [[ $(curl https://raw.githubusercontent.com --max-time 30 -s -o /dev/null -w "%{http_code}") != @(000|407|502) ]]; then echo "${GREEN}SUCCESSFULLY reached raw.githubusercontent.com"; else echo "${RED}CANNOT REACH raw.githubusercontent.com - DO NOT PROCEED WITH ONLINE UPGRADE UNTIL THIS IS RESOLVED"; fi
    if [[ $(curl https://github.com --max-time 30 -s -o /dev/null -w "%{http_code}") != @(000|407|502) ]]; then echo "${GREEN}SUCCESSFULLY reached github.com"; else echo "${RED}CANNOT REACH github.com - DO NOT PROCEED WITH ONLINE UPGRADE UNTIL THIS IS RESOLVED"; fi
    if [[ $(curl https://download.vmturbo.com/appliance/download/updates/8.2.0/onlineUpgrade.sh --max-time 30 -s -o /dev/null -w "%{http_code}") != @(000|407|502) ]]; then echo "${GREEN}SUCCESSFULLY reached download.vmturbo.com"; else echo "${RED}CANNOT REACH download.vmturbo.com - DO NOT PROCEED WITH ONLINE UPGRADE UNTIL THIS IS RESOLVED"; fi
    if [[ $(curl https://yum.mariadb.org --max-time 30 -s -o /dev/null -w "%{http_code}") != @(000|407|502) ]]; then echo "${GREEN}SUCCESSFULLY reached https://yum.mariadb.org"; else echo "${RED}CANNOT REACH https://yum.mariadb.org - DO NOT PROCEED WITH ONLINE UPGRADE UNTIL THIS IS RESOLVED"; fi
    if [[ $(curl https://packagecloud.io --max-time 30 -s -o /dev/null -w "%{http_code}") != @(000|407|502) ]]; then echo "${GREEN}SUCCESSFULLY reached https://packagecloud.io"; else echo "${RED}CANNOT REACH https://packagecloud.io - DO NOT PROCEED WITH ONLINE UPGRADE UNTIL THIS IS RESOLVED"; fi
    if [[ $(curl https://download.postgresql.org --max-time 30 -s -o /dev/null -w "%{http_code}") != @(000|407|502) ]]; then echo "${GREEN}SUCCESSFULLY reached https://download.postgresql.org"; else echo "${RED}CANNOT REACH https://download.postgresql.org - DO NOT PROCEED WITH ONLINE UPGRADE UNTIL THIS IS RESOLVED"; fi
    if [[ $(curl https://yum.postgresql.org --max-time 30 -s -o /dev/null -w "%{http_code}") != @(000|407|502) ]]; then echo "${GREEN}SUCCESSFULLY reached https://yum.postgresql.org"; else echo "${RED}CANNOT REACH https://yum.postgresql.org - DO NOT PROCEED WITH ONLINE UPGRADE UNTIL THIS IS RESOLVED"; fi
    echo "${WHITE}****************************"
fi

echo " "
echo "Checking MariaDB status..."
echo "${GREEN}Checking if the MariaDB service is running...${WHITE}"
MSTATUS="$(systemctl is-active mariadb)"
case ${MSTATUS} in 
        active)
                echo "${GREEN}MariaDB service is running"
                echo "${WHITE}Checking MariaDB version"
                MVERSION=$(systemctl list-units --all -t service --full --no-legend "mariadb.service" | awk {'print $6'})
                # Compare version (if 10.5.9 is the output, that means the version is either equals or above this)
                VERSION_COMPARE=$(echo -e "10.5.9\n${MVERSION}" | sort -V | head -n1)
                if [[ ${VERSION_COMPARE} = "10.5.9" ]]; then
                    echo "${GREEN}PASSED - MariaDB checks"
                else                    
                    echo "${RED}The version of MariaDB is below version 10.5.9 you will need to upgrade it post Turbonomic upgrade following the steps in the install guide"
                    echo "${RED}FAILED - MariaDB checks"
                fi
                ;;
        unknown)
                echo "${WHITE}MariaDB service is not installed, precheck skipped"
                echo "${GREEN}PASSED - MariaDB checks"
                ;;
        *)
                echo "${RED}MariaDB service is not running....please resolve before upgrading"
                echo "${RED}FAILED - MariaDB checks"
                ;;
esac
echo "${WHITE}Checking if the Kubernetes service is running..."
CSTATUS="$(systemctl is-active kubelet)"
if [ "${CSTATUS}" = "active" ]; then
    echo "${GREEN}PASSED - Kubernetes service is running..."
else 
    echo "${RED}FAILED - Kubernetes service is not running....please resolve before upgrading"  
fi
#sudo systemctl status kubelet | grep Active
echo "${WHITE}****************************"
echo " "
echo "Checking for expired Kubernetes certificates..."
kubeVersion=$(/usr/local/bin/kubectl version | awk '{print $4}' | head -1 | awk -F: '{print $2}' | sed 's/"//g' | sed 's/,//g')
if [[ $kubeVersion -ge 20 ]]; then
    sudo /usr/local/bin/kubeadm certs check-expiration
elif [[ $kubeVersion -ge 15 ]]; then
    sudo /usr/local/bin/kubeadm alpha certs check-expiration
else
    sudo find /etc/kubernetes/pki/ -type f -name "*.crt" -print|egrep -v 'ca.crt$'|xargs -L 1 -t  -i bash -c 'openssl x509  -noout -text -in {}|grep After'
fi
echo "${YELLOW}Please validate the EXPIRES dates above, ${RED}if the EXPIRES dates listed above is before current date please run the script kubeNodeCertUpdate.sh in /opt/local/bin to renew the expired certs before upgrading"
echo "${WHITE}*****************************"
echo " "
echo "Checking if root password is expired or set to expire..."
echo "${GREEN}root account details below${WHITE}"
sudo chage -l root
echo "${YELLOW}Please validate the expiry dates above, ${RED}if expired or not set please set/reset the password before proceeding"
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
echo "${YELLOW}Please validate NTP, TIME and DATE configuration above if it is required, ${RED}if not enabled or correct and it is required please resolve by reviewing the Install Guide for steps to Sync Time"
echo "${WHITE}*****************************"
echo " "
echo "${GREEN}Checking for any Turbonomic pods not ready and running...${WHITE}"
if [ -f "/opt/turbonomic/kubernetes/yaml/persistent-volumes/local-storage-pv.yaml" ]; then
    gluster_enabled=false
    kubectl get pod -n turbonomic | grep -Pv '\s+([1-9]+)\/\1\s+' | grep -v "NAME"
else
    gluster_enabled=true
    kubectl get pod -n turbonomic | grep -Pv '\s+([1-9]+)\/\1\s+' | grep -v "NAME"
    kubectl get pod -n default | grep -Pv '\s+([1-9]+)\/\1\s+' | grep -v "NAME"
fi
echo "${YELLOW}Please resolve issues with the pods listed above (if any), ${RED}if you cannot resolve on your own **please contact support**"
echo "${WHITE}*****************************"
echo " "
echo "${YELLOW}Please take time to review and resolve any issues above before proceeding with the upgrade, ${RED}if you cannot resolve **please contact support**"
echo " "
echo "${GREEN}End of Upgrade Pre-Check${WHITE}"
