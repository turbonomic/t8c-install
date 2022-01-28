#!/bin/bash
#Upgrade pre-check script - January 19, 2022
#Author: CS/JS
echo " "
RED=`tput setaf 1`
WHITE=`tput setaf 7`
GREEN=`tput setaf 2`
BLUE=`tput setaf 4`
YELLOW=`tput setaf 3`
NC=`tput sgr0` # No Color

MAX_TIME=10
VERBOSE=0
ECC=0 # Endpoints connectivity checks details
SUMMARY_TABLE=0 # Summary table status
SUMMARY=() # Summary table

# Reset terminal on exit not to mess with colors
trap 'tput sgr0' EXIT

usage () {
   echo ""
   echo "Upgrade Precheck Script"
   echo "v2.22"
   echo ""
   echo "Usage:"
   echo ""
   echo "   upgrade-precheck.sh [-v] [-c] [-t <time_in_seconds>] [-s] [-h]"
   echo ""
   echo "   Arguments list"
   echo "      -v: turn on verbose mode"
   echo "      -c: show details on endpoints connectivity checks"
   echo "      -t <time_in_seconds>: change timeout for endpoints connectivity checks to <time_in_seconds> seconds (default is 10 seconds)"
   echo "      -s: display a summary table at the end of all checks"
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
    if [[ $(printf '%s\n' "${VARSPACE}" | grep "/var$" | awk {'print $4'}) -ge 15728640 ]]; then
        if [[ ${VERBOSE} = 1 ]]; then
            echo "${GREEN}There's enough disk space in /var to proceed with the upgrade."
        fi
        echo "${GREEN}Disk space check PASSED"
        SUMMARY+=( "${WHITE}Disk space check | ${GREEN}PASSED" )
    else
        if [[ ${VERBOSE} = 1 ]]; then
            echo "${RED}/var has less than 15GB free - if needed remove un-used docker images to clear enough space."
            echo "${WHITE}***************************"
            echo " "
            echo "${WHITE}Reclaimable space list below - By deleting un-used docker images${WHITE}"
            sudo docker system df
            echo "${WHITE}To reclaim space from un-used docker images above you need to confirm the previous version of Turbonomic images installed:"
            echo "Run the command ${YELLOW}'sudo docker images | grep turbonomic/auth'${WHITE} to find the previous versions."
            echo "Run the command ${YELLOW}'for i in \`sudo docker images | grep 8.3.0 | awk '{print \$3}'\`; do sudo docker rmi \$i;done'${WHITE} replacing ${YELLOW}'8.3.0'${YELLOW} with the old previous versions of the docker images installed to be removed to clear up the required disk space."
            echo "${WHITE}***************************"
        fi
        echo "${RED}Disk space checks FAILED"
        SUMMARY+=( "${WHITE}Disk space check | ${RED}FAILED" )
    fi
    echo "${WHITE}****************************"
}

