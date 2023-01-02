#!/usr/bin/env bash

set -e
set -u
set -o pipefail

# Use this script to launch a kibitzer pod attached to a given component and performing one
# or more activities.

XL_NAME=; COMPONENT=; DESCRIBING=; REPO=; TAG=; PULL_SECRET_NAME=; NAMESPACE=;
DB_AUTOPROVISION=; DB_SECRET_NAME=; DB_SECRET_VOLUME=; DB_SECRET_MOUNT=;
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
        names, descriptions, types, and defaults for all configuration properties

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
    shift
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
  exit 1
fi

if [[ ! $COMPONENT && ! $DESCRIBING ]]; then
  echo "No component specified; please use --component option to specifiy one" > /dev/stderr
  usage
  exit 1
fi

# detect image tag for current XL resource, if not given on command line
# for this we need the name of an XL resource
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

if [[ ! $REPO ]]; then
  REPO=$($KC get xl "$XL_NAME" -o jsonpath='{.spec.global.repository}')
  if [[ ! $REPO ]]; then
    echo "Unable to obtain default docker repository from XL resource "$XL_NAME"; please specify" \
        "using --repo option" > /dev/stderr
    usage
    exit 1
  fi
fi

if [[ ! $NAMESPACE ]]; then
  NAMESPACE="$($KC get xl "$XL_NAME" -o jsonpath='{.metadata.namespace}')"
  if [[ ! $NAMESPACE ]] ; then
    echo "Unable to obtain default namespace from XL resource $XL_NAME; please specify using" \
         "--namespace option" > /dev/stderr
    usage
    exit 1
  fi
fi

# extract default tag name from the XL resource if not specified on command line
if [[ ! $TAG ]]; then
  TAG=$($KC get xl "$XL_NAME" -o jsonpath='{.spec.global.tag}')
  if [[ ! $TAG ]]; then
    echo "Unable to obtain default image tag from XL resource $XL_NAME; please specify using" \
         "--tag option" > /dev/stderr
    usage
    exit 1
  fi
fi
export TAG

if [[ ${#KARGS[@]} == 0 ]]; then
  echo "No kibitzer activities specified; please specify at least one" > /dev/stderr
  usage
  exit 1
fi

if [[ ! $DB_SECRET_NAME ]]; then
  DB_SECRET_NAME="$($KC get xl "$XL_NAME" -o jsonpath="{.spec.$COMPONENT.dbSecretName}")"
fi
if [[ ! $DB_SECRET_NAME ]]; then
  DB_SECRET_NAME="$($KC get xl "$XL_NAME" -o jsonpath="{.spec.global.dbSecretName}")"
fi

if [[ $DESCRIBING ]] ; then
  # exec so we quit when container exits and don't follow on with actaully running activities
  exec docker run --rm --name=kibitzer \
    -e JAVA_OPTS="-Dorg.jooq.no-logo=true" -e LOG_TO_STDOUT=true \
    "$REPO/kibitzer:$TAG" --describe "${KARGS[@]}"
fi

# kibitzer expects component name followed by activity specs; all need to be quoted and comma-separated
# for inclusion in YAML inlined array literal
ARGSTRING="\"$COMPONENT\""
for arg in "${KARGS[@]}"; do ARGSTRING="$ARGSTRING,\"$arg\""; done

if [[ $PULL_SECRET_NAME ]]; then PULL_SECRET_NAME="\"$PULL_SECRET_NAME\""; fi

if [[ $DB_AUTOPROVISION ]] ; then
  JAVA_COMPONENT_OPTS="$JAVA_COMPONENT_OPTS -DdbAutoprovision=true"
fi

if [[ $DB_SECRET_NAME ]]; then
  DB_SECRET_VOLUME="$(echo '- {"name": "db-creds", "secret": ' \
      '{"secretName": "'$DB_SECRET_NAME'", "optional": true}}')"
  DB_SECRET_MOUNT='- {"mountPath": "/vault/secrets", "name": "db-creds", "readOnly": true}'
fi

# Create a customized job and submit it to kubernetes, using `envsubst` to inline our kibitzer args
# and random numbers to prevent job/pod name collisions
tmpfile=$(mktemp)
( cat | envsubst '${JOB_ARGS} ${RANDOM} ${REPO} ${TAG} ${NAMESPACE}' > $tmpfile; \
  $KC apply -f $tmpfile) <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: kibitzer-$(printf %x $RANDOM$RANDOM)-$(printf %x $RANDOM$RANDOM)
  namespace: $NAMESPACE
  labels:
    app.kubernetes.io/name: kibitzer
    zone: internal
spec:
  # allow the jobs and pods to live for a few minutes after job completion, in case there is
  # a need to examine them or extract data from them. If more than this time will be needed, the
  # first step should be to edit the job and set its ttl to zero or a sufficiently large value
  ttlSecondsAfterFinished: 300
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
