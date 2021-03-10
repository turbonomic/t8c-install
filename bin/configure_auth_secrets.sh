#!/bin/bash

# Script to set up Auth encryption keys before bringing up XL components (if so configured)
# This script will be called after checking to see if kubernetes auth secrets are being used.
# If so, pre-generate the encryption keys and load them into secrets.
# The following keys will be created:
#   * encryption key (a random sequence of 256 bits)

set -euo pipefail

# Create a secret for each encryption key (one for each component that uses them)
# The expression `openssl rand 32` creates an encryption key composed of random bytes of a specified length
# Currently, we expect 256-bit keys, which is 32 bytes
# Note: We don't delete any existing keys that we encounter. Doing so could 'brick' an already-configured instance.
#   If any of these keys already exist, this script will exit with an error message like the following:
#   Error from server (AlreadyExists): secrets "auth-secret" already exists
kubectl create secret generic master-key-secret --from-literal=primary_key_256.out="`openssl rand 32`"
KEY_LENGTH=`kubectl get secret master-key-secret -o json | jq -r '.data[]' | base64 -d | wc -c`
while [ $KEY_LENGTH -ne 32 ]
do
  echo "The generated key was not the correct length; regenerating!"
  kubectl delete secret master-key-secret
  kubectl create secret generic master-key-secret --from-literal=primary_key_256.out="`openssl rand 32`"
  KEY_LENGTH=`kubectl get secret master-key-secret -o json | jq -r '.data[]' | base64 -d | wc -c`
done
