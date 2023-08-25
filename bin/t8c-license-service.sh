#!/bin/bash
#
# Copyright 2023 IBM Corporation
#

script_name=$0
operator_version=1.16.6
tmp_folder="/tmp"
src_folder="/tmp/licensing-sources"
licensing_namespace=ibm-common-services
turbo_namespace=turbonomic
use_private_docker_registry="false"
use_private_docker_registry_creds="false"
my_docker_registry="my.private.registry.example.com"
my_docker_registry_username="my.private.registry.example.username"
my_docker_registry_token="my.private.registry.example.token"
uninstall="false"
skip_to_instance_check=0
version_installed=""
thanos_url="http://prometheus-server.${turbo_namespace}:9090/api/v1/query"
offline_install="false"
offline_sources_folder="/opt/local/downloads"
verbose=0
KUBECTL=${KUBECTL-/usr/local/bin/kubectl}
kubernetes_min_version=1.19

function timestamp() {
	date '+%Y-%m-%d %H:%M:%S'
}

function INFO() {
	local ts=$(timestamp)
	echo ${ts} "${script_name} INFO - " "$@"
}

function WARN() {
	local ts=$(timestamp)
	echo ${ts} "${script_name} ** WARN - " "$@"
}

function ERROR() {
	local ts=$(timestamp)
	echo ${ts} "${script_name} >>>>> ERROR - " "$@"
}

function usage() {
    cat <<USAGETEXT
Description: A script to install IBM License Service via Operator.

Note: Use this script only for cluster running on x86 architecture.

Usage:
    $0 [(-v|--operator_version) <version number>] [(-s|--src_folder) <source folder>] [(-n|--namespace)  <licensing namespace>]
    [(-tn|--turbo_namespace)  <turbo namespace>] [(-d|--docker_registry) <private docker registry>]
    [(-u|--docker_username) <private docker registry username>] [(-t|--docker_token) <private docker registry token>]
    [-r|--uninstall] [-o|--offline] [--help|-h]

    $0 [-r]

When installing it uninstalls any previous instance with version different than [-v|--operator_version] (which defaults at v${operator_version}).

Options:
    [-v|--operator_version]:    operator version                    (default: ${operator_version})
    [-s|--src_folder]:          source folder                       (default: ${src_folder})
    [-n|--namespace]:           licensing service namespace         (default: ${licensing_namespace})
    [-tn|--turbo_namespace]:    namespace where turbo is installed  (default: ${turbo_namespace})
    [-d|--docker_registry]:     private registry prefix             (default: not set)
    [-u|--docker_username]:     private registry username           (default: not set)
    [-t|--docker_token]:        private registry token              (default: not set)
    [-r|--uninstall]:           uninstall ibm-licensing-service     (default: not set)
    [-o|--offline]:             install from ISO image              (default: false)
    [-h|--help]:                print this help
USAGETEXT
    exit 1
}

while [ "${1}" != "" ]; do
  OPT=${1}
  case ${OPT} in
    -h | --help )                                       usage
                                                        exit
                                                        ;;
    -v | --operator_version )                           shift
                                                        operator_version=${1}
                                                        ;;
    -s | --src_folder )                                 shift
                                                        src_folder=${1}
                                                        ;;
    -n | --namespace )                                  shift
                                                        licensing_namespace=${1}
                                                        ;;
    -tn | --turbo_namespace )                           shift
                                                        turbo_namespace=${1}
                                                        ;;
    -d | --docker_registry )                            shift
                                                        my_docker_registry=${1}
                                                        use_private_docker_registry="true"
                                                        ;;
    -u | --docker_username )                            shift
                                                        my_docker_registry_username=${1}
                                                        use_private_docker_registry_creds="true"
                                                        ;;
    -t | --docker_token )                               shift
                                                        my_docker_registry_token=${1}
                                                        use_private_docker_registry_creds="true"
                                                        ;;
    -r | --uninstall )                                  uninstall="true"
                                                        ;;
    -o | --offline )                                    offline_install="true"
                                                        ;;
    * )                                                 ERROR "Wrong option: $OPT"
                                                        usage
                                                        exit 1
  esac
  if ! shift
  then
    ERROR "Did not add needed arguments after option: $OPT"
    usage
    exit 4
  fi
done


