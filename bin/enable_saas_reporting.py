#!/usr/bin/env python3

import argparse
import logging
import os
import subprocess
import sys
import time
from datetime import datetime, timedelta
from typing import Callable
from collections import namedtuple
from ruamel.yaml import YAML


class CustomResource:
    def __init__(self, custom_resource_file):
        self.yaml = YAML()
        self.custom_resource_file = custom_resource_file
        try:
            self.data = self.__read(self.custom_resource_file)
        except Exception as e:
            print("Failed to load CR file: {}. Error: {}".format(self.custom_resource_file, str(e)))
            sys.exit(1)

    # read and parse yaml file
    # return valid parsed yaml file or throw exception
    def __read(self, filename):
        with open(filename) as file:
            return self.yaml.load(file)

    # Attempt to validate the YAML by dumping and restoring it.
    def validate(self):
        intermediary_file = "{}.temp".format(self.custom_resource_file)

        with open(intermediary_file, 'w') as file:
            self.yaml.dump(self.data, file)

        try:
            self.__read(intermediary_file)
        finally:
            os.remove(intermediary_file)

    # tries to apply custom resource settings:
    # an intermediary file is created to represent the new CR file
    # the intermediary file is attempted to be read back in to verify yaml validity
    # on success, the previous CR file is renamed with a new extension of '.bak' and
    # the 'current cr' file now contains the new user selected values.
    # on failure, the process exits with no changes applies
    def write(self):
        intermediary_file = "{}.temp".format(self.custom_resource_file)

        with open(intermediary_file, 'w') as file:
            self.yaml.dump(self.data, file)

        try:
            self.__read(intermediary_file)
        except:
            os.remove(intermediary_file)
            print("Failed to modify CR with user selected options.")
            sys.exit(1)

        backup_filename = "{}.bak".format(self.custom_resource_file)
        os.rename(self.custom_resource_file, backup_filename)
        os.rename(intermediary_file, self.custom_resource_file)
        print("Successfully applied new changes to {}. Backup written to {}".format(
            self.custom_resource_file, backup_filename))

    # data is the yaml parsed cr file
    # path is a space delimited path of the key-value in yaml that needs to be modified
    # will create the key pair if one does not exist
    def set_value(self, path, value):
        if value is None:
            return

        path = path.split()
        key = path.pop()

        data = self.data
        for p in path:
            if p not in data:
                data[p] = dict()
            data = data[p]

        data[key] = value

    # retrieves value from yaml data
    # returns default (None by default) if key/path does not exist
    def get_value(self, path, default=None):
        path = path.split()
        key = path.pop()

        data = self.data
        for p in path:
            if p not in data:
                return default
            data = data[p]

        return data[key] if key in data else default


MSKUserInput = namedtuple('MSKUserInput', ['aws_access_key_id', 'aws_secret_access_key', 'msk_topic', 'msk_bootstrap_server'])


