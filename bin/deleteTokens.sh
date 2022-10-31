#!/bin/bash

kubectl delete secret -l 'skupper.io/type in (connection-token, token-claim)'
