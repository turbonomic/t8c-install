#!/usr/bin/env bash

set -e
set -u
set -o pipefail

# Use this script to launch a kibitzer pod attached to a given component and performing one
# or more activities.

XL_NAME=; COMPONENT=; DESCRIBING=; REPO=; TAG=; PULL_SECRET_NAME=; NAMESPACE=;
DB_AUTOPROVISION=; DB_SECRET_NAME=; DB_SECRET_VOLUME=; DB_SECRET_MOUNT=; JOB_NAME=;
DELETE=; NOLOG=; RESTARTS=0
JAVA_COMPONENT_OPTS="-Dorg.jooq.no-logo=true";
KC=kubectl
KARGS=()

function usage() {
  cat <<EOF
Usage: $0 [--xl name] [--tag t] \
    {  --component c activity:prop=value:... ... | \
       --describe component:tag ... }
Where:
  --component c
        specifies that this Kibitzer should run with activities associated with the
        specified component
  activity:prop=value:...
        specifies an activity (via its tag) that should be executed by this kibitzer, with the
        given property settings

  --describe component:tag ...
        produces information about the specified activities in Kibitzer, including
        names, descriptions, types, and defaults for all configuration properties. This
        option always turns on --delete-on-completion

  --job-name name
        specify the job name to use; by default the name is "kibitzer" followed by a random
        hex string for deduplication. If a job by this name already exists, that job is updated
        rather than a new job being created.
  --nolog
        do not tail job output to terminal. By default, this is done unil the job completes.
        Output always goes to rsyslog with prefix "kibitzer" regardless of this setting
  --delete-on-completion
        specify that the job should be deleted immediately after completion, rather than
        the default of specifying auto-deletion five minutes after completion
  --restarts n
        specify how many times the pod should be allowed to restart if it fails. If this is not
        specified, the kubernetes default of 6 is used.
  --xl name
        useful in the case where multiple XL resources are present in the current environment
        (uncommon). This option can be used to select one of those resources for use by
        Kibitzer
  --repo r
        use the specified repository name for image retrieval, rather than the one obtained
        by querying the cluster
  --tag t
        useful when running --describe when there is not a cluster with an XL resource from
        which to obtain a tag for the Kibitzer container. Also useful when running a Kibitzer
        container in a Turbo environment from an old release that predates the needed
        activity or even Kibitzer itself
  --namespace ns (or --project ns)
        specify a namespace or OpenShift project name for the job
  --db-autoprovision
        use this to indicate that that any new database needed by Kibitzer should be created
        and dropped automatically as needed. This requires that a root user and password be
        configured via standard means. By default, Kibitzer expects any needed databases to be
        created prior to using Kibitzer, if any activities use COPY or RETAINED_COPY db_mode.
  --db-secret-name secretName
        use this to specify a the name of a kubernetes secret with credentials for host componnent
        DB connection. The same credentials will be used for a kibitzer copy of the component
        database if one is required. Normally, the script will automatically detect the correct
        the secret name from the XL resource.
        component configuration or via global configuration
  --pull-secret-name name
        specify the name of a secret that can be used when pulling images
  --openshift
        use when working with an openshift cluster. The script will use \`oc\` instead of
        \`kubectl\` and alter certain other details accordingly
EOF
}

function get_args {
  while [[ "$*" ]]; do
    case "$1" in
    --xl)
      XL_NAME="$2"
      shift 2
      ;;
    --component)
      COMPONENT="$2"
      shift 2
      ;;
    --describe)
      DESCRIBING=true
      DELETE=true
      shift
      ;;
    --job-name)
      JOB_NAME="$2"
      shift 2
      ;;
    --delete-on-completion)
      DELETE=true
      shift
      ;;
    --nolog)
      NOLOG=true
      shift
      ;;
    --restarts)
      RESTARTS="$2"
      shift 2
      ;;
    --repo)
      REPO="$2"
      shift 2
      ;;
    --tag)
      TAG="$2"
      shift 2
      ;;
    --namespace|--project)
      NAMESPACE="$2"
      shift 2
      ;;
    --db-autoprovision)
      DB_AUTOPROVISION=true
      shift
      ;;
    --db-secret-name)
      DB_SECRET_NAME="$2"
      shift 2
      ;;
    --pull-secret-name)
      PULL_SECRET_NAME="$2"
      shift 2
      ;;
    --openshift)
      KC=oc
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      KARGS+=("$1")
      shift
      ;;
    esac
  done

  if [[ $COMPONENT && $DESCRIBING ]];  then
    echo "--describe and --component cannot be used together" > /dev/stderr
    usage
    return 1
  fi

  if [[ ! $COMPONENT && ! $DESCRIBING ]]; then
    echo "No component specified; please use --component option to specifiy one" > /dev/stderr
    usage
    return 1
  fi
}

function run_detections {
  detect_xl_resource
  detect_repo
  detect_namespace
  detect_tag
}

function detect_xl_resource {
  if [[ ! $XL_NAME ]]; then
    XL_NAME=$($KC get xl --no-headers -o name)
    n=$(echo "$XL_NAME" | wc -w)
    if [[ $n -gt 1 && $COMPONENT ]]; then
      echo "Multiple XL resources exist; please specify one of them using --xl option" > /dev/stderr
      usage
      exit 1
    elif [[ $n == 0 && $COMPONENT ]]; then
      echo "No XL resource exists; cannot launch kibitzer." > /dev/stderr
      exit 1
    else
      # strip resource type from name
      XL_NAME=${XL_NAME#*/}
    fi
  fi
}

function detect_repo {
  if [[ ! $REPO ]]; then
    REPO=$($KC get xl "$XL_NAME" -o jsonpath='{.spec.global.repository}')
    if [[ ! $REPO ]]; then
      echo "Unable to obtain default docker repository from XL resource '$XL_NAME'; please " \
          "specify using --repo option" > /dev/stderr
      usage
      exit 1
    fi
  fi
}

function detect_namespace {
  if [[ ! $NAMESPACE ]]; then
    NAMESPACE="$($KC get xl "$XL_NAME" -o jsonpath='{.metadata.namespace}')"
    if [[ ! $NAMESPACE ]] ; then
      echo "Unable to obtain default namespace from XL resource $XL_NAME; please specify using" \
           "--namespace option" > /dev/stderr
      usage
      exit 1
    fi
  fi
}

function detect_tag {
  if [[ ! $TAG ]]; then
    TAG=$($KC get xl "$XL_NAME" -o jsonpath='{.spec.global.tag}')
    if [[ ! $TAG ]]; then
      echo "Unable to obtain default image tag from XL resource $XL_NAME; please specify using" \
           "--tag option" > /dev/stderr
      usage
      exit 1
    fi
  fi
}

function compose_argstring {
  if [[ ! $DESCRIBING && ${#KARGS[@]} == 0 ]]; then
    echo "No kibitzer activities specified; please specify at least one" > /dev/stderr
    usage
    exit 1
  fi

  if [[ $DESCRIBING ]] ; then
    # for --describe, we need that option up front in kibitzer container args, followed by
    # describe specs
    ARGSTRING="\"--describe\""
  else
    # otherwise, kibitzer expects component name first, followed by activity specs and other options
    ARGSTRING="\"$COMPONENT\""
  fi
  for arg in "${KARGS[@]}"; do ARGSTRING="$ARGSTRING,\"$arg\""; done
}

function create_job_name {
  if [[ ! $JOB_NAME ]]; then
    JOB_NAME="kibitzer-$(printf %x $RANDOM$RANDOM)"
  fi
  echo job name $JOB_NAME
}


function compose_jobspec_substitutions {
  compose_argstring

  if [[ ! $DB_SECRET_NAME ]]; then
    DB_SECRET_NAME="$($KC get xl "$XL_NAME" -o jsonpath="{.spec.$COMPONENT.dbSecretName}")"
  fi
  if [[ ! $DB_SECRET_NAME ]]; then
    DB_SECRET_NAME="$($KC get xl "$XL_NAME" -o jsonpath="{.spec.global.dbSecretName}")"
  fi

  if [[ $PULL_SECRET_NAME ]]; then PULL_SECRET_NAME="\"$PULL_SECRET_NAME\""; fi

  if [[ $DB_AUTOPROVISION ]] ; then
    JAVA_COMPONENT_OPTS="$JAVA_COMPONENT_OPTS -DdbAutoprovision=true"
  fi

  if [[ $DB_SECRET_NAME ]]; then
    DB_SECRET_VOLUME="$(echo '- {"name": "db-creds", "secret": ' \
        '{"secretName": "'$DB_SECRET_NAME'", "optional": true}}')"
    DB_SECRET_MOUNT='- {"mountPath": "/vault/secrets", "name": "db-creds", "readOnly": true}'
  fi

  if [[ $RESTARTS ]]; then
    RESTART_SPEC="backoffLimit: $RESTARTS"
  else
    RESTART_SPEC=""
  fi
}

function create_job_spec {
  # Create a customized job and submit it to kubernetes, using `envsubst` to inline our kibitzer args
  cat << EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: "$JOB_NAME"
  namespace: $NAMESPACE
  labels:
    app.kubernetes.io/name: kibitzer
    zone: internal
spec:
  # allow the jobs and pods to live for a few minutes after job completion, in case there is
  # a need to examine them or extract data from them. If more than this time will be needed, the
  # first step should be to edit the job and set its ttl to zero or a sufficiently large value
  ttlSecondsAfterFinished: 300
  $RESTART_SPEC
  template:
    spec:
      restartPolicy: Never
      imagePullSecrets: [ $PULL_SECRET_NAME ]
      containers:
      - name: kibitzer
        args: [$ARGSTRING]
        env:
        - name: JAVA_DEBUG
          value: "true"
        - name: JAVA_DEBUG_OPTS
          value: "-agentlib:jdwp=transport=dt_socket,address=0.0.0.0:8000,server=y,suspend=n"
        - name: JAVA_COMPONENT_OPTS
          value: "$JAVA_COMPONENT_OPTS"
        - name: component_type
          value: kibitzer
        - name: instance_id
          valueFrom:
            fieldRef:
              apiVersion: v1
              fieldPath: metadata.name
        - name: instance_ip
          valueFrom:
            fieldRef:
              apiVersion: v1
              fieldPath: status.podIP
        - name: clustermgr_host
          value: clustermgr
        - name: clustermgr_port
          value: "8080"
        - name: kafkaServers
          value: kafka:9092
        - name: logging.level.com.vmturbo.kibitzer
          value: info
        - name: LOG_TO_STDOUT
          value: "true"
        image: "$REPO/kibitzer:$TAG"
        imagePullPolicy: IfNotPresent
        livenessProbe:
          failureThreshold: 1440
          httpGet:
            path: /health
            port: 8080
            scheme: HTTP
          periodSeconds: 10
          successThreshold: 1
          timeoutSeconds: 1
        ports:
        - containerPort: 8080
          protocol: TCP
        - containerPort: 9001
          protocol: TCP
        - containerPort: 8000
          protocol: TCP
        resources:
          limits:
            memory: 32Gi
          requests:
            memory: 786Mi
        securityContext:
          capabilities:
            drop:
            - ALL
          readOnlyRootFilesystem: true
        volumeMounts:
        - mountPath: /vault/trust
          name: common-truststore-secret
          readOnly: true
        - mountPath: /vault/key
          name: kibitzer-keystore-secret
          readOnly: true
        - mountPath: /vault/mtlsSecrets
          name: kibitzer-mtls-secret
          readOnly: true
        - mountPath: /etc/turbonomic
          name: turbo-volume
          readOnly: true
        - mountPath: /tmp
          name: kibitzer-tmpfs0
        ${DB_SECRET_MOUNT}
      volumes:
      - configMap:
          defaultMode: 420
          name: global-properties-xl-release
          optional: true
        name: turbo-volume
      - name: kibitzer-truststore-secret
        secret:
          defaultMode: 420
          optional: true
          secretName: kibitzer-truststore-secret
      - name: common-truststore-secret
        secret:
          defaultMode: 420
          optional: true
          secretName: common-truststore-secret
      - name: kibitzer-keystore-secret
        secret:
          defaultMode: 420
          optional: true
          secretName: kibitzer-keystore-secret
      - name: kibitzer-mtls-secret
        secret:
          defaultMode: 420
          optional: true
          secretName: kibitzer-mtls-secret
      - emptyDir: {}
        name: kibitzer-tmpfs0
      ${DB_SECRET_VOLUME}
EOF
}

function create_job {
    local tmpfile=$(mktemp)
    create_job_spec > $tmpfile
    $KC apply -f $tmpfile
}

function log_pod {
  local name_out="--output=jsonpath={.items[0].metadata.name}"
  local pod_name="$($KC get pod -l job-name="$JOB_NAME" "$name_out")"
  if [[ $DESCRIBING ]]; then
      # skip output until we see the initial description separator
      $KC logs -f "$pod_name" | sed -n '/=====================/,$p'
  else
      # skip output until we see the first message from Kibitzer class
      $KC logs -f "$pod_name" | sed -n '/[[]Kibitzer[]]/,$p'
  fi
}

function wait_for_pod {
  local ready_out="--output=jsonpath={.status.ready}"
  local completed_out="--output=jsonpath={.status.completed}"
  while true; do
    local ready="$($KC get job "$JOB_NAME" "$ready_out")"
    local completed="$($KC get job "$JOB_NAME" "$completed_out")"
    if [[ $ready -gt 0 || $completed -gt 0 ]]; then return; fi
    sleep 1
  done
}

function delete_job {
  $KC delete job "$JOB_NAME"
}

function main {
  get_args "$@"
  run_detections
  create_job_name
  compose_jobspec_substitutions
  create_job
  if [[ ! $NOLOG ]]; then
    wait_for_pod
    log_pod
  fi
  if [[ $DELETE ]]; then delete_job; fi
}

main "$@"