function print_args() {
    echo -e "Starting the $0 script with the following arguments:"
    if [[ "${uninstall}" == "true" ]]
    then
      echo -e "\t-r  | uninstall\t\t\t: ${uninstall}"
    else
      echo -e "\t-v  | version\t\t\t: ${operator_version}"
      echo -e "\t-s  | src folder\t\t: ${src_folder}"
      echo -e "\t-n  | namespace\t\t\t: ${licensing_namespace}"
      echo -e "\t-tn | turbo_namespace\t\t: ${turbo_namespace}"
      if [[ "${offline_install}" == "true" ]]
      then
        echo -e "\t-o  | offline\t\t\t: ${offline_install}"
        echo -e "\t-t  | offline src folder\t: ${offline_sources_folder}"
      fi

      if [[ "${use_private_docker_registry}" == "true" ]]
      then
        echo -e "\t-d  | private registry\t\t: ${my_docker_registry}"
      fi
      if [[ "${use_private_docker_registry_creds}" == "true" ]]
      then
        echo -e "\t-u  | private registry username\t: ${my_docker_registry_username}"
        echo -e "\t-t  | private registry token\t: ${my_docker_registry_token}"
      fi
    fi
    echo ""
}

function verbose_output_command(){
  if [ "$verbose" = "1" ]; then
    "$@"
  else
    "$@" 1> /dev/null 2>&1
  fi
}

function create_sources_folder() {
  INFO "Creating a sources folder under ${src_folder}"
  sudo mkdir -p ${src_folder}
}

function check_pre_req() {
  if [[ ! -x "$KUBECTL" ]]
    then
      ERROR "$KUBECTL is not an executable file"
      exit 2
  fi
  kubernetes_installed_version=$($KUBECTL version -o json | jq -rj '.serverVersion|.major,".",.minor')
  INFO "Kubernetes version installed:  ${kubernetes_installed_version}"
  if [[ "${kubernetes_installed_version}" < "${kubernetes_min_version}" ]]
    then
      ERROR "Kubernetes version is too low. Update OVA for licence to be installed. Please contact
       support if more assistance is required."
      exit 2
  fi
  if which wget unzip $KUBECTL unzip >/dev/null
  then
    if [[ "${use_private_docker_registry}" == "true" ]]
    then
        if ! which docker >/dev/null
        then
            ERROR "Pre requirement check: FAILED"
            exit 2
        fi
    fi
    INFO "Pre requirement check: OK"
  else
    ERROR "Pre requirement check: FAILED"
    exit 2
  fi
}

function check_ls_exists() {
  INFO "Checking if the License Service is already installed"
  if ! verbose_output_command $KUBECTL get ibmlicensing --all-namespaces
  then
    version_installed=""
    INFO "License Service is not installed"
  else
    version_installed=$($KUBECTL get IBMLicensing instance --all-namespaces -o jsonpath='{.spec.version}')
    INFO "License Service seems to be installed with version ${version_installed}."
  fi
}

function create_namespace() {
  INFO "Creating licensing namespace ${licensing_namespace}"
  if ! verbose_output_command $KUBECTL get namespace "${licensing_namespace}"
  then
    INFO "Creating namespace ${licensing_namespace}"
    if ! $KUBECTL create namespace "${licensing_namespace}"
    then
      ERROR "kubectl command cannot create needed namespace"
      ERROR "make sure you are connected to your cluster where you want to install IBM License Service and have admin permissions"
      exit 3
    fi
  else
    INFO "Needed namespace: \"${licensing_namespace}\", already exists"
  fi
}

