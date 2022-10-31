#!/bin/bash

set -o errexit
set -o pipefail
trap "echo 'Token exchange failed.'" ERR

function must_input {
  while [[ "$x" == "" ]]; do
  read "$@" x;
  done
  echo $x
}

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

curl -sS -k -m 10 -b $tmp -X POST ${ip}/api/v3/clients/networks/tokens | jq -r .tokenData | base64 -d | kubectl apply -f -

echo "Token exchange successful."
