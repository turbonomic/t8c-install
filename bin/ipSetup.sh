#!/bin/bash

# To Do
#       1. Validate that ip addresses and netmasks are valid
#       2. Peer review
#

# Run this as the root user
if [[ $(/usr/bin/id -u) -ne 0 ]]
then
  echo "Not running as root, please become the root user"
  exit
fi

# VMTurbo Network Configuration Script
dump () { 
    echo "interactive: $interactive"
    echo "  bootproto: $bootproto"
    echo " domainName: $domainName"
    echo "     ipAddr: $ipAddr"
    echo "    netMask: $netMask"
    echo "    gateWay: $gateWay"
    echo "       DNS1: ${dns[0]}"
    echo "       DNS1: ${dns[1]}"
}

usage () {
    echo "usage: ipsetup "
    echo "       ipsetup -b [-v]"
    echo "       ipsetup -a inet4Address -n netmask -g gateway -d dnsServer [-D domain] [-v]"
    echo ""
    echo "       Running ipsetup with no parameters runs in interactive mode"
    echo ""
    echo "       -a ipAddr              Assign IPv4 adddress"
    echo "       -b                     Set boot protocol to dhcp"
    echo "       -d dnsServer           Assign DNS server"
    echo "                              (May be a quoted, space-delimited list)"
    echo "       -D domain              Assign domain name for this VM"
    echo "       -h                     Help, such as it is..."
    echo "       -g gateway             Assign gateway address"
    echo "       -n netmask             Assgin network mask"
    echo "       -v                     Verbose mode"

}

interactive=1;
verbose=0;

declare -a dns

while getopts "a:bd:D:g:hn:v" opt; do
    interactive=0
    case $opt in
        a)      # IP Address
                ipAddr=$OPTARG
                bootproto=static
                ;;
        b)      # Boot Protocol
                bootproto=dhcp
                ;;
        d)      # DNS 
                dns=($OPTARG)
                ;;
        D)      # Domain Name
                domainName=$OPTARG
                ;;
        g)      # Gateway Address
                gateWay=$OPTARG
                bootproto=static
                ;;
        h)      # Help
                usage
                exit
                ;;
        n)      # Network Mask
                netMask=$OPTARG
                bootproto=static
                ;;
        v)      # Verbose
                verbose=1
                ;;
        *)      # Anything else
                echo "Unrecognized argument, exiting"
                exit
                ;;

    esac
done

# Check that we have a valid configuration
if [ X$bootproto == "Xstatic" ];then
    if [ -z $ipAddr ]; then
        echo "Must supply an IP address"
        usage
        exit
    fi

    if [ -z $netMask ]; then
        echo "Must supply an IP address AND a netmask"
        usage
        exit
    fi

    if [ -z $gateWay ]; then
        echo "Must supply an IP address, a netmask, AND a gateway address"
        usage
        exit
    fi

    if [ -z ${dns[0]} ]; then
        echo "Must supply an IP address, a netmask, a gateway address, AND at least one DNS server"
        usage
        exit
    fi
fi

if [ X$verbose == X1 ]; then
    dump
fi

# Check the device 
deviceName="eth0"
ifcfgPath="/etc/sysconfig/network-scripts/ifcfg-${deviceName}"

get_current_ip() {
  ip_addr=$(ip a show ${deviceName} | grep inet | egrep -v inet6 | awk '{print $2}' | awk -F/ '{print $1}')
}

# Set ip, static or dhcp
# if set on the command line, ignore
if [ -z $bootproto ]; then
    echo ""
    read -e -p "Do you want to use DHCP or set a static IP (dhcp/static) :: " bootproto
fi

#dbf

if [ X${bootproto} = "Xdhcp" ]
then 
  cat <<EOF > ${ifcfgPath}
STARTMODE="auto"
DEVICE="${deviceName}"
BOOTPROTO="dhcp"
ONBOOT="yes"
EOF
fi