function fetch_sources() {
  # Yaml sources
  file_url="https://github.com/IBM/ibm-licensing-operator/archive/refs/heads/release-${operator_version}.zip"
  filename="ibm-licensing-operator-release-${operator_version}.zip"
  destination_folder=${tmp_folder}
  downloaded_file="${destination_folder}/${filename}"


  if [[ "${offline_install}" == "false" ]]
  then
    # Download requirements
    INFO "Fetching sources from ${file_url}"
    wget -q "${file_url}" -O "${downloaded_file}"
    if wget -q "${file_url}" -O "${downloaded_file}"
    then
        INFO "File download successful."
    else
        ERROR "File download failed."
        exit 1
    fi
  else
    # Offline installation
    downloaded_file="${offline_sources_folder}/${filename}"
    if [[ ! -f "${downloaded_file}" ]]
    then
        ERROR "File ${downloaded_file} not found."
        exit 1
    fi
  fi

  # unzip
  if unzip -o -q "$downloaded_file" -d "$destination_folder"
  then
      INFO "File unzip successful."
  else
      ERROR "File unzip failed."
      exit 1
  fi

  if ! cd /tmp/ibm-licensing-operator-release-${operator_version}/
  then
    ERROR "Path /tmp/ibm-licensing-operator-release-${operator_version}/ not found"
    exit 1
  fi

  \cp -rf config ${src_folder}
  # Docker images
  if [[ "${use_private_docker_registry}" == "true" ]]
  then
    # Docker images
    INFO "Pulling source images"
    docker pull icr.io/cpopen/ibm-licensing-operator:${operator_version}
    docker pull icr.io/cpopen/cpfs/ibm-licensing:${operator_version}
    # Before pushing the images to your private registry, make sure we are are logged in.
    if [[ "${use_private_docker_registry_creds}" == "true" ]]
    then
      INFO "Logging in docker registry ${my_docker_registry} using creds"
      docker login ${my_docker_registry} -u ${my_docker_registry_username} -p ${my_docker_registry_token}
    else
      INFO "Logging in docker registry ${my_docker_registry}"
      docker login ${my_docker_registry}
    fi
    INFO "Tagging the images with registry prefix and pushing them"
    docker tag icr.io/cpopen/ibm-licensing-operator:${operator_version} ${my_docker_registry}/ibm-licensing-operator:${operator_version}
    docker push ${my_docker_registry}/ibm-licensing-operator:${operator_version}
    docker tag icr.io/cpopen/cpfs/ibm-licensing:${operator_version} ${my_docker_registry}/ibm-licensing:${operator_version}
    docker push ${my_docker_registry}/ibm-licensing:${operator_version}
    # If your cluster needs the access token to your private Docker registry, create the secret in the dedicated installation namespace:
    if [[ "${use_private_docker_registry_creds}" == "true" ]]
    then
      INFO "Creating secret with the registry access token"
      $KUBECTL create secret -n ${licensing_namespace} docker-registry my-registry-token --docker-server=${my_docker_registry} \
      --docker-username=${my_docker_registry_username} --docker-password=${my_docker_registry_token} --docker-email=${my_docker_registry_username}
      sed -i -e "/name: ibm-licensing-operator$/{N;s/$/\nimagePullSecrets:\n- name: my-registry-token/}" ${src_folder}/config/rbac/service_account.yaml
    fi
  fi
}

