#!/usr/bin/env python3

import argparse
import os
import subprocess
import sys
import time

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

        return data[key]


class EmbeddedReporting:
    grafana_admin_password_path = 'spec grafana adminPassword'
    grafana_db_password_path = 'spec grafana grafana.ini database password'

    def __init__(self, custom_resource):
        self.custom_resource = custom_resource

    def enable(self, grafana_admin_password, grafana_db_password):
        self.custom_resource.set_value('spec grafana enabled', True)
        self.custom_resource.set_value('spec reporting enabled', True)
        self.custom_resource.set_value('spec timescaledb enabled', True)
        self.custom_resource.set_value('spec extractor enabled', True)

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

        try:
            self.custom_resource.validate()
        except Exception as e:
            warnings.append("CR validation failed: {}".format(str(e)))

        return warnings

    def check_property_enabled(self, component, warnings_list):
        if not self.custom_resource.get_value('spec {} enabled'.format(component), False):
            warnings_list.append("spec.{}.enabled should be true".format(component))

    def check_password(self, path, warnings):
        pass_warn = validate_password(self.custom_resource.get_value(path))
        if pass_warn is not None:
            warnings.append("Problematic {} password: {}".format(path, pass_warn))


# Restarts API pod to apply new configuration changes when grafana and extractor pods finished creation/deletion
def apply_and_wait(custom_resource_file, timeout, polling_interval_s):
    # apply config changes in kubernetes and restart required containers containers
    apply_command = 'kubectl apply -f {}'.format(custom_resource_file)
    print("Applying CR file {}".format(custom_resource_file))
    subprocess.call(apply_command, shell=True)

    print("Waiting for changes to take effect...")
    time.sleep(10)

    current_time = 0
    is_result_success = False

    restart_api_pod_command = "kubectl delete pod $(kubectl get pod | grep api- | awk '{print $1}')"

    while current_time < timeout:
        check_ready_pods = 'kubectl get pods -n turbonomic | egrep -c \'grafana.*1/|extractor.*1/\''
        stdout_value, stderr_value = subprocess.Popen(check_ready_pods, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT).communicate()
        check_ready_pods = int(stdout_value.decode().split("\n")[0])
        if check_ready_pods >= 2:
            is_result_success = True
            print("Restarting api pod to apply configuration changes.")
            subprocess.call(restart_api_pod_command, shell=True)
            # Wait a little bit to give the API a head start when its coming back up.
            time.sleep(10)
            break
        print("Changes have not been fully applied. Sleeping for another {} seconds.".format(polling_interval_s))
        current_time = current_time + polling_interval_s
        time.sleep(polling_interval_s)

    if is_result_success:
        print("Changes have been successfully applied. Embedded reporting is now enabled.")
    else:
        print("Grafana/Extractor pods are not created after timeout - Exiting")
        sys.exit(1)


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
    args = parser.parse_args()

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

    grafana_admin_password = collect_input("Set initial Grafana Administrator password: ", validate_password)
    grafana_db_password = collect_input("Set Grafana database password: ", validate_password)
    embedded_reporting.enable(grafana_admin_password, grafana_db_password)

    # write out custom resource component
    custom_resource.write()

    if not args.no_apply:
        apply_and_wait(custom_resource_file, 600, 30)


if __name__ == "__main__":
    main()