class SaasMSKReporting:
    extractor_path = "spec extractor"
    extractor_properties_path = "spec properties extractor"
    api_properties_path = "spec properties api featureFlags"

    def __init__(self, custom_resource):
        self.custom_resource = custom_resource

    def enable(self):
        if not hasattr(self, "user_input"):
            logging.error("User input is required.")
            sys.exit(1)
        self.custom_resource.set_value(SaasMSKReporting.extractor_path + ' enabled', True)
        self.custom_resource.set_value(SaasMSKReporting.extractor_path + ' enableAwsMsk', True)
        self.custom_resource.set_value(SaasMSKReporting.extractor_properties_path + ' enableAwsMsk', True)
        self.custom_resource.set_value(SaasMSKReporting.extractor_properties_path + ' enableDataExtraction', True)
        self.custom_resource.set_value(SaasMSKReporting.extractor_properties_path + ' enableEntityBlacklist', True)
        self.custom_resource.set_value(SaasMSKReporting.extractor_properties_path + ' enableEntityRelationWhitelist', True)
        self.custom_resource.set_value(SaasMSKReporting.extractor_properties_path + ' mskBootstrapServer', self.user_input.msk_bootstrap_server)
        self.custom_resource.set_value(SaasMSKReporting.extractor_properties_path + ' mskTopic', self.user_input.msk_topic)
        self.custom_resource.set_value(SaasMSKReporting.api_properties_path + ' saasReporting', True)

        # Deploy the tenant access key kubernetes secret
        os.system(f"kubectl create secret generic extractor-secret "
                  f"--from-literal=AWS_ACCESS_KEY_ID='{self.user_input.aws_access_key_id}' "
                  f"--from-literal=AWS_SECRET_ACCESS_KEY='{self.user_input.aws_secret_access_key}'")

    def disable(self):
        self.custom_resource.set_value(SaasMSKReporting.extractor_path + ' enabled', False)
        self.custom_resource.set_value(SaasMSKReporting.extractor_path + ' enableAwsMsk', False)
        self.custom_resource.set_value(SaasMSKReporting.extractor_properties_path + ' enableAwsMsk', False)
        self.custom_resource.set_value(SaasMSKReporting.extractor_properties_path + ' enableDataExtraction', False)
        self.custom_resource.set_value(SaasMSKReporting.extractor_properties_path + ' enableEntityBlacklist', False)
        self.custom_resource.set_value(SaasMSKReporting.extractor_properties_path + ' enableEntityRelationWhitelist', False)
        self.custom_resource.set_value(SaasMSKReporting.api_properties_path + ' saasReporting', False)

        # Remove secret
        os.system("kubectl delete secret extractor-secret")

    def is_enabled(self):
        return self.custom_resource.get_value(SaasMSKReporting.extractor_path + ' enabled', False) \
            and self.custom_resource.get_value(SaasMSKReporting.extractor_path + ' enableAwsMsk', False) \
            and self.custom_resource.get_value(SaasMSKReporting.extractor_properties_path + ' enableAwsMsk', False) \
            and self.custom_resource.get_value(SaasMSKReporting.extractor_properties_path + ' enableDataExtraction', False) \
            and self.custom_resource.get_value(SaasMSKReporting.extractor_properties_path + ' enableEntityBlacklist', False) \
            and self.custom_resource.get_value(SaasMSKReporting.extractor_properties_path + ' enableEntityRelationWhitelist', False) \
            and self.custom_resource.get_value(SaasMSKReporting.extractor_properties_path + ' mskBootstrapServer', False) \
            and self.custom_resource.get_value(SaasMSKReporting.extractor_properties_path + ' mskTopic', False) \
            and self.custom_resource.get_value(SaasMSKReporting.api_properties_path + ' saasReporting', False)

    def validate(self):
        if not self.is_enabled():
            print('SaaS Reporting is not enabled')
        else:
            try:
                self.custom_resource.validate()
                print('SaaS Reporting is enabled')
            except Exception as e:
                print(("CR validation failed: {}".format(str(e))))

    def check_property_present(self, path, warnings_list):
        if self.custom_resource.get_value(path) is None:
            warnings_list.append("Missing field: {}".format(path))

    def get_input_from_user(self):
        aws_access_key_id = input("Provide the AWS Access Key ID: ")
        aws_secret_access_key = input("Provide the AWS Secret Access Key: ")
        msk_topic = input("Provide the Kafka topic assigned to your account: ")
        msk_bootstrap_server = input("Provide the Kafka bootstrap server assigned to your account: ")
        self.user_input = MSKUserInput(aws_access_key_id, aws_secret_access_key, msk_topic, msk_bootstrap_server)

    def pods_are_ready(self) -> bool:

        # The shell command:
        #   1. gets the pods
        #   2. keeps only api and extractor
        #   3. for each line it keeps only the READY column n/N
        #   4. it filters for lines where n is equal to N
        #   5. it counts the lines
        # Possible values 0, 1, 2
        check_ready_pods = "kubectl get pods | " + \
                           "egrep 'api|extractor' | " + \
                           "awk '{print $2}' | " + \
                           "awk -F '/' '{ if($1 == $2) { print $0 } }' | " + \
                           "wc -l"
        stdout_value, stderr_value = subprocess.Popen(check_ready_pods, shell=True, stdout=subprocess.PIPE,
                                                      stderr=subprocess.STDOUT).communicate()
        check_ready_pods = int(stdout_value.decode().split("\n")[0])
        return check_ready_pods >= 2

    def pods_are_shutdown(self) -> bool:
        check_ready_pods = "kubectl get pods | " + \
                           "egrep 'extractor' | " + \
                           "awk '{print $2}' | " + \
                           "awk -F '/' '{ if($1 == $2) { print $0 } }' | " + \
                           "wc -l"
        stdout_value, stderr_value = subprocess.Popen(check_ready_pods, shell=True, stdout=subprocess.PIPE,
                                                      stderr=subprocess.STDOUT).communicate()
        check_ready_pods = int(stdout_value.decode().split("\n")[0])
        return check_ready_pods == 0


