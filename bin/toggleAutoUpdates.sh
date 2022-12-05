#!/bin/bash

function main() {

  # check if kubernetes is running
  kubectl cluster-info > /dev/null 2>&1 || {
    echo "kubernetes is not running"
    exit 1
  }

  parse_args $@ 

  # Toggle auto-updates by creating or deleting versionmanager-release object
  versionmanagerFile=/opt/turbonomic/kubernetes/yaml/t8c-client-operator/versionmanager.yaml
  answer=$(yes_or_no "Would you like to enable automatic version updates? [y/n]")
  if [ "${answer}" == "yes" ]
  then
    kubectl apply -f $versionmanagerFile $namespace
    echo "You answered YES - Automatic Updates are ENABLED"
  else
    # Delete the version manager if it already exists. This can happen if the script is run multiple times
    kubectl delete -f $versionmanagerFile $namespace > /dev/null 2>&1
    echo "You answered NO - Automatic Updates are DISABLED"
  fi
}

# Repeatedly prompts the user for input until the user provides a valid yes or no input.
# Prints "yes" if the user gave a yes input. Prints "no" if the user gave a no input.
# Example: answer=$(yes_or_no "Is today Friday?")
yes_or_no() {
  local prompt=${1:?"First arg should be prompt"}
  local answer

  while :; do
    read -e -p "${prompt} " answer
    case $answer in
      y | Y | yes)
        echo yes
        return
        ;;
      n | N | no)
        echo no
        return
        ;;
      esac
  done
}

function parse_args() {
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
}

main $@