if [ X${bootproto} = "Xstatic" ]; then 

    if [ X${interactive} == "X1" ]; then
      read -e -p "Please enter the IP Address for this machine :: " ipAddr
      read -e -p "Please enter the network mask for this machine :: " netMask
      read -e -p "Please enter the Gateway address for this machine :: " gateWay
      # Declare dns array
      # declare -a dns
      #  All subsequent commands in this script will treat
      #+ the variable "dns" as an array.
      read -e -p "Enter DNS Server(s) IP Address for this machine (separated from each other by a space) :: " -a dns
      read -e -p "Enter Domain Name for this machine :: " domainName

      echo ""
      echo "--------"
      echo "These are the settings that will be committed."
      echo "The IP Address is ${ipAddr}"
      echo "The Netmask is ${netMask}"
      echo "The Gateway is ${gateWay}"
      echo "Configured DNS Server's IP Address is:"
      element_count=${#dns[@]}
      index=0
      while [ "$index" -lt "$element_count" ]
      do    # List all the elements in the array.
        let "dnsNumber = $index + 1"
        echo "DNS ${dnsNumber}: ${dns[$index]}" 
        let "index = $index + 1"
      done
      echo "The Domain is: ${domainName}"
      echo "--------"

      read -e -p "Are you sure you want to use these settings? (y/n) :: " answer
  else
      answer="y"
  fi

  if [ X$answer = "Xy" ]
  then
    cat <<EOF > ${ifcfgPath}
STARTMODE="auto"
DEVICE="${deviceName}"
BOOTPROTO="static"
ONBOOT="yes"
IPADDR="${ipAddr}"
NETMASK="${netMask}"
GATEWAY="${gateWay}"
DOMAIN="${domainName}"
EOF

    element_count=${#dns[@]}
    index=0
    while [ "$index" -lt "$element_count" ]
    do    # List all the elements in the array.
      let "dnsNumber = $index + 1"
      echo "DNS${dnsNumber}=\"${dns[$index]}\"" >> ${ifcfgPath}
      let "index = $index + 1"
    done  
  else
    echo "Restart to correct settings"
    exit 0
  fi
fi

# Restart if not properly answered
if [ ! X$bootproto = Xstatic ] && [ ! X$bootproto = Xdhcp ]
then
  echo "Restart to correct settings"
  exit 0
fi

# Configure proxy
if [ X${interactive} == "X1" ]; then
    echo ""
    read -e -p "Do you want to configure a proxy server? (y/n) :: " proxy
    echo ""
else
    proxy="n"
fi

if [ X$proxy = "Xy" ]
then
  # Declare excludedProxies array
  declare -a exludedProxies
  #  All subsequent commands in this script will treat
  #+ the variable "excludedProxies" as an array.
  read -e -p "Please enter the http proxy server and port (proxy:port) :: " httpProxy

  echo ""
  echo "--------"
  echo "Proxy settings that will be used"
  echo "The http proxy is ${httpProxy}"
  echo "--------"

  read -e -p "Are you sure you want to use these settings? (y/n) :: " answer

  if [ X$answer = "Xy" ]
  then
    echo "http_proxy: \"http://${httpProxy}/\"" >> /opt/kubespray/inventory/sample/group_vars/all/all.yml
    echo "https_proxy: \"http://${httpProxy}/\"" >> /opt/kubespray/inventory/sample/group_vars/all/all.yml
    echo "no_proxy: \"${ipAddr}, node1, node1, 127.0.0.1, 127.0.0.0\"" >> /opt/kubespray/inventory/sample/group_vars/all/all.yml
    sed -i '/proxy/d' /etc/yum.conf
    sed -i "/main/a proxy=http://${httpProxy}" /etc/yum.conf
  else
    echo "Restart to correct settings"
    exit 0 
  fi
fi

# Restart network services
if [ X${interactive} == X1 ]; then
    read -e -p "Do you want to restart the network now? (y/n) :: " networkRestart
else
    networkRestart="y"
fi

if [ X$networkRestart = "Xy" ]
then
  echo ""
  echo "********"
  echo "If you are using ssh to configure, you will be disconnected from the server."
  echo "Reconnect with ${ipAddr} after 30 seconds"
  echo "********"
  echo ""
  systemctl restart network
else 
  echo "Changes will take place after a network restart"
  exit 0
fi

if [  X${bootproto} = 'Xdhcp' ] || [ X${bootproto} = 'Xstatic' ]
then
  get_current_ip
  echo ""
  echo "Turbonomic Operations Manager is now running with IP: *${ip_addr}*"
  if [ ! -z ${httpProxy} ]
  then
    echo "The proxy is ${httpProxy}"
  fi
  echo ""

  echo "Start a secure session (SSH) on your Turbonomic VM as the turbo user and"
  echo "perform the following steps:"
  echo "------------------------------------------------------------------------"
  echo "  Initialize the Kubernetes node and deploy the Turbonomic Appliance"
  echo "  Execute the script: /opt/local/bin/t8c.sh"
  echo "  Do not specify sudo when you execute this script."
  echo "  The script should take up to 20 minutes to complete."

  echo "  example:"
  echo "  $ ssh turbo@${ip_addr}"
  echo "  $ /opt/local/bin/t8c.sh"
  echo ""
else
  echo ""
  echo "Must be either static or dhcp"
  echo ""
  exec $0
fi

# Configure Central Time Servers
if [ X${interactive} == "X1" ]; then
    echo ""
    read -e -p "Do you want to configure a Network Time Source? (y/n) :: " timesync
    /opt/local/bin/timesync.sh
else
    proxy="n"
fi