# Restarts Extractor and API pods to apply new configuration changes
def apply_and_wait(custom_resource_file, timeout: timedelta, polling_interval: timedelta, ready_condition: Callable[[], bool]):
    # apply config changes in kubernetes and restart required containers

    apply_command = 'kubectl apply -f {}'.format(custom_resource_file)
    print("Applying CR file {}".format(custom_resource_file))
    subprocess.call(apply_command, shell=True)

    print("Waiting for changes to take effect...")

    successful = wait_until_ready(ready=ready_condition, timeout=timeout, period=polling_interval)

    if not successful:
        print("Necessary pods are not created after timeout - Exiting")
        sys.exit(1)

    restart_api_pod_command = "kubectl delete pod -n turbonomic $(kubectl get pod -n turbonomic | grep api- | awk '{print $1}')"
    subprocess.call(restart_api_pod_command, shell=True)

    successful = wait_until_ready(ready=ready_condition, timeout=timeout, period=polling_interval)

    if successful:
        print("Updated configuration is successful.")
    else:
        print("Necessary pods are not created after timeout - Exiting")
        sys.exit(1)


def wait_until_ready(ready: Callable[[], bool], timeout: timedelta, period: timedelta) -> bool:
    start_time = datetime.now()

    success = False
    while datetime.now() - start_time < timeout:
        try:
            if ready():
                success = True
                break
        except Exception:
            logging.exception("exception raised while calling ready function")

        time.sleep(period.seconds)

        # print without newline
        sys.stdout.write(".")
        sys.stdout.flush()

    # add newline
    print("")
    return success


def main():
    default_cr = '/opt/turbonomic/kubernetes/operator/deploy/crds/charts_v1alpha1_xl_cr.yaml'

    parser = argparse.ArgumentParser(description='Enable/Disable SaaS Reporting on an XL CR.')
    parser.add_argument('--file',
                        help="Location where the CR is located.",
                        action='store', dest="file")
    # Flag to identify if we are restarting k8.
    parser.add_argument("--no-apply", help="Skip applying the CR after modification.", action="store_true",
                        dest="no_apply")
    parser.add_argument("--validate", help="Don't make any changes, but lint the CR to check for common errors.",
                        action="store_true", dest="validate")

    parser.add_argument("--disable", help="Disable streaming", action="store_true", dest="disable")

    args = parser.parse_args()

    # File to modify - can be overwritten by passing cr file as an arg to the python script
    custom_resource_file = args.file
    if custom_resource_file is None:
        custom_resource_file = default_cr

    # Custom Resource Loader that loads/applies changes made to Custom Resource
    custom_resource = CustomResource(custom_resource_file)

    saas_reporting = SaasMSKReporting(custom_resource)

    if args.disable:
        saas_reporting.disable()
        custom_resource.write()
        apply_and_wait(custom_resource_file, timeout=timedelta(minutes=10), polling_interval=timedelta(seconds=5),
                       ready_condition=saas_reporting.pods_are_shutdown)
        return

    if args.validate:
        saas_reporting.validate()
        return

    if saas_reporting.is_enabled():
        print("SaaS reporting is already enabled. Please contact support if it is not working.")
        return

    saas_reporting.get_input_from_user()
    saas_reporting.enable()

# write out custom resource component
    custom_resource.write()

    if not args.no_apply:
        apply_and_wait(custom_resource_file, timeout=timedelta(minutes=10), polling_interval=timedelta(seconds=5),
                       ready_condition=saas_reporting.pods_are_ready)


if __name__ == "__main__":
    main()
