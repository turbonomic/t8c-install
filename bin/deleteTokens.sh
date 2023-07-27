#!/bin/bash

namespace=""

while [ "${1-}" != "" ]; do
  case $1 in
  -n)
    shift
    namespace="-n ${1}"
    ;;
  *)
    echo "Invalid option: ${1}" >&2
    exit 1
    ;;
  esac
  shift
done

kubectl delete secret ${namespace} -l 'skupper.io/type in (connection-token, token-claim)'
