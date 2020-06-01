#!/usr/bin/python
import mysql.connector as mariadb
import logging
import sys
from datetime import datetime
import argparse
import subprocess
import sys

# This script restores historical statistics for the following entities:
# Application Server, Virtual Application, Database Server, Database, Load Balancer and Business Application.
# Running this script is optional -- Do not run it if your environment
# does not not contain those entities, or if you do not need that historical data.
# IMPORTANT: If your environment has a lot of data for these entities, the script
# can take a long time to complete (up to six hours).
#
# REQUIREMENTS:
# This script requires python and the module mysql-connector-python.
# On a default OVA run the following the commands:
# sudo yum install python-pip
# pip install mysql-connector-python --user
#
# If you need SSL for connections to the database, you must use python3
# and you must install pyopenssl with the command: pip install pyopenssl
#
# HOW TO RUN:
# These are brief instructions. For more information, see the section,
# “Restoring Historical Data After an Upgrade” in the Installation Guide.
#
# The script needs the following arguments: user, password, host, port number and database.
# For example:
# python convertMaxUtilizationToSettingOverride vmturbo root localhost 3306 vmtdb.
#
# After the script completes, bring the environment back up.
# To do this, just scale up the operator to back to one replica. For an example:
# kubectl scale deployment -n turbonoic t8c-operator --replicas=1

def install(package):
    subprocess.check_call([sys.executable, "-m", "pip", "install", package])

def set_logging_config():
    """
    Set the logging configurations for the log file (log everything) and the console (skip DEBUG)
    :return: None
    """
    log_format = '%(asctime)-20s %(levelname)-9s %(message)s'
    date_format = '%Y-%m-%d %H:%M:%S'
    # Only log Error/Info/Critical to the console, but log Everything to the file
    logging.basicConfig(level=logging.DEBUG,
                        format=log_format,
                        datefmt=date_format,
                        filename="convert_utilization_settings_{}.log".format(
                            datetime.now().strftime("%Y-%m-%d_%H-%M")))
    console = logging.StreamHandler()
    console.setLevel(logging.INFO)
    console.setFormatter(logging.Formatter(fmt=log_format, datefmt=date_format))
    logging.getLogger().addHandler(console)

tableToEntityType =	{
'app_server_stats_latest': "ApplicationServer",
'app_server_stats_by_hour': "ApplicationServer",
'app_server_stats_by_day': "ApplicationServer",
'app_server_stats_by_month': "ApplicationServer",
'business_app_stats_latest': "BusinessApplication",
'business_app_stats_by_hour': "BusinessApplication",
'business_app_stats_by_day': "BusinessApplication",
'business_app_stats_by_month': "BusinessApplication",
'load_balancer_stats_latest': "LoadBalancer",
'load_balancer_stats_by_hour': "LoadBalancer",
'load_balancer_stats_by_day': "LoadBalancer",
'load_balancer_stats_by_month': "LoadBalancer",
'db_server_stats_latest': "DatabaseServer",
'db_server_stats_by_hour': "DatabaseServer",
'db_server_stats_by_day': "DatabaseServer",
'db_server_stats_by_month': "DatabaseServer",
'virtual_app_stats_latest': "VirtualApp",
'virtual_app_stats_by_hour': "VirtualApp",
'virtual_app_stats_by_day': "VirtualApp",
'virtual_app_stats_by_month': "VirtualApp",
'db_stats_latest': "Database",
'db_stats_by_hour': "Database",
'db_stats_by_day': "Database",
'db_stats_by_month': "Database"
}

newTableToOldTableMapping = {
'app_server_stats_latest': 'app_stats_latest',
'app_server_stats_by_hour': 'app_stats_by_hour',
'app_server_stats_by_day': 'app_stats_by_day',
'app_server_stats_by_month': 'app_stats_by_month',
'business_app_stats_latest': 'app_stats_latest',
'business_app_stats_by_hour': 'app_stats_by_hour',
'business_app_stats_by_day': 'app_stats_by_day',
'business_app_stats_by_month': 'app_stats_by_month',
'load_balancer_stats_latest': "app_stats_latest",
'load_balancer_stats_by_hour': "app_stats_by_hour",
'load_balancer_stats_by_day': "app_stats_by_day",
'load_balancer_stats_by_month': "app_stats_by_month",
'db_server_stats_latest': "app_stats_latest",
'db_server_stats_by_hour': "app_stats_by_hour",
'db_server_stats_by_day': "app_stats_by_day",
'db_server_stats_by_month': "app_stats_by_month",
'virtual_app_stats_latest': "app_stats_latest",
'virtual_app_stats_by_hour': "app_stats_by_hour",
'virtual_app_stats_by_day': "app_stats_by_day",
'virtual_app_stats_by_month': "app_stats_by_month",
'db_stats_latest': "app_stats_latest",
'db_stats_by_hour': "app_stats_by_hour",
'db_stats_by_day': "app_stats_by_day",
'db_stats_by_month': "app_stats_by_month"
}
def main():
    parser = argparse.ArgumentParser(description='Script to migrate entities from old tables to new tables introduced in RB-36843. If you need to establish an ssl connection with the db just install pyopenssl and run with python3')
    parser.add_argument('user', type=str, nargs='+',
                        help='user that connects to the db')
    parser.add_argument('password', type=str, nargs='+',
                    help='password that connects to the db')
    parser.add_argument('host', type=str, nargs='+',
                        help='host where the db runs')
    parser.add_argument('port', type=str, nargs='+',
                        help='port on which the db runs')
    parser.add_argument('database', type=str, nargs='+',
                        help='name of the db')
    args = parser.parse_args()
    install("mysql-connector-python")
    set_logging_config()
    logging.info ("Logging into sql server")
    if len(sys.argv) != 6:
        logging.error("Error in passing the arguments, the order should be user, password, host, port and database name.")
    database=sys.argv[5]
    mariadb_connection = mariadb.connect(user = sys.argv[1], password = sys.argv[2], host = sys.argv[3], port = sys.argv[4], database=sys.argv[5])
    cursor = mariadb_connection.cursor()

    for newTable, entityType in tableToEntityType.items():
        try:
            oldTable = newTableToOldTableMapping[newTable]
            logging.info("Inserting {} into {} from {}".format(entityType, newTable, oldTable))
            cursor.execute("INSERT INTO {database}.{newTable} (SELECT {database}.{oldTable}.* FROM {database}.{oldTable}, {database}.entities WHERE {database}.{oldTable}.uuid = {database}.entities.id and {database}.entities.creation_class = '{entityType}')".format(database = database, newTable = newTable, entityType = entityType, oldTable = oldTable))
            insertedEntries = cursor.rowcount
            cursor.execute("DELETE FROM {database}.{oldTable} WHERE uuid IN (SELECT {database}.entities.uuid FROM {database}.entities WHERE {database}.entities.creation_class = '{entityType}')".format(newTable = newTable, entityType = entityType, oldTable = oldTable, database = database))
            deletedEntries = cursor.rowcount
            if insertedEntries == deletedEntries:
                logging.info("affected rows = {} for {}".format(cursor.rowcount, newTable))
                mariadb_connection.commit()
            else:
                logging.error("Number of inserted rows ({}) differ from the deleted ones({}), rolling back transaction".format(insertedEntries, deletedEntries))
                mariadb_connection.rollback

        except mariadb.Error as error:
            logging.error("Error {} on table {}".format(error, newTable))
            mariadb_connection.rollback

if __name__ == '__main__':
    main()
