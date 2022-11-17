#!/bin/bash

function main() (
  set -e

  parse_args $@

  check_token

  if [[ "${login}" == "true" ]]
  then
    login_and_generate_token
  else
    ask_user_for_token
  fi

  : ${token:?"Bad state: token is blank"}
  secret=$(echo $token | jq -r .tokenData | base64 -d | kubectl apply -o name ${namespace} -f -)

  echo "Token applied successfully. Waiting up to 30s for connection to be established..."

  for i in $(seq 10)
  do
    sleep 3
    if [[ $(kubectl get ${secret} ${namespace} -o template --template='{{index .metadata.labels "skupper.io/type"}}') == "connection-token" ]]
    then
      echo "Connection has been established."
      echo "Token exchange successful."
      return
    fi
  done

  echo "Timeout: Failed to establish connection after 30s"
  return 1
)

function parse_args() {
  while [ "${1-}" != "" ]; do
    case $1 in
    -l)
      login="true"
      ;;
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

function check_token() {
  tokens=$(kubectl get secret ${namespace} -l "skupper.io/type=connection-token" -o name)

  if [[ "${tokens}" != "" ]]
  then
    echo "A connection has already been established for this deployment."
    return 1
  fi
}

function login_and_generate_token() {
  ip=$(must_input -p "Enter address of Turbonomic SaaS instance (e.g. 'turbonomic.example.com', '127.0.0.1'): ")

  if ! [[ $ip =~ ^https?:// ]]; then
    ip=https://${ip}
  fi

  username=$(must_input -p "enter username: ")

  read -s -p "enter password: " password
  echo ""

  tmp=$(mktemp)
  trap "rm -f $tmp" 0 2 3 15

  status=`curl -sS -k -m 10 -c $tmp ${ip}/api/v3/login --data-urlencode "username=${username}" --data-urlencode "password=${password}" -w "%{http_code}" -o /dev/null`
  if [[ "$status" != "200" ]]; then
    echo "Login failed. Check your inputs and try again"
    exit 1
  fi

  token=$(curl -sS -k -m 10 -b $tmp -X POST ${ip}/api/v3/clients/networks/tokens)
}

function must_input {
  while [[ "$x" == "" ]]; do
    read "$@" x;
  done
  echo $x
}

function ask_user_for_token() {
  echo "Enter token provided by your Turbonomic SaaS instance: "

  while [[ "${token}" == "" ]]
  do
    token=$(sed '/}$/q')
  done
}

login="false"
token=""

trap "echo 'Token exchange failed.'" ERR
main $@