check_internet(){
    echo "${WHITE}****************************"
    echo "${WHITE}Checking endpoints connectivity for ONLINE upgrade ONLY..."
    URL_LIST=( https://index.docker.io https://auth.docker.io https://registry-1.docker.io https://production.cloudflare.docker.com https://raw.githubusercontent.com https://github.com https://download.vmturbo.com/appliance/download/updates/8.4.2/onlineUpgrade.sh https://yum.mariadb.org https://packagecloud.io https://download.postgresql.org https://yum.postgresql.org )
    NOT_REACHABLE_LIST=()
    read -p "${GREEN}Are you using a proxy to connect to the internet on this Turbonomic instance (y/n)? " CONT
    if [[ "${CONT}" =~ ^([yY][eE][sS]|[yY])$ ]]
    then
        read -p "${WHITE}What is the proxy name or IP and port you use?....example https://proxy.server.com:8443 " P_NAME_PORT
        echo " "
        echo "${WHITE}Checking endpoints connectivity for ONLINE upgrade ONLY using proxy provided..."
        for URL in "${URL_LIST[@]}"
        do
            if [[ $(curl --proxy $P_NAME_PORT ${URL} --max-time ${MAX_TIME} -s -o /dev/null -w "%{http_code}") != @(000|407|502) ]]; then
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
            if [[ $(curl ${URL} --max-time ${MAX_TIME} -s -o /dev/null -w "%{http_code}") != @(000|407|502) ]]; then
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
        SUMMARY+=( "${WHITE}Endpoints connectivity checks | ${GREEN}PASSED" )
    else
        echo "${RED}Endpoints connectivity checks FAILED"
        SUMMARY+=( "${WHITE}Endpoints connectivity checks | ${RED}FAILED" )
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
                # Compare version (if 10.5.12 is the output, that means the version is either equals or above this)
                VERSION_COMPARE=$(echo -e "10.5.12\n${MVERSION}" | sort -V | head -n1)
                if [[ ${VERSION_COMPARE} = "10.5.12" ]]; then
                    echo "${GREEN}MariaDB checks PASSED"
                    SUMMARY+=( "${WHITE}MariaDB checks | ${GREEN}PASSED" )
                else                    
                    if [[ ${VERBOSE} = 1 ]]; then
                        echo "${RED}The version of MariaDB is below version 10.5.12 you will also need to upgrade it post Turbonomic upgrade following the steps in the install guide."
                    fi
                    echo "${RED}MariaDB version check FAILED"
                    SUMMARY+=( "${WHITE}MariaDB checks | ${RED}FAILED" )
                fi
                ;;
        unknown)
                if [[ ${VERBOSE} = 1 ]]; then
                    echo "${WHITE}MariaDB service is not installed, precheck skipped."
                fi
                echo "${GREEN}MariaDB checks PASSED"
                SUMMARY+=( "${WHITE}MariaDB checks | ${GREEN}PASSED" )
                ;;
        *)
                if [[ ${VERBOSE} = 1 ]]; then
                    echo "${RED}MariaDB service is not running....please resolve before upgrading."
                fi
                echo "${RED}MariaDB service check FAILED"
                SUMMARY+=( "${WHITE}MariaDB checks | ${RED}FAILED" )
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
        SUMMARY+=( "${WHITE}Kubernetes service checks | ${GREEN}PASSED" )
    else
        if [[ ${VERBOSE} = 1 ]]; then
            echo "${RED}Kubernetes service is not running. Please resolve before upgrading."
        fi
        echo "${RED}Kubernetes service checks FAILED"
        SUMMARY+=( "${WHITE}Kubernetes service checks | ${RED}FAILED" )
    fi
    echo "${WHITE}****************************"
}

