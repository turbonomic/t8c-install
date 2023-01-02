#!/bin/bash

errors=()

function main {
  echo "Troubleshooting skupper components:"
  echo
  troubleshoot-skupper-component skupper-site-controller app.kubernetes.io/name=skupper-site-controller
  troubleshoot-skupper-component skupper-service-controller skupper.io/component=service-controller
  troubleshoot-skupper-component skupper-router skupper.io/component=router

  echo "Troubleshooting tokens:"
  echo
  troubleshoot_tokens

  echo "Troubleshooting complete."
  echo
  echo "${#errors[@]} errors detected."
  if [[ ${#errors[@]} -gt 0 ]]
  then
    echo "Errors:"
    for i in ${!errors[@]}
    do
      echo "- ${errors[$i]}"
      echo
    done
  fi
}

function troubleshoot-skupper-component {

  deploy=${1:?"First arg should be deployment name!"}
  label=${2:?"Second arg should be label!"}

  print_header $deploy

  kubectl get deploy/${deploy} -o name > /dev/null 2>&1 || {
    error="ERROR: deployment/${deploy} not found"
    echo "${error}"
    echo
    errors+=("${error}")
    return
  }

  kubectl get deploy/${deploy} -o template --template='''{{- "" -}}
Name:{{- "\t"}}{{- "\t"}}{{- "\t"}}{{.metadata.name}}
Desired Replicas:{{- "\t"}}{{.spec.replicas}}
Current Replicas:{{- "\t"}}{{ or .status.replicas 0}}
Ready:{{- "\t"}}{{- "\t"}}{{- "\t"}}{{ or .status.readyReplicas 0}}/{{ or .status.replicas 0}}
'''

  desired_replicas=$(kubectl get deploy/${deploy} -o template --template='{{ or .spec.replicas 0}}')
  ready_replicas=$(kubectl get deploy/${deploy} -o template --template='{{ or .status.readyReplicas 0}}')

  [[ ${desired_replicas} == "0" ]] && {
    error="ERROR: deployment/${deploy} has 0 replicas. Please scale to 1 replica"
    echo "${error}"
    echo
    errors+=("${error}")
    return
  }

  kubectl get pods -l ${label} -o template --template='''{{- "" -}}
Pods:
{{- range .items }}
- Name: {{.metadata.name}}
  Containers:
  {{- range .status.containerStatuses }}
  - Name:{{- "\t"}}{{.name}}
    Image:{{- "\t"}}{{.image}}
    {{- range $key,$value := .state }}
    State:{{- "\t"}}{{$key}}
    {{- if $value.message }}
    Message:{{- "\t"}}{{$value.message}}
    {{- end -}}
    {{- if $value.reason }}
    Reason:{{- "\t"}}{{$value.reason}}
    {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end }}

'''

  [[ ${ready_replicas} == "0" ]] && {
    error="ERROR: deployment/${deploy} has 0 ready replicas.
$(kubectl get pods -l ${label} -o jsonpath='{range .items[*].status.containerStatuses[*]}{..message}{"\n"}{end}')"
    echo "${error}"
    echo
    errors+=("${error}")
    return
  }
  
  echo "Status: OK"
  echo
}

function troubleshoot_tokens {
  tokens=$(kubectl get secret -l 'skupper.io/type in (connection-token, token-claim)' -o name)

  if [[ "${tokens}" == "" ]]
  then
    error="ERROR: No tokens found. Please perform the token exchange to connect to the SaaS environment."
    echo "${error}"
    echo
    errors+=("${error}")
  fi

  for t in ${tokens}
  do
    troubleshoot_token $t
  done
}

function troubleshoot_token {
  token=${1:?"First arg should be the token!"}

  print_header $token

  type=$(kubectl get $token -o jsonpath='{.metadata.labels.skupper\.io/type}')
  if [[ "${type}" == "connection-token" ]]
  then
    troubleshoot_connection_token $token
  else
    troubleshoot_token_claim $token
  fi
}

function troubleshoot_connection_token {
  token=${1:?"First arg should be the token!"}

  remote_services=($(kubectl get service -o=jsonpath='{.items[?(@.metadata.annotations.internal\.skupper\.io/controlled=="true")].metadata.name}'))

  if [[ "${#remote_services[@]}" == "0" ]]
  then
    error="ERROR: Token ${token#*/} appears to be active but no remote services could be found. Please contact support."
    echo "${error}"
    echo
    errors+=("${error}")
    return
  fi

  echo "Token ${token#*/} is active and the following remote services were found:"
  for s in ${remote_services[@]}
  do
    echo "- ${s}"
  done
  echo
  echo "Status: OK"
  echo
}

function troubleshoot_token_claim {
  token=${1:?"First arg should be the token!"}

  url=$(kubectl get $token -o jsonpath='{.metadata.annotations.skupper\.io/url}')
  tmp=${url#*://}
  tmp=${tmp%%/*}

  ip=${tmp%:*}
  port=${tmp#*:}

  echo "Testing connectivity to ${ip}:${port}..."
  nc -vzw 5 ${ip} ${port} || {
    error="ERROR: Cannot connect to SaaS endpoint ${ip}:${port}. Is it being blocked by a firewall?"
    echo "${error}"
    echo
    errors+=("${error}")
    return
  }

  status=$(kubectl get $token -o jsonpath='{.metadata.annotations.internal\.skupper\.io/status}')
  error="ERROR: Failed to establish connection to SaaS instance using token ${token#*/}. Status: ${status}."
  if [[ "${status}" == "No such claim" ]]
  then
    error="${error} Token may have expired or has already been claimed. Please try again with a new token."
  elif [[ "${status}" == *"cannot validate certificate"* ]]
  then
    error="${error} Please contact support."
  fi
  echo "${error}"
  echo
  errors+=("${error}")
}

function print_header {
  text=${1:?"First argument should be text to display!"}
  line=$(printf '=%.0s' $(seq 1 ${#text}))
  echo "${line}"
  echo "${text}"
  echo "${line}"
}

main
