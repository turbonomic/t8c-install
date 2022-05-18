#!/usr/bin/env python3

import argparse
import os
import subprocess
from subprocess import CompletedProcess
import sys
import time
import json
from typing import Callable
from datetime import datetime, timedelta
import logging
from getpass import getpass

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
        print("Succesfully applied new changes to {}. Backup written to {}".format(
            self.custom_resource_file, backup_filename))

    # data is the yaml parsed cr file
    # path is a space delimeted path of the key-value in yaml that needs to be modified
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


class EmbeddedReporting:
    grafana_admin_password_path = 'spec grafana adminPassword'
    grafana_db_password_path = 'spec grafana grafana.ini database password'
    grafana_database_type_path = 'spec grafana grafana.ini database type'
    timescaledb_path = 'spec global externalTimescaleDBIP'

    def __init__(self, custom_resource):
        self.custom_resource = custom_resource

    def enable(self, grafana_admin_password, grafana_db_password):
        self.custom_resource.set_value('spec grafana enabled', True)
        self.custom_resource.set_value('spec reporting enabled', True)
        self.custom_resource.set_value('spec timescaledb enabled', True)
        self.custom_resource.set_value('spec extractor enabled', True)

        # set timescaleDBIP if it hasn't been set.
        if self.custom_resource.get_value(EmbeddedReporting.timescaledb_path) == None:
            # externalIP represents the OVAs IP
            externalIP = self.custom_resource.get_value('spec global externalIP')
            # use externalIP for timescaleDB IP
            self.custom_resource.set_value(EmbeddedReporting.timescaledb_path, externalIP)

        # set database-type if it hasn't been set.
        if self.custom_resource.get_value(EmbeddedReporting.grafana_database_type_path) == None:
            self.custom_resource.set_value(EmbeddedReporting.grafana_database_type_path, 'postgres')

        self.custom_resource.set_value(EmbeddedReporting.grafana_admin_password_path, grafana_admin_password)
        self.custom_resource.set_value(EmbeddedReporting.grafana_db_password_path, grafana_db_password)

    def is_enabled(self):
        # This is the primary flag that determines whether reporting is enabled or not.
        # Grafana, timescaledb, and extractor can be enabled/disabled for other reasons.
        return self.custom_resource.get_value('spec reporting enabled', False)

    def validate(self):
        warnings = []
        if self.is_enabled():
            self.check_property_enabled("grafana", warnings)
            self.check_property_enabled("reporting", warnings)
            self.check_property_enabled("extractor", warnings)
            self.check_property_enabled("timescaledb", warnings)
            self.check_password(EmbeddedReporting.grafana_admin_password_path, warnings)
            self.check_password(EmbeddedReporting.grafana_db_password_path, warnings)
            self.check_property_present(EmbeddedReporting.grafana_database_type_path, warnings)
            self.check_property_present(EmbeddedReporting.timescaledb_path, warnings)

        try:
            self.custom_resource.validate()
        except Exception as e:
            warnings.append("CR validation failed: {}".format(str(e)))

        return warnings

    def check_property_enabled(self, component, warnings_list):
        if not self.custom_resource.get_value('spec {} enabled'.format(component), False):
            warnings_list.append("spec.{}.enabled should be true".format(component))

    def check_property_present(self, path, warnings_list):
        if self.custom_resource.get_value(path) == None:
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
    time.sleep(10)

    def pods_are_ready() -> bool:
        check_ready_pods = "kubectl get pods -n turbonomic | egrep -c 'grafana.*1/|extractor.*1/'"
        stdout_value, stderr_value = subprocess.Popen(check_ready_pods, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT).communicate()
        check_ready_pods = int(stdout_value.decode().split("\n")[0])
        return check_ready_pods >= 2

    successful = wait_until_ready(ready=pods_are_ready, timeout=timeout, period=polling_interval)

    if successful:
        print("Grafana/Extractor pods are ready.")
    else:
        print("Grafana/Extractor pods are not created after timeout - Exiting")
        sys.exit(1)

    print("Restarting api pod to apply configuration changes.")

    restart_api_pod_command = "kubectl delete pod -n turbonomic $(kubectl get pod -n turbonomic | grep api- | awk '{print $1}')"
    subprocess.call(restart_api_pod_command, shell=True)

    print("Waiting for api pod to become ready...")

    def api_pod_is_ready() -> bool:
        _command = "kubectl get deploy api -n turbonomic -o json"
        result: CompletedProcess = subprocess.run(_command, shell=True, stdout=subprocess.PIPE)
        status: dict = json.loads(result.stdout)['status']
        return status.get('availableReplicas', 0) == 1 and status.get('unavailableReplicas', 0) == 0

    successful = wait_until_ready(api_pod_is_ready, timeout=timeout, period=polling_interval)

    if successful:
        print("api pod is now ready.")
        print("Changes have been successfully applied. Embedded reporting is now enabled.")
    else:
        print("Timed out while waiting for api pod to become ready. Exiting.")


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