check_kubernetes_certs(){
    echo "${WHITE}****************************"
    echo "Checking for expired Kubernetes certificates..."
    echo "Checking all certs now..."
    ERRORS=()
    EXPIRED_CERTS=()
    # Execute the command to check if kubectl is working
    /usr/local/bin/kubectl version | awk '{print $4}' | head -1 | awk -F: '{print $2}' | sed 's/"//g' | sed 's/,//g' > /dev/null
    # Grab return code
    KUBECTL_RC=${PIPESTATUS[0]}
    if [[ ${KUBECTL_RC} -eq 0 ]]; then # only if the kubectl command worked
    # As the command works, let's get the version
    kubeVersion=$(/usr/local/bin/kubectl version | awk '{print $4}' | head -1 | awk -F: '{print $2}' | sed 's/"//g' | sed 's/,//g')
        if [[ $kubeVersion -ge 20 ]]; then
            CERT_OUTPUT=$(sudo /usr/local/bin/kubeadm certs check-expiration 2>/dev/null | sed -n '/CERTIFICATE/,/^CERTIFICATE AUTHORITY/{//!p;}')
            if [[ ${VERBOSE} = 1 ]]; then
                printf '%s\n' "${CERT_OUTPUT}"
                echo " " 
            fi
            while IFS= read -r LINE; do
                if [[ ${LINE} =~ "MISSING" ]]; then # in some cases some certificates are !MISSING!
                    CERT_NAME=$(echo ${LINE} | sed 's/!MISSING! //g')
                    ERRORS+=( "A Kubernetes certificate is missing: ${CERT_NAME}." )
                else
                    CERT_DATE=$(echo ${LINE} | tr -s ' ' | cut -d ' ' -f 2-6 | xargs)
                    CERT_EPOCH=$(date +%s -d "${CERT_DATE}")
                    NOW_EPOCH=$(date +%s)
                    # compare with today in epoch
                    if [[ ${CERT_EPOCH} < ${NOW_EPOCH} ]]; then
                        EXPIRED_CERTS+=( ${CERT} )
                    fi    
                fi
            done <<< "${KUBE_OUTPUT_TURBO_FILTERED}"
        elif [[ $kubeVersion -ge 15 ]]; then
            CERT_OUTPUT=$(sudo /usr/local/bin/kubeadm alpha certs check-expiration 2>/dev/null | sed -n '/CERTIFICATE/,/^CERTIFICATE AUTHORITY/{//!p;}')
            if [[ ${VERBOSE} = 1 ]]; then
                printf '%s\n' "${CERT_OUTPUT}"
                echo " " 
            fi
            while IFS= read -r LINE; do
                if [[ ${LINE} =~ "MISSING" ]]; then # in some cases some certificates are !MISSING!
                    CERT_NAME=$(echo ${LINE} | sed 's/!MISSING! //g')
                    ERRORS+=( "A Kubernetes certificate is missing: ${CERT_NAME}." )
                else
                    CERT_DATE=$(echo ${LINE} | tr -s ' ' | cut -d ' ' -f 2-6 | xargs)
                    CERT_EPOCH=$(date +%s -d "${CERT_DATE}")
                    NOW_EPOCH=$(date +%s)
                    # compare with today in epoch
                    if [[ ${CERT_EPOCH} < ${NOW_EPOCH} ]]; then
                        EXPIRED_CERTS+=( ${CERT} )
                    fi
                fi
            done <<< "${CERT_OUTPUT}"
        elif [[ $kubeVersion -gt 0 && $kubeVersion -lt 15 ]]; then # For Kubernetes below version 15 - specific handling
            CERT_OUTPUT_VERBOSE=()
            for CERT in /etc/kubernetes/pki/*.crt
            do
                if ! [[ ${CERT} =~ "ca.crt" ]]; then
                    CERT_OUTPUT=$(openssl x509 -noout -text -in ${CERT} 2>/dev/null | grep After | xargs)
                    if [[ ${VERBOSE} = 1 ]]; then
                        printf '%s\n' "${CERT} - ${CERT_OUTPUT}"
                        echo " "
                    fi
                    CERT_OUTPUT_VERBOSE+=( ${CERT_OUTPUT} )
                    CERT_DATE=$(printf '%s\n' "${CERT_OUTPUT}" | grep After | cut -d ':' -f 2- | xargs) # from that we get the date in a proper format without trailing space
                    # convert $CERT_DATE in epoch
                    CERT_EPOCH=$(date +%s -d "${CERT_DATE}")
                    NOW_EPOCH=$(date +%s)
                    # compare with today in epoch
                    if [[ ${CERT_EPOCH} < ${NOW_EPOCH} ]]; then
                        EXPIRED_CERTS+=( ${CERT} )
                    fi
                fi
            done
        else # If for any other reason the version check didn't work (configuration messed up)
            ERRORS+=( "Kubernetes version parsing error." )
        fi
    else # kubectl command failed - cluster is messed up?
        ERRORS+=( "Kubectl command is failing." )
    fi
    # final check
    if [[ ${#EXPIRED_CERTS[@]} = 0 && ${#ERRORS[@]} = 0 ]]; then
        echo "${GREEN}Certificate checks PASSED"
        SUMMARY+=( "${WHITE}Certificate checks | ${GREEN}PASSED" )
    else
        echo "${RED}Certificate checks FAILED"
        SUMMARY+=( "${WHITE}Certificate checks | ${RED}FAILED" )
        if [[ ${VERBOSE} = 1 ]]; then
            if [[ ${#EXPIRED_CERTS[@]} != 0 ]]; then # in that case kubectl command worked but certificates are expired
                echo "${WHITE}List of expired certificates:"
                for CERT in "${EXPIRED_CERTS[@]}"
                do
                    echo "${RED}${CERT}"
                done
                echo "${RED}Please run the script kubeNodeCertUpdate.sh in /opt/local/bin to renew the expired certs before upgrading."
            elif [[ ${#ERRORS[@]} != 0 ]]; then # in that case kubectl command failed
                for MSG in "${ERRORS[@]}"
                do
                    echo "${RED}${MSG}"
                done
                echo "${RED}Please check the status of your Kubernetes cluster."
            fi
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
        SUMMARY+=( "${WHITE}Root account checks | ${GREEN}PASSED" )
    else
        echo "${RED}Root account checks FAILED"
        SUMMARY+=( "${WHITE}Root account checks | ${RED}FAILED" )
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
        printf '%s\n' "${TIMEDATECTL_OUTPUT}"
        echo " "
        echo "${WHITE}Checking if NTP is enabled for timesync..."
    fi
    NTP_ENABLED=$(printf '%s\n' "${TIMEDATECTL_OUTPUT}" | grep "NTP enabled" | cut -d ':' -f 2 | xargs)
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
    NTP_SYNC=$(printf '%s\n' "${TIMEDATECTL_OUTPUT}" | grep "NTP synchronized" | cut -d ':' -f 2 | xargs)
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
        printf '%s\n' "${CHRONYD_OUTPUT}"
        echo " "
    fi
    CHRONYD_RUN=$(printf '%s\n' "${CHRONYD_OUTPUT}" | grep Active | grep running)
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
        SUMMARY+=( "${WHITE}Time and date settings checks | ${GREEN}PASSED" )
    else
        echo "${RED}Time and date settings checks FAILED"
        SUMMARY+=( "${WHITE}Time and date settings checks | ${RED}FAILED" )
    fi
    echo "${WHITE}****************************"
}

check_turbonomic_pods(){
    echo "${WHITE}*****************************"
    echo "Checking for any Turbonomic pods not ready and running..."
    FAILING_PODS=()
    KUBECTL_TEST_COMMAND=$(kubectl version)
    KUBECTL_TEST=$?
    if [ -f "/opt/turbonomic/kubernetes/yaml/persistent-volumes/local-storage-pv.yaml" ]; then
        # Gluster is disabled
        KUBE_OUTPUT=$(kubectl get pods -n turbonomic | grep -v "NAME")
        KUBE_OUTPUT_FILTERED=$(kubectl get pods -n turbonomic | grep -Pv '\s+([1-9]+)\/\1\s+Running' | grep -v "NAME")
        if [[ ${KUBECTL_TEST} -eq 0 ]]; then # only if the kubectl command worked
            if [[ -z ${KUBE_OUTPUT_FILTERED} ]]; then
                if [[ ${VERBOSE} = 1 ]]; then
                    printf '%s\n' "${KUBE_OUTPUT}"
                    echo " "
                    echo "${GREEN}All pods are running as expected."
                fi
                echo "${GREEN}Turbonomic pods checks PASSED"
                SUMMARY+=( "${WHITE}Turbonomic pods checks | ${GREEN}PASSED" )
            else
                # Get the list of non correctly running pods
                while IFS= read -r LINE; do
                    #POD_NAME=$(echo ${LINE} | cut -d ' ' -f 1)
                    POD_RECORD=$(echo ${LINE})
                    FAILING_PODS+=( "${POD_RECORD}" )
                done <<< "${KUBE_OUTPUT_FILTERED}"
                if [[ ${VERBOSE} = 1 ]]; then
                    echo "${RED}Some pods are not running as expected."
                    echo "${WHITE}List of pods not running as expected:"
                    printf '%s\n' "${FAILING_PODS[@]}"
                fi
                echo "${RED}Turbonomic pods checks FAILED"
                SUMMARY+=( "${WHITE}Turbonomic pods checks | ${RED}FAILED" )
            fi
        else # kubectl command failed - cluster is messed up?
            if [[ ${VERBOSE} = 1 ]]; then
                echo "${RED}Kubectl command is failing. Please check the status of your Kubernetes cluster."
            fi
            echo "${RED}Turbonomic pods checks FAILED"
            SUMMARY+=( "${WHITE}Turbonomic pods checks | ${RED}FAILED" )
        fi
    else
        # Gluster is enabled
        KUBE_OUTPUT_TURBO=$(kubectl get pods -n turbonomic | grep -v "NAME")
        KUBE_OUTPUT_TURBO_FILTERED=$(kubectl get pods -n turbonomic | grep -Pv '\s+([1-9]+)\/\1\s+Running' | grep -v "NAME")
        if [[ ${KUBECTL_TEST} -eq 0 ]]; then # only if the kubectl command worked
            KUBE_OUTPUT_DEFAULT=$(kubectl get pods -n default | grep -v "NAME")
            KUBE_OUTPUT_DEFAULT_FILTERED=$(kubectl get pods -n default | grep -Pv '\s+([1-9]+)\/\1\s+Running' | grep -v "NAME")
            if [[ -z ${KUBE_OUTPUT_TURBO_FILTERED} && -z ${KUBE_OUTPUT_DEFAULT_FILTERED} ]]; then
                if [[ ${VERBOSE} = 1 ]]; then
                    printf '%s\n' "${KUBE_OUTPUT_TURBO}"
                    echo " "
                    printf '%s\n' "${KUBE_OUTPUT_DEFAULT}"
                    echo " "
                    echo "${GREEN}All pods are running as expected."
                fi
                echo "${GREEN}Turbonomic pods checks PASSED"
                SUMMARY+=( "${WHITE}Turbonomic pods checks | ${GREEN}PASSED" )
            else
                # Get the list of non correctly running pods
                while IFS= read -r LINE; do
                    #POD_NAME=$(echo ${LINE} | cut -d ' ' -f 1)
                    POD_RECORD=$(echo ${LINE})
                    FAILING_PODS+=( "${POD_RECORD}" )
                done <<< "${KUBE_OUTPUT_TURBO_FILTERED}"
                while IFS= read -r LINE; do
                    #POD_NAME=$(echo ${LINE} | cut -d ' ' -f 1)
                    POD_RECORD=$(echo ${LINE})
                    FAILING_PODS+=( "${POD_RECORD}" )
                done <<< "${KUBE_OUTPUT_DEFAULT_FILTERED}"
                if [[ ${VERBOSE} = 1 ]]; then
                    echo "${RED}Some pods are not running as expected."
                    echo "${WHITE}List of pods not running as expected:"
                    for POD in "${FAILING_PODS[@]}"
                    do
                        echo "${RED}${POD}"
                    done
                fi
                echo "${RED}Turbonomic pods checks FAILED"
                SUMMARY+=( "${WHITE}Turbonomic pods checks | ${RED}FAILED" )
            fi
        else # kubectl command failed - cluster is messed up?
            if [[ ${VERBOSE} = 1 ]]; then
                echo "${RED}Kubectl command is failing. Please check the status of your Kubernetes cluster."
            fi
            echo "${RED}Turbonomic pods checks FAILED"
            SUMMARY+=( "${WHITE}Turbonomic pods checks | ${RED}FAILED" )
        fi
    fi
    echo "${WHITE}*****************************"
}

# Main script
# Check for arguments
while getopts "vct:sh" ARGUMENTS
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
      t)
         if [[ -z ${OPTARG} ]]; then
            echo "-t argument requires a value"
         elif ! [[ ${OPTARG} =~ ^[0-9]+$ ]]; then
            echo "-t argument requires a integer value"
            usage
         else
            MAX_TIME=${OPTARG}
            echo "${WHITE}Changing endpoints connectivity checks timeout to ${OPTARG} seconds"
            echo " "
         fi
         ;;
      s)
         echo "${WHITE}Summary table ON"
         echo " "
         SUMMARY_TABLE=1
         ;;
      h|?)
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
if [[ ${SUMMARY_TABLE} = 1 ]]; then
    printf "%s\n" "${WHITE}-------------- SUMMARY TABLE --------------"
    for MSG in "${SUMMARY[@]}"
    do
        NAME=$(echo ${MSG} | cut -f1 -d'|')
        VALUE=$(echo ${MSG} | cut -f2 -d'|')
        printf "%-40s %-40s\n" "${NAME}" "${VALUE}"
    done
    printf "%s\n" "${WHITE}-------------------------------------------"
fi
echo " "
if [[ ${VERBOSE} = 1 ]]; then
    echo "${WHITE}Please review and resolve any FAILED issues above before proceeding with the upgrade, if you cannot resolve **please contact Turbonomic support**"
else
    echo "${WHITE}Please review and resolve any FAILED issues above before proceeding with the upgrade, if you need more details of any failed items re-run the script with the -v switch, if you cannot resolve **please contact Turbonomic support**"
fi
echo " "
echo "End of Upgrade Pre-Check"