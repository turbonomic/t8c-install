#!/bin/bash
#Upgrade pre-check script - September 29, 2021
#Author: CS
echo " "
RED=`tput setaf 1`
WHITE=`tput setaf 7`
GREEN=`tput setaf 2`
BLUE=`tput setaf 4`
YELLOW=`tput setaf 3`
NC=`tput sgr0` # No Color

VERBOSE=0
ECC=0 # Endpoints connectivity checks details

# Reset terminal on exit not to mess with colors
trap 'tput sgr0' EXIT

usage () {
   echo "v2.06"
   echo ""
   echo "Usage:"
   echo ""
   echo "   upgrade-precheck.sh [-v] [-c] [-h]"
   echo ""
   echo "   Arguments list"
   echo "      -v: turn on verbose mode"
   echo "      -c: show details on endpoints connectivity checks"
   echo "      -h: this help"
   echo ""
 
   exit 1
}

check_space(){
    echo "${WHITE}****************************"
    echo "Checking for free disk space..."
    VARSPACE=$(df | egrep -v "overlay|shm")
    if [[ ${VERBOSE} = 1 ]]; then
        df -h | egrep -v "overlay|shm"
        echo " "
    fi
    if [[ $(printf %s "${VARSPACE}" | grep "/var$" | awk {'print $4'}) > 15728640 ]]; then
        if [[ ${VERBOSE} = 1 ]]; then
            echo "${GREEN}There's enough disk space in /var to proceed with the upgrade."
        fi
        echo "${GREEN}Disk space check PASSED"
    else
        if [[ ${VERBOSE} = 1 ]]; then
            echo "${RED}/var has less than 15GB free - if needed remove un-used docker images to clear enough space."
            echo "${WHITE}***************************"
            echo " "
            echo "${WHITE}Reclaimable space list below - By deleting un-used docker images${WHITE}"
            sudo docker system df
            echo "${WHITE}To reclaim space from un-used docker images above you need to confirm the previous version of Turbonomic images installed:"
            echo "Run the command ${YELLOW}'sudo docker images | grep turbonomic/auth'${WHITE} to find the previous versions."
            echo "Run the command ${YELLOW}'for i in \`sudo docker images | grep 8.1.0 | awk '{print \$3}'\`; do sudo docker rmi \$i;done'${WHITE} replacing ${YELLOW}'8.1.0'${YELLOW} with the old previous versions of the docker images installed to be removed to clear up the required disk space."
            echo "${WHITE}***************************"
        fi
        echo "${RED}Disk space checks FAILED"
    fi
    echo "${WHITE}****************************"
    #echo "${GREEN}Please verify disk space above - ${RED}ensure that /var has at least 15GB free - if not please remove un-used docker images to clear enough space"
}

