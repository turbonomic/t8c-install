#!/usr/local/bin/bash -e

# Use this script to launch a kibitzer pod attached to a given component and performing one
# or more activities.

unset XL_NAME COMPONENT DESCRIBING

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
  --tag t
        useful when running --describe when there is not a cluster with an XL resource from
        which to obtain a tag for the Kibitzer container. Also useful when running a Kibitzer
        container in a Turbo environment from an old release that predates the needed
        activity or even Kibitzer itself
EOF
}

if [[ $1 == '--describe' ]]; then
  DESCRIBING=true
  shift 1
else
  while [[ $1 ]]; do
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
      DESCRIBING=ture
      shift
      ;;
    --tag)
      TAG="$2"
      shift 2
      ;;
    *) break ;;
    esac
  done
fi

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
  XL_NAME=$(kubectl get xl --no-headers -o name)
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

# extract default tag name from the XL resource if not specified on command line
if [[ ! $TAG ]]; then
  TAG=$(kubectl get -o json xl "$XL_NAME" | jq -r .spec.global.tag)
  if [[ ! $TAG ]]; then
    echo "Unable to obtain default image tag from XL resource $XL_NAME; please specify using" \
         "--tag option" > /dev/stderr
    usage
    exit 1
  fi
fi
export TAG

if [[ $# == 0 ]]; then
  echo "No kibitzer activities specified; please specify at least one" > /dev/stderr
  usage
  exit 1
fi

if [[ $DESCRIBING ]] ; then
  # exec so we quit when container exits and don't follow on with actaully running activities
  exec docker run --rm --name=kibitzer \
    -e JAVA_OPTS="-Dorg.jooq.no-logo=true" -e LOG_TO_STDOUT=true \
    turbonomic/kibitzer:$TAG --describe "$@"
fi

# kibitzer expects component name followed by activity specs; all need to be quoted and comma-separated
# for inclusion in YAML inlined array literal
args="\"$COMPONENT\""
for arg in "$@"; do args="$args,\"$arg\""; done

# Create a customized job and submit it to kubernetes, using `envsubst` to inline our kibitzer args
# and random numbers to prevent job/pod name collisions
export ARGS="[$args]"
cat <<EOF | envsubst '${ARGS} ${RANDOM} ${TAG}' | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: kibitzer-$(printf %x $RANDOM$RANDOM)-$(printf %x $RANDOM$RANDOM)
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
      containers:
      - name: kibitzer
        args: $ARGS
        env:
        - name: JAVA_DEBUG
          value: "true"
        - name: JAVA_DEBUG_OPTS
          value: "-agentlib:jdwp=transport=dt_socket,address=0.0.0.0:8000,server=y,suspend=n"
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
        image: "turbonomic/kibitzer:$TAG"
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
EOF