def collect_input(prompt, validation_fn):
    collected_input = ""
    while True:
        collected_input = input(prompt)
        warning = validation_fn(collected_input)
        if warning is None:
            break
        else:
            print(warning)
    return collected_input


# Run a password input through some validation rules.
def validate_password(password_input):
    if len(password_input) == 0:
        return "Password must be non-empty."
    if len(password_input) >= 100:
        return "Password must be shorter than 100 characters"
    if len(password_input) < 5:
        return "Password must be longer than 5 characters."
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

# Checks to see if a service is running.
def is_service_running(service_name):
    ACTIVE_SERVICE = 'active (running)'
    check_service_status = 'service {} status'.format(service_name)
    stdout_value, stderr_value = subprocess.Popen(check_service_status, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT).communicate()
    return True if ACTIVE_SERVICE in str(stdout_value) else False

def main():
    default_cr = '/opt/turbonomic/kubernetes/operator/deploy/crds/charts_v1alpha1_xl_cr.yaml'

    parser = argparse.ArgumentParser(description='Enable/Disable Embedded Reporting on an XL CR.')
    parser.add_argument('--file',
                        help="Location where the CR is located.",
                        action='store', dest="file")
    # Flag to identicate if we are restarting k8.
    parser.add_argument("--no-apply", help="Skip applying the CR after modification.", action="store_true", dest="no_apply")
    parser.add_argument("--validate", help="Don't make any changes, but lint the CR to check for common errors.",
                        action="store_true", dest="validate")
    parser.add_argument("--no-timescaledb", help="Skip the precondition of needing timescaledb enabled.",
                        action="store_true", dest="no_timescaledb")
    args = parser.parse_args()

    # precondition(s)
    if not args.no_timescaledb:
        # 1. timescaledb must be installed and running as a service natively.
        timescaledb_name = 'postgresql-12.service'
        if not is_service_running(timescaledb_name):
            print("Embedded Reporting requires TimescaleDB to be installed. Please install TimescaleDB and rerun enable_reporting.py.")
            return

    # File to modify - can be overwritten by passing cr file as an arg to the python script
    custom_resource_file = args.file
    if custom_resource_file is None:
        custom_resource_file = default_cr

    # Custom Resource Loader that loads/applies changes made to Custom Resource
    custom_resource = CustomResource(custom_resource_file)

    # The embedded reporting component.
    embedded_reporting = EmbeddedReporting(custom_resource)

    if args.validate:
        warnings = embedded_reporting.validate()
        if len(warnings) > 0:
            print("Detected {} potential error(s) with embedded reporting installation:".format(len(warnings)))
            for warning in warnings:
                print("    " + warning)
        else:
            print("No obvious embedded reporting installation errors detected.")
        return

    if embedded_reporting.is_enabled():
        print("Embedded reporting is already enabled. Please contact support if it is not working.")
        return

    grafana_admin_password = wait_for_password("Set initial Grafana Administrator password: ")
    grafana_db_password = wait_for_password("Set Grafana database password: ")
    embedded_reporting.enable(grafana_admin_password, grafana_db_password)

    # write out custom resource component
    custom_resource.write()

    if not args.no_apply:
        apply_and_wait(custom_resource_file, timeout=timedelta(minutes=10), polling_interval=timedelta(seconds=5))


if __name__ == "__main__":
    main()
