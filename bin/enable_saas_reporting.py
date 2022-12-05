#!/usr/bin/env python3

import argparse
import logging
import os
import subprocess
import sys
import time
from datetime import datetime, timedelta
from getpass import getpass
from typing import Callable

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


class SaaSReporting:

    connectorBasePath = 'spec kinesis-kafka-connect'
    connectorPropertiesBasePath = connectorBasePath + ' connector'
    connectorDeliveryStreamPath = connectorPropertiesBasePath + ' config kinesis_delivery_stream'
    connectorAccessKeyIdPath = connectorPropertiesBasePath + ' aws_access_key aws_access_key_id'
    connectorSecretAccessKeyPath = connectorPropertiesBasePath + ' aws_access_key aws_secret_access_key'

    def __init__(self, custom_resource):
        self.custom_resource = custom_resource

    def enable(self, delivery_stream, aws_access_key_id, aws_secret_access_key):

        # Enable the extractor
        self.custom_resource.set_value('spec extractor enabled', True)

        # Enable data extraction
        self.custom_resource.set_value('spec properties extractor enableDataExtraction', True)

        # Enable and configure the connector
        self.custom_resource.set_value(SaaSReporting.connectorBasePath + ' enabled', True)
        self.custom_resource.set_value(SaaSReporting.connectorDeliveryStreamPath, delivery_stream)
        self.custom_resource.set_value(SaaSReporting.connectorAccessKeyIdPath, aws_access_key_id)
        self.custom_resource.set_value(SaaSReporting.connectorSecretAccessKeyPath, aws_secret_access_key)

    def is_enabled(self):
        # This is the primary flag that determines whether saas reporting is enabled or not.
        # We need both the connector and data extraction running.
        return self.custom_resource.get_value('spec kinesis-kafka-connect enabled', False) \
               and self.custom_resource.get_value('spec properties extractor enableDataExtraction', False) \
               and self.custom_resource.get_value('spec extractor enabled', False)

    def validate(self):
        warnings = []
        if self.is_enabled():
            # TODO: maybe check for the saas reporting feature flag
            self.check_password(SaaSReporting.connectorAccessKeyIdPath, warnings)
            self.check_password(SaaSReporting.connectorSecretAccessKeyPath, warnings)
            self.check_property_present(SaaSReporting.connectorDeliveryStreamPath, warnings)
        else:
            warnings.append('SaaS Reporting is not enabled')

        try:
            self.custom_resource.validate()
        except Exception as e:
            warnings.append("CR validation failed: {}".format(str(e)))

        return warnings

    def check_property_present(self, path, warnings_list):
        if self.custom_resource.get_value(path) is None:
            warnings_list.append("Missing field: {}".format(path))

    def check_password(self, path, warnings):
        pass_warn = validate_password(self.custom_resource.get_value(path))
        if pass_warn is not None:
            warnings.append("Problematic {} password: {}".format(path, pass_warn))


# Restarts API pod to apply new configuration changes when grafana and extractor pods finished creation/deletion
def apply_and_wait(custom_resource_file, timeout: timedelta, polling_interval: timedelta):
    # apply config changes in kubernetes and restart required containers containers
    apply_command = 'kubectl apply -f {}'.format(custom_resource_file)
    print("Applying CR file {}".format(custom_resource_file))
    subprocess.call(apply_command, shell=True)

    print("Waiting for changes to take effect...")

    def pods_are_ready() -> bool:

        # The shell command:
        #   1. gets the pods
        #   2. keeps only kinesis and extractor
        #   3. for each line it keeps only the READY column n/N
        #   4. it filters for lines where n is equal to N
        #   5. it counts the lines
        # Possible values 0, 1, 2
        check_ready_pods = "kubectl get pods | " + \
                           "egrep 'kinesis|extractor' | " + \
                           "awk '{print $2}' | " + \
                           "awk -F '/' '{ if($1 == $2) { print $0 } }' | " + \
                           "wc -l"
        stdout_value, stderr_value = subprocess.Popen(check_ready_pods, shell=True, stdout=subprocess.PIPE,
                                                      stderr=subprocess.STDOUT).communicate()
        check_ready_pods = int(stdout_value.decode().split("\n")[0])
        return check_ready_pods >= 2

    successful = wait_until_ready(ready=pods_are_ready, timeout=timeout, period=polling_interval)

    if successful:
        print("Necessary pods are ready.")
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


# Run a password input through some validation rules.
def validate_password(password_input):
    if len(password_input) == 0:
        return "Password must be non-empty."
    if "#" in password_input or ";" in password_input:
        return "Password should not contain # or ;"
    return None


def wait_for_password(msg):
    while True:
        if sys.stdin.isatty():
            password = getpass(msg)
        else:
            password = input()
        warning = validate_password(password)
        if warning is None:
            break
        else:
            print(warning)
    return password


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
    args = parser.parse_args()

    # File to modify - can be overwritten by passing cr file as an arg to the python script
    custom_resource_file = args.file
    if custom_resource_file is None:
        custom_resource_file = default_cr

    # Custom Resource Loader that loads/applies changes made to Custom Resource
    custom_resource = CustomResource(custom_resource_file)

    # The SaaS reporting component.
    saas_reporting = SaaSReporting(custom_resource)

    if args.validate:
        warnings = saas_reporting.validate()
        if len(warnings) > 0:
            print("Detected {} potential error(s) with SaaS reporting installation:".format(len(warnings)))
            for warning in warnings:
                print("    " + warning)
        else:
            print("No obvious SaaS reporting installation errors detected.")
        return

    if saas_reporting.is_enabled():
        print("SaaS reporting is already enabled. Please contact support if it is not working.")
        return

    # while True:
    #         if sys.stdin.isatty():
    #             password = getpass(msg)
    #         else:
    #             password = input()
    #         warning = validate_password(password)
    #         if warning is None:
    #             break
    #         else:
    #             print(warning)
    #     return password

    deliverySteam = input("Provide the name of the data streamed assigned to your account: ")
    awsAccessKeyId = wait_for_password("Provide the AWS Access Key ID: ")
    awsSecretAccessKey = wait_for_password("Provide the AWS Secret Access Key: ")
    saas_reporting.enable(deliverySteam, awsAccessKeyId, awsSecretAccessKey)

    # write out custom resource component
    custom_resource.write()

    if not args.no_apply:
        apply_and_wait(custom_resource_file, timeout=timedelta(minutes=10), polling_interval=timedelta(seconds=5))


if __name__ == "__main__":
    main()
