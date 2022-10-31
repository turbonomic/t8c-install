#!/bin/bash

set -o errexit

command -v jq >/dev/null 2>&1 || {
  echo "jq not found. Please install before running this script"
  exit 1
}

: ${1:?First arg should be token file!}

jq -r .tokenData $1 | base64 -d | kubectl apply -f -