function apply_yaml() {
  INFO "Applying RBAC roles, CRD and operator yaml"
  if [[ "${use_private_docker_registry}" == "true" ]]
  then
      INFO "Replacing image registry"
      ESCAPED_REPLACE=$(echo ${my_docker_registry} | sed -e 's/[\/&]/\\&/g')
      sed -i 's/icr\.io\/cpopen\/cpfs/'"${ESCAPED_REPLACE}"'/g' ${src_folder}/config/manager/manager.yaml
      sed -i 's/icr\.io\/cpopen/'"${ESCAPED_REPLACE}"'/g' ${src_folder}/config/manager/manager.yaml
  fi
  sed -i "s/annotations\['olm.targetNamespaces'\]/namespace/g" ${src_folder}/config/manager/manager.yaml
  sed -i "s/imagePullPolicy: Always/imagePullPolicy: IfNotPresent/g" ${src_folder}/config/manager/manager.yaml
  if [ "${licensing_namespace}" != "" ] && [ "${licensing_namespace}" != "ibm-common-services" ]
  then
    INFO "Replacing namespace"
    sed -i 's|ibm-common-services|'"${licensing_namespace}"'|g' ${src_folder}/config/rbac/*.yaml
    sed -i "s/annotations\['olm.targetNamespaces'\]/namespace/g" ${src_folder}/config/manager/manager.yaml
  fi
  INFO "Adding CRD"
  $KUBECTL apply -f ${src_folder}/config/crd/bases/operator.ibm.com_ibmlicensings.yaml
  $KUBECTL apply -f ${src_folder}/config/crd/bases/operator.ibm.com_ibmlicenseservicereporters.yaml
  $KUBECTL apply -f ${src_folder}/config/crd/bases/operator.ibm.com_ibmlicensingmetadatas.yaml
  $KUBECTL apply -f ${src_folder}/config/crd/bases/operator.ibm.com_ibmlicensingdefinitions.yaml
  $KUBECTL apply -f ${src_folder}/config/crd/bases/operator.ibm.com_ibmlicensingquerysources.yaml
  INFO "Adding RBAC"
  $KUBECTL apply -f ${src_folder}/config/rbac/role.yaml
  $KUBECTL apply -f ${src_folder}/config/rbac/role_operands.yaml
  $KUBECTL apply -f ${src_folder}/config/rbac/service_account.yaml
  $KUBECTL apply -f ${src_folder}/config/rbac/role_binding.yaml
  INFO "Adding operator"
  $KUBECTL apply -f ${src_folder}/config/manager/manager.yaml -n ${licensing_namespace}
}

function create_instance() {
  if ! verbose_output_command $KUBECTL get IBMLicensing instance -n ${licensing_namespace}
  then
    INFO "Creating the IBM Licensing instance"
    mkdir -p ${src_folder}/config/instance

    # create the yaml file for the instance
    cat << EOF > ${src_folder}/config/instance/ibmlicensings_instance.yaml
apiVersion: operator.ibm.com/v1
kind: IBMLicensingQuerySource
metadata:
  name: querysource
spec:
  aggregationPolicy: MAX
  query: "turbo_managed_workloads_count{}"
  annotations:
    cloudpakId: ""
    cloudpakMetric: ""
    cloudpakName: ""
    productCloudpakRatio: ""
    productID: "b40ccd47c8e64b9eb450c047d8abd614"
    productName: "IBM Turbonomic Application Resource Management"
    productMetric: "MANAGED_VIRTUAL_SERVER"
    productChargedContainers: "All"
---
apiVersion: operator.ibm.com/v1alpha1
kind: IBMLicensing
metadata:
  labels:
    app.kubernetes.io/instance: instance
    app.kubernetes.io/managed-by: instance
    app.kubernetes.io/name: instance
  name: instance
spec:
  version: ${operator_version}
  apiSecretToken: ibm-licensing-token
  datasource: datacollector
  httpsEnable: true
  ingressEnabled: false
  envVariable:
    PROMETHEUS_QUERY_SOURCE_ENABLED: "true"
    thanos_url: ${thanos_url}
  instanceNamespace: ${licensing_namespace}
  imagePullPolicy: IfNotPresent
  usageContainer:
    imagePullPolicy: IfNotPresent
EOF

    # add imagePullSecrets for private registry
    if [[ "${use_private_docker_registry_creds}" == "true" ]]
    then
      INFO "Setting imagePullSecrets for private registry"
      printf "  imagePullSecrets:\n    - my-registry-token" >> ${src_folder}/config/instance/ibmlicensings_instance.yaml
    fi
    # apply the yaml file for the instance
    if ! $KUBECTL apply -f ${src_folder}/config/instance/ibmlicensings_instance.yaml -n ${licensing_namespace}
    then
      ERROR "Failed to apply IBMLicensing instance at namespace ${licensing_namespace}"
      exit 19
    fi
  else
    INFO "IBMLicensing instance already exists"
  fi
}

function wait_for_ready() {
  INFO "Waiting for the ibm-licensing-operator pod to be ready"
  $KUBECTL wait --for=condition=ready pod -l name=ibm-licensing-operator -n ${licensing_namespace}
  INFO "Checking the ibm-licensing-service-instance status"
  retries=36
  ibmlicensing_phase=""
  until [[ ${retries} == 0 || "${ibmlicensing_phase}" == Running* ]]
  do
    if [[ "${retries}" != 36 ]]
    then
      INFO "Sleeping for 30 seconds"
      sleep 30
    fi
    retries=$((retries - 1))
    ibmlicensing_phase=$($KUBECTL get IBMLicensing instance -o jsonpath='{.status..phase}' -n ${licensing_namespace} 2>/dev/null)
    if [ "${ibmlicensing_phase}" == "Failed" ]
    then
      ERROR "Problem during installation of IBMLicensing, try running script again when fixed."
      exit 20
    elif [[ "${ibmlicensing_phase}" == "" ]]
    then
      INFO "Waiting for the ibm-licensing-service-instance pod to be ready"
    else
      INFO "IBMLicensing Pod phase: ${ibmlicensing_phase}"
    fi
  done
  if [[ ${retries} == 0 && "${ibmlicensing_phase}" != Running* ]]
  then
    ERROR "IBMLicensing instance pod failed to reach phase Running. Check ibm-licensing-operator pod logs."
    exit 21
  fi
}

function show_token() {
  if ! licensing_token=$($KUBECTL get secret ibm-licensing-token -o jsonpath='{.data.token}' -n "${licensing_namespace}" | base64 -d) || [ "${licensing_token}" == "" ]
  then
    WARN "Could not get ibm-licensing-token in ${licensing_namespace}, something might be wrong"
  else
    INFO "License Service secret for accessing the API is: $licensing_token"
  fi
}

function uninstall() {
  INFO "Uninstalling ibm-licensing-instance"
  INFO "Deleting the operator deployment"
  $KUBECTL delete deployment ibm-licensing-operator -n ${licensing_namespace}
  INFO "Deleting the role-based access control (RBAC) for operand"
  $KUBECTL delete RoleBinding ibm-license-service -n ${licensing_namespace}
  $KUBECTL delete RoleBinding ibm-license-service-restricted -n ${licensing_namespace}
  $KUBECTL delete ClusterRoleBinding ibm-license-service
  $KUBECTL delete ClusterRoleBinding ibm-license-service-restricted
  $KUBECTL delete ClusterRoleBinding ibm-licensing-default-reader
  $KUBECTL delete ServiceAccount ibm-license-service -n ${licensing_namespace}
  $KUBECTL delete ServiceAccount ibm-license-service-restricted -n ${licensing_namespace}
  $KUBECTL delete ServiceAccount ibm-licensing-default-reader -n ${licensing_namespace}
  $KUBECTL delete Role ibm-license-service -n ${licensing_namespace}
  $KUBECTL delete Role ibm-license-service-restricted -n ${licensing_namespace}
  $KUBECTL delete ClusterRole ibm-license-service
  $KUBECTL delete ClusterRole ibm-license-service-restricted
  $KUBECTL delete ClusterRole ibm-licensing-default-reader
  INFO "Deleting the role-based access control (RBAC) for operator"
  $KUBECTL delete RoleBinding ibm-licensing-operator -n ${licensing_namespace}
  $KUBECTL delete ClusterRoleBinding ibm-licensing-operator
  $KUBECTL delete ServiceAccount ibm-licensing-operator -n ${licensing_namespace}
  $KUBECTL delete Role ibm-licensing-operator -n ${licensing_namespace}
  $KUBECTL delete ClusterRole ibm-licensing-operator
  INFO "Deleting the Custom Resource Definition (CRD)"
  $KUBECTL delete CustomResourceDefinition ibmlicensings.operator.ibm.com
  $KUBECTL delete CustomResourceDefinition ibmlicenseservicereporters.operator.ibm.com
  $KUBECTL delete CustomResourceDefinition ibmlicensingdefinitions.operator.ibm.com
  $KUBECTL delete CustomResourceDefinition ibmlicensingmetadatas.operator.ibm.com
  $KUBECTL delete CustomResourceDefinition ibmlicensingquerysources.operator.ibm.com
  if [[ "${use_private_docker_registry}" == "true" ]]
  then
    INFO "Deleting images from private registry"
    docker rmi ${my_docker_registry}/ibm-licensing-operator:${operator_version}
    docker rmi ${my_docker_registry}/ibm-licensing:${operator_version}
  fi
  INFO "Waiting ibm-licensing-operator pod to terminate"
  $KUBECTL wait --for=delete pod -l name=ibm-licensing-operator --timeout=60s -n ${licensing_namespace}
  INFO "Waiting ibm-licensing-service-instance pod to terminate"
  $KUBECTL wait --for=delete pod -l app.kubernetes.io/name=ibm-licensing-service-instance  \
  --timeout=60s -n ${licensing_namespace}
}

function main() {
  print_args
  check_ls_exists
  if [[ ( "${uninstall}" == "true" && "${version_installed}" != "" ) || ( "${version_installed}" != "" && "${version_installed}" != "${operator_version}" ) ]]
  then
    uninstall
    INFO "IBM License Service v${version_installed} has been removed."
    check_ls_exists
  fi
  if [[ "${uninstall}" == "false" ]]
  then
    if [[ "${version_installed}" == ""  ]]
    then
      check_pre_req
      create_sources_folder
      create_namespace
      fetch_sources
      apply_yaml
      create_instance
    fi
      wait_for_ready
      show_token
      INFO "IBM License Service is ready."
  fi
}

# Start
main