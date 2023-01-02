#!/usr/bin/env python3

import http.client
import json
import subprocess
import logging
import sys
import time
import argparse

class MonitorTask:

  def __init__(self, namespace: str, service_name: str, url_host: str, url_port: int, url_path: str):
    self.namespace: str = namespace
    self.service_name: str = service_name
    self.url_host: str = url_host
    self.url_port: int = url_port
    self.url_path: str = url_path

  def doRun(self):

    host = self.url_host if self.url_host else self.get_service_ip()
    port = self.url_port if self.url_port else self.get_service_port()

    site_id = self.get_site_id()

    body = {
      "timestamp": int(time.time()),
      "versionmanagers": self.get_vmgrs(),
      "turbonomicclients": self.get_tcs(),
      "pods": self.get_pods(),
    }

    self.publish_data(host=host, port=port, site_id=site_id, body=body)

  def get_service_ip(self) -> str:
    cmd = f"kubectl get service {self.service_name} -n {self.namespace} -o jsonpath='{{.spec.clusterIP}}'"
    return MonitorTask.run_command(cmd)

  def get_service_port(self) -> int:
    cmd = f"kubectl get service {self.service_name} -n {self.namespace} -o jsonpath='{{.spec.ports[0].port}}'"
    return int(MonitorTask.run_command(cmd))

  def get_site_id(self) -> str:
    cmd = f"kubectl get configmap skupper-site -n {self.namespace} -o jsonpath='{{.metadata.uid}}'"
    return MonitorTask.run_command(cmd)

  def get_vmgrs(self) -> dict:
    cmd = f"kubectl get versionmanagers -n {self.namespace} -o jsonpath='{{.items}}'"
    vmgrs: list = json.loads(MonitorTask.run_command(cmd))
    return {vmgr["metadata"]["name"]: vmgr["status"] for vmgr in vmgrs}

  def get_tcs(self) -> dict:
    cmd = f"kubectl get turbonomicclients -n {self.namespace} -o jsonpath='{{.items}}'"
    tcs: list = json.loads(MonitorTask.run_command(cmd))
    return {tc["metadata"]["name"]: tc["spec"] for tc in tcs}

  def get_pods(self) -> dict:
    cmd = f"kubectl get pods -n {self.namespace} -o jsonpath='{{.items}}'"
    pods: list = json.loads(MonitorTask.run_command(cmd))
    return {p["metadata"]["name"]: p["status"]["containerStatuses"] for p in pods}

  @staticmethod
  def run_command(cmd: str) -> str:
    status, out = subprocess.getstatusoutput(cmd)

    if status != 0:
      raise Exception(out)
    
    return out

  def publish_data(self, host: str, port: int, site_id: str, body: dict):
    conn = http.client.HTTPConnection(host=host, port=port, timeout=10)

    conn.request(method="POST", url=self.url_path.format(site_id=site_id), body=json.dumps(body))
    res = conn.getresponse()

    if res.status != 200:
      raise Exception(f"Request to publish data failed: {res.status} {res.reason}")

    conn.close()

  def __call__(self):
    logging.info("Running MonitorTask...")
    try:
      self.doRun()
    except Exception as e:
      logging.exception("Exception raised.")

    logging.info("MonitorTask completed.")

if __name__ == '__main__':

  ap = argparse.ArgumentParser(add_help=True)
  ap.add_argument("-n", "--namespace", default="turbonomic", type=str, help="The Kubernetes namespace to use")
  ap.add_argument("--service-name", default="remote-nginx-tunnel", type=str, help="The Kubernetes service to use")
  ap.add_argument("--host", type=str, help="The URL host to use for the heartbeat API")
  ap.add_argument("--port", type=int, help="The URL port to use for the heartbeat API")
  ap.add_argument("--path", default="/client-network/sites/{site_id}/data", type=str, help="The URL path to use for the heartbeat API")
  args = ap.parse_args()

  logging.basicConfig(
    format='%(asctime)s %(levelname)-8s %(message)s',
    stream=sys.stdout,
    level=logging.INFO
  )

  task = MonitorTask(
    namespace=args.namespace,
    service_name=args.service_name,
    url_host=args.host,
    url_port=args.port,
    url_path=args.path
  )

  task()