check_internet(){
    echo "${WHITE}****************************"
    echo "${WHITE}Checking endpoints connectivity for ONLINE upgrade ONLY..."
    URL_LIST=( https://index.docker.io https://auth.docker.io https://registry-1.docker.io https://production.cloudflare.docker.com https://raw.githubusercontent.com https://github.com https://download.vmturbo.com/appliance/download/updates/8.3.2/onlineUpgrade.sh https://yum.mariadb.org https://packagecloud.io https://download.postgresql.org https://yum.postgresql.org )
    NOT_REACHABLE_LIST=()
    read -p "${GREEN}Are you using a proxy to connect to the internet on this Turbonomic instance (y/n)? " CONT
    if [[ "${CONT}" =~ ^([yY][eE][sS]|[yY])$ ]]
    then
        read -p "${WHITE}What is the proxy name or IP and port you use?....example https://proxy.server.com:8443 " P_NAME_PORT
        echo " "
        echo "${WHITE}Checking endpoints connectivity for ONLINE upgrade ONLY using proxy provided..."
        for URL in "${URL_LIST[@]}"
        do
            if [[ $(curl --proxy $P_NAME_PORT ${URL} --max-time 10 -s -o /dev/null -w "%{http_code}") != @(000|407|502) ]]; then
                if [[ ${VERBOSE} = 1 || ${ECC} = 1 ]]; then
                    echo "${GREEN}Successfully reached ${URL}"
                fi
            else
                NOT_REACHABLE_LIST+=( $URL )
                if [[ ${VERBOSE} = 1 || ${ECC} = 1 ]]; then
                    echo "${RED}Cannot reach ${URL} - Do not proceed with online upgrade until this is resolved."
                    echo "${RED}Please work with your IT administrators to make sure this system has access to this URL."
                fi
            fi
        done
    else
        for URL in "${URL_LIST[@]}"
        do
            if [[ $(curl ${URL} --max-time 10 -s -o /dev/null -w "%{http_code}") != @(000|407|502) ]]; then
                if [[ ${VERBOSE} = 1 || ${ECC} = 1 ]]; then
                    echo "${GREEN}Successfully reached ${URL}"
                fi
            else
                NOT_REACHABLE_LIST+=( ${URL} )
                if [[ ${VERBOSE} = 1 || ${ECC} = 1 ]]; then
                    echo "${RED}Cannot reach ${URL} - Do not proceed with online upgrade until this is resolved."
                    echo "${RED}Please work with your IT administrators to make sure this system has access to this URL."
                fi
            fi
        done
    fi
    # final check
    if [[ ${#NOT_REACHABLE_LIST[@]} = 0 ]]; then
        echo "${GREEN}Endpoints connectivity checks PASSED"
    else
        echo "${RED}Endpoints connectivity checks FAILED"
        if [[ ${VERBOSE} = 1 || ${ECC} = 1 ]]; then
            echo "${WHITE}List of failing endpoints:"
            for URL in "${NOT_REACHABLE_LIST[@]}"
            do
                echo "${RED}${URL}"
            done
        fi
    fi
    echo "${WHITE}****************************"
}

check_database(){
    echo "${WHITE}****************************"
    echo "Checking MariaDB status and version..."
    echo "Checking if the MariaDB service is running..."
    MSTATUS=$(systemctl is-active mariadb)
    case ${MSTATUS} in 
        active)
                if [[ ${VERBOSE} = 1 ]]; then
                    echo "${GREEN}MariaDB service is running."
                    echo "${WHITE}Checking MariaDB version"
                fi
                MVERSION=$(systemctl list-units --all -t service --full --no-legend "mariadb.service" | awk {'print $6'})
                # Compare version (if 10.5.9 is the output, that means the version is either equals or above this)
                VERSION_COMPARE=$(echo -e "10.5.9\n${MVERSION}" | sort -V | head -n1)
                if [[ ${VERSION_COMPARE} = "10.5.9" ]]; then
                    echo "${GREEN}MariaDB checks PASSED"
                else                    
                    if [[ ${VERBOSE} = 1 ]]; then
                        echo "${RED}The version of MariaDB is below version 10.5.9 you will also need to upgrade it post Turbonomic upgrade following the steps in the install guide."
                    fi
                    echo "${RED}MariaDB checks FAILED"
                fi
                ;;
        unknown)
                if [[ ${VERBOSE} = 1 ]]; then
                    echo "${WHITE}MariaDB service is not installed, precheck skipped."
                fi
                echo "${GREEN}MariaDB checks PASSED"
                ;;
        *)
                if [[ ${VERBOSE} = 1 ]]; then
                    echo "${RED}MariaDB service is not running....please resolve before upgrading."
                fi
                echo "${RED}MariaDB checks FAILED"
                ;;
    esac
    echo "${WHITE}****************************"
}

check_kubernetes_service(){
    echo "${WHITE}****************************"
    echo "Checking if the Kubernetes service is running..."
    CSTATUS=$(systemctl is-active kubelet)
    if [ "${CSTATUS}" = "active" ]; then
        if [[ ${VERBOSE} = 1 ]]; then
            echo "${GREEN}Kubernetes service is running."
        fi
        echo "${GREEN}Kubernetes service checks PASSED"
    else
        if [[ ${VERBOSE} = 1 ]]; then
            echo "${RED}Kubernetes service is not running. Please resolve before upgrading."
        fi
        echo "${RED}Kubernetes service checks FAILED"
    fi
    echo "${WHITE}****************************"
}

check_kubernetes_certs(){
    echo "${WHITE}****************************"
    echo "Checking for expired Kubernetes certificates..."
    echo "Checking all certs now..."
    EXPIRED_CERTS=()
    kubeVersion=$(/usr/local/bin/kubectl version | awk '{print $4}' | head -1 | awk -F: '{print $2}' | sed 's/"//g' | sed 's/,//g')
    if [[ $kubeVersion -ge 20 ]]; then
        CERT_OUTPUT=$(sudo /usr/local/bin/kubeadm certs check-expiration 2>/dev/null | sed -n '/CERTIFICATE/,/^CERTIFICATE AUTHORITY/{//!p;}')
        if [[ ${VERBOSE} = 1 ]]; then
            printf %s "${CERT_OUTPUT}"
            echo " " 
        fi
        printf %s "${CERT_OUTPUT}" |
        while IFS= read -r LINE; do
            CERT_DATE=$(echo ${LINE} | tr -s ' ' | cut -d ' ' -f 2-6 | xargs)
            CERT_EPOCH=$(date +%s -d "${CERT_DATE}")
            NOW_EPOCH=$(date +%s)
            # compare with today in epoch
            if [[ ${CERT_DATE} < ${NOW_EPOCH} ]]; then
                EXPIRED_CERTS+=( ${CERT} )
            fi
        done
    elif [[ $kubeVersion -ge 15 ]]; then
        CERT_OUTPUT=$(sudo /usr/local/bin/kubeadm alpha certs check-expiration 2>/dev/null | sed -n '/CERTIFICATE/,/^CERTIFICATE AUTHORITY/{//!p;}')
        if [[ ${VERBOSE} = 1 ]]; then
            printf %s "${CERT_OUTPUT}"
            echo " " 
        fi
        printf %s "${CERT_OUTPUT}" |
        while IFS= read -r LINE; do
            CERT_DATE=$(echo ${LINE} | tr -s ' ' | cut -d ' ' -f 2-6 | xargs)
            CERT_EPOCH=$(date +%s -d "${CERT_DATE}")
            NOW_EPOCH=$(date +%s)
            # compare with today in epoch
            if [[ ${CERT_DATE} < ${NOW_EPOCH} ]]; then
                EXPIRED_CERTS+=( ${CERT} )
            fi
        done
    else # For Kubernetes below version 15 - specific handling
        CERT_OUTPUT_VERBOSE=()
        for CERT in /etc/kubernetes/pki/*.crt
        do
            if ! [[ ${CERT} =~ "ca.crt" ]]; then
                CERT_OUTPUT=$(openssl x509 -noout -text -in ${CERT} 2>/dev/null | grep After | xargs)
                if [[ ${VERBOSE} = 1 ]]; then
                    printf %s "${CERT} - ${CERT_OUTPUT}"
                    echo " "
                fi
                CERT_OUTPUT_VERBOSE+=( ${CERT_OUTPUT} )
                CERT_DATE=$(printf %s "${CERT_OUTPUT}" | grep After | cut -d ':' -f 2- | xargs) # from that we get the date in a proper format without trailing space
                # convert $CERT_DATE in epoch
                CERT_EPOCH=$(date +%s -d "${CERT_DATE}")
                NOW_EPOCH=$(date +%s)
                # compare with today in epoch
                if [[ ${CERT_DATE} < ${NOW_EPOCH} ]]; then
                    EXPIRED_CERTS+=( ${CERT} )
                fi
            fi
        done
    fi
    # final check
    if [[ ${#EXPIRED_CERTS[@]} = 0 ]]; then
        echo "${GREEN}Certificate checks PASSED"
    else
        echo "${RED}Certificate checks FAILED"
        if [[ ${VERBOSE} = 1 ]]; then
            echo "${WHITE}List of expired certificates:"
            for CERT in "${EXPIRED_CERTS[@]}"
            do
                echo "${RED}${CERT}"
            done
            echo "${RED}Please run the script kubeNodeCertUpdate.sh in /opt/local/bin to renew the expired certs before upgrading."
        fi
    fi
    echo "${WHITE}****************************"
}

check_root_password(){
    echo "${WHITE}*****************************"
    echo "Checking if root password is expired or set to expire..."
    if [[ ${VERBOSE} = 1 ]]; then
        echo "Root account details below"
        sudo chage -l root
    fi
    ACCOUNT_EXPIRATION_DATE=$(sudo chage -l root | grep "Account expires" | cut -d ':' -f 2 | xargs)
    PASSWORD_EXPIRATION_DATE=$(sudo chage -l root | grep "Password expires" | cut -d ':' -f 2 | xargs)
    ERRORS=()
    case ${ACCOUNT_EXPIRATION_DATE} in 
        never)
            if [[ ${VERBOSE} = 1 ]]; then
                echo "${GREEN}Root account expiration checks PASSED"
            fi
            ;;
        *)
            ACCOUNT_EXPIRATION_EPOCH=$(date +%s -d "${ACCOUNT_EXPIRATION_DATE}")
            NOW_EPOCH=$(date +%s)
            # compare with today in epoch
            if [[ ${ACCOUNT_EXPIRATION_EPOCH} < ${NOW_EPOCH} ]]; then
                if [[ ${VERBOSE} = 1 ]]; then
                    echo "${RED}Root account is expired since ${ACCOUNT_EXPIRATION_DATE}. Please enable the account before upgrading."
                fi
                ERRORS+=( "Account Expired" )
            else
                if [[ ${VERBOSE} = 1 ]]; then
                    echo "${GREEN}Root account expiration checks PASSED"
                fi
            fi
            ;;
    esac
    case ${PASSWORD_EXPIRATION_DATE} in 
        never)
            if [[ ${VERBOSE} = 1 ]]; then
                echo "${GREEN}Root password expiration checks PASSED"
            fi
            ;;
        *)
            PASSWORD_EXPIRATION_EPOCH=$(date +%s -d "${PASSWORD_EXPIRATION_DATE}")
            NOW_EPOCH=$(date +%s)
            # compare with today in epoch
            if [[ ${PASSWORD_EXPIRATION_EPOCH} < ${NOW_EPOCH} ]]; then
                if [[ ${VERBOSE} = 1 ]]; then
                    echo "${RED}Root password is expired since ${PASSWORD_EXPIRATION_DATE}. Please renew the password before upgrading."
                fi
                ERRORS+=( "Password Expired" )
            else
                if [[ ${VERBOSE} = 1 ]]; then
                    echo "${GREEN}Root password expiration checks PASSED"
                fi
            fi
            ;;
    esac
    # final check
    if [[ ${#ERRORS[@]} = 0 ]]; then
        echo "${GREEN}Root account checks PASSED"
    else
        echo "${RED}Root account checks FAILED"
    fi
    echo "${WHITE}****************************"
}

check_time_and_date(){
    echo "${WHITE}****************************"
    echo "Checking time and date settings (NTP, Timezone...)"
    ERRORS=()
    TIMEDATECTL_OUTPUT=$(timedatectl)
    # Is NTP enabled?
    if [[ ${VERBOSE} = 1 ]]; then
        printf %s "${TIMEDATECTL_OUTPUT}"
        echo " "
        echo "${WHITE}Checking if NTP is enabled for timesync..."
    fi
    NTP_ENABLED=$(printf %s "${TIMEDATECTL_OUTPUT}" | grep "NTP enabled" | cut -d ':' -f 2 | xargs)
    if [[ ${NTP_ENABLED} != "yes" ]]; then
        if [[ ${VERBOSE} = 1 ]]; then
            echo "${RED}NTP is disabled."
        fi
        ERRORS+=( "NTP disabled" )
    else
        if [[ ${VERBOSE} = 1 ]]; then
            echo "${GREEN}NTP is enabled."
        fi
    fi
    # Is NTP sync?
    if [[ ${VERBOSE} = 1 ]]; then
        echo "${WHITE}Checking if NTP is synchronized for timesync..."
    fi
    NTP_SYNC=$(printf %s "${TIMEDATECTL_OUTPUT}" | grep "NTP synchronized" | cut -d ':' -f 2 | xargs)
    if [[ ${NTP_SYNC} != "yes" ]]; then
        if [[ ${VERBOSE} = 1 ]]; then
            echo "${RED}NTP is not synchronized."
        fi
        ERRORS+=( "NTP not synchronized" )
    else
        if [[ ${VERBOSE} = 1 ]]; then
            echo "${GREEN}NTP is synchronized."
        fi
    fi
    # Is chronyd running?
    CHRONYD_OUTPUT=$(sudo systemctl status chronyd 2>/dev/null)
    if [[ ${VERBOSE} = 1 ]]; then
        echo "${WHITE}Checking if Chronyd is running for NTP timesync..."
        printf %s "${CHRONYD_OUTPUT}"
        echo " "
    fi
    CHRONYD_RUN=$(printf %s "${CHRONYD_OUTPUT}" | grep Active | grep running)
    if [[ -z ${CHRONYD_RUN} ]]; then
        if [[ ${VERBOSE} = 1 ]]; then
            echo "${RED}Chronyd is not running."
        fi
        ERRORS+=( "Chronyd not running" )
    else
        if [[ ${VERBOSE} = 1 ]]; then
            echo "${GREEN}Chronyd is running."
        fi
    fi
    # Display list of NTP servers configured and displaying date for info
    if [[ ${VERBOSE} = 1 ]]; then
        echo "${WHITE}Displaying list of NTP servers being used for timesync (if enabled and running)..."
        cat /etc/chrony.conf | grep ^server
        echo "${WHITE}Current date, time and timezone configured (default is UTC time)..."
        date
    fi
    # final check
    if [[ ${#ERRORS[@]} = 0 ]]; then
        echo "${GREEN}Time and date settings checks PASSED"
    else
        echo "${RED}Time and date settings checks FAILED"
    fi
    echo "${WHITE}****************************"
}

check_turbonomic_pods(){
    echo "${WHITE}*****************************"
    echo "Checking for any Turbonomic pods not ready and running..."
    ERRORS=()
    if [ -f "/opt/turbonomic/kubernetes/yaml/persistent-volumes/local-storage-pv.yaml" ]; then
        # Gluster is disabled
        KUBE_OUTPUT=$(kubectl get pod -n turbonomic | grep -Pv '\s+([1-9]+)\/\1\s+' | grep -v "NAME")
        if [[ ${VERBOSE} = 1 ]]; then
            printf %s "${KUBE_OUTPUT}"
            echo " "
        fi
        if [[ -z ${KUBE_OUTPUT} ]]; then
            if [[ ${VERBOSE} = 1 ]]; then
                echo "${GREEN}All pods are running as expected."
            fi
            echo "${GREEN}Turbonomic pods checks PASSED"
        else
            if [[ ${VERBOSE} = 1 ]]; then
                echo "${RED}Some pods are not running as expected."
            fi
            echo "${RED}Turbonomic pods checks FAILED"
        fi
    else
        # Gluster is enabled
        KUBE_OUTPUT_TURBO=$(kubectl get pod -n turbonomic | grep -Pv '\s+([1-9]+)\/\1\s+' | grep -v "NAME")
        KUBE_OUTPUT_DEFAULT=$(kubectl get pod -n default | grep -Pv '\s+([1-9]+)\/\1\s+' | grep -v "NAME")
        if [[ ${VERBOSE} = 1 ]]; then
            printf %s "${KUBE_OUTPUT_TURBO}"
            echo " "
            printf %s "${KUBE_OUTPUT_DEFAULT}"
            echo " "
        fi
        if [[ -z ${KUBE_OUTPUT_TURBO} && -z ${KUBE_OUTPUT_DEFAULT} ]]; then
            if [[ ${VERBOSE} = 1 ]]; then
                echo "${GREEN}All pods are running as expected."
            fi
            echo "${GREEN}Turbonomic pods checks PASSED"
        else
            if [[ ${VERBOSE} = 1 ]]; then
                echo "${RED}Some pods are not running as expected."
            fi
            echo "${RED}Turbonomic pods checks FAILED"
        fi
    fi
    echo "${WHITE}*****************************"
}

# Main script
# Check for arguments
while getopts "vch" ARGUMENTS
do
   case ${ARGUMENTS} in
      v)
         echo "${WHITE}Verbose Mode ON"
         echo " "
         VERBOSE=1
         ;;
      c)
         echo "${WHITE}Details for endpoints connectivity checks ON"
         echo " "
         ECC=1
         ;;
      h)
         usage
         ;;
   esac
done
echo "Starting Upgrade Pre-check..."
echo " "
check_space
echo " "
echo "${WHITE}*****************************"
read -p "${GREEN}Are you going to be performing an ONLINE upgrade of the Turbonomic instance (y/n)? " ONL
echo " "
if [[ "${ONL}" =~ ^([yY][eE][sS]|[yY])$ ]]; then
   check_internet    
fi
echo " "
check_database
echo " "
check_kubernetes_service
echo " "
check_kubernetes_certs
echo " "
check_root_password
echo " "
check_time_and_date
echo " "
check_turbonomic_pods
echo " "
if [[ ${VERBOSE} = 1 ]]; then
   echo "${WHITE}Please review and resolve any FAILED issues above before proceeding with the upgrade, if you cannot resolve **please contact Turbonomic support**"
else
   echo "${WHITE}Please review and resolve any FAILED issues above before proceeding with the upgrade, if you need more details of any failed items re-run the script with the -v switch, if you cannot resolve **please contact Turbonomic support**"
fi
echo " "
echo "End of Upgrade Pre-Check"

