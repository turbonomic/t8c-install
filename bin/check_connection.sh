#!/bin/bash

usage()
{
   echo ""
   echo "Usage: $(basename ${0}) --ip 127.0.0.1 --port 443"
   echo "Flags:"
   echo "  -h, --help         print help"
   echo "  -i, --ip string    the IP address to use"
   echo "  -p, --port string  the port to use"
}

function main() (
  set -e
  parse_args $@

  [[ -z ${ipAddress} ]] && {
    ipAddress=$(must_input -p "enter IP address (e.g. '127.0.0.1'): ")
  }
  [[ -z ${port} ]] && {
    port=$(must_input -p "enter port number (e.g. '44'): ")
  }

  echo "Checking connectivity to ${ipAddress}:${port}..."
  nc -z -w 2 ${ipAddress} ${port} && {
    echo "The request to ${ipAddress}:${port} was successful"
  } || {
    echo "Failed to connect to ${ipAddress}:${port}"
    return 1
  }
)

function parse_args() {
  while [ "${1-}" != "" ]; do
    case $1 in
    -i | --ip)
    shift
      ipAddress="${1}"
      ;;
    -p | --port)
      shift
      port="${1}"
      ;;
    -h | --help )
      usage
      exit 0
      ;;
    * )
      echo "Invalid argument: ${1}" >&2
      usage
      exit 1
      ;;
    esac
    shift
  done
}

function must_input {
  while [[ "$x" == "" ]]; do
    read "$@" x;
  done
  echo $x
}

main $@
