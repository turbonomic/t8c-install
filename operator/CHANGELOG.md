T8C-Operator Changelog
====================

Operator Versions
---------------------
42.38
1. Removed SAAS deploymentMode, added logic to convert SAAS to HYBRID_SAAS in configmap.
2. Enable single class loader for mediation-awscloudbilling to enable metrics.
3. Update latest crd.yaml version with enable msk block for saas reporting
4. Sharing turbo_discovered_entities for PLG 

42.37
1. Enable single class loader for mediation-aws to enable metrics.
2. Enable passing environment variables to the server-power-modeler via the CR file.
3. Propagate tolerations from CR into deployments that don't already have them.

42.36
1. Granted permissions to client-network-service to list Services and OpenShift Routes.
2. Update prometheus-mysqld-exporter image to v0.14.0.4. Fix CVE-2023-29404
3. update prometheus/node_exporter image to v1.6.0.1. Fix for CVE-2023-29404
4. Added connection timeout setting winrm-proxy. 
5. Added additional configuration to embed tenantId and ibmUniqueId into api component properties.

42.35
1. Enable online telemetry by default
2. Added custom database name configuration support for suspend
3. Removed unused database configuration parameters for suspend
4. Update prometheus to use offical Docker image to address CVE-2023-29404 and others.
5. Update prometheus kafka adapter image to v1.8.0.4, fix for CVE-2023-29404
6. Update configmap-reload image to v0.8.0.4, fix for CVE-2023-29404. 

42.34
1. Removed redundant Redis secret mount path for suspend
2. Added DB secret mount path environment variable for suspend
3. updated clustermgr label
4. update prometheus/node_exporter to v1.6.0, fix for CVE-2023-24538
5. Update prometheus-mysqld-exporter image to v0.14.0.3. Fix CVE-2023-24540
6. Fixed ensuring that the operator now properly respects the AWS Prometheus parameters
7. Removed default security context for Prometheus so that it can run on OpenShift.
8. Added new metric to prometheus: turbo_managed_workloads_count

42.33
1. Changes to configure workerConnections and workerProcesses parameters from CR for nginx
2. Changed default Prometheus component(s) configuration to require less permissions and resources.
3. Added additional configuration options for Prometheus component(s).
4. Add support for defining external labels.
5. Fix CVE-2023-24540 in configmap-reload
6. Enable server-power-modeler by default.
7. Update prometheus kafka adapter image to v1.8.0.3, fix for CVE-2023-24540
8. Allow specification of security context in prometheus.server CR file section.
9. Add saas reporting export through msk

42.32
1. Add properties in mediation-hyperv and mediation-vmm pods to support proxy mode.
2. Add policy evaluator config for suspend service
3. Allow overriding sharing telemetry setting via shareTelemetry setting.
4. Fix handling of nonstandard external DB ports (for `db`, `postgres` and `timescaledb` services)
5. Add group discoverer engine config for suspend service

42.31
1. Update prometheus image to v2.42.0.2
2. Update prometheus kafka adapter image to v1.8.0.2
3. Update configmap-reload to v0.8.0.2 (change Go version to 1.20.3)

42.30
1. Give metrics-processor service access to topology-processor's persistent volume
2. Updated timescaledb image to version 2.10.2.

42.29
1. Update Kube State Metrics version to use no Go version to resolve CVE vulnerabilities
2. Security patches for prometheus/mysqld_exporter 
3. Updated prometheus-kafka-adapter image to 1.8.0.1, updating the golang version to 1.20.2.

42.28
1. Add new defaults and configurations to kinesis kafka connect helm chart for bug. 
2. Enabled GCP Infrastructure Probe by default, if GCP probe is enabled.
3. Added insecureHttpOnly so non-SSL requests will not be redirected even nginx is acting as primary ingress

42.27
1. Enabled Suspend(Parking) service by default
2. Added `metrics-processor` component for metrics collection on certain cloud entities. Disabled by default.
3. Enabled Azure Pricing Probe by default if azure enabled.
4. Updated prometheus-kafka-adapter image to 1.8.2 tag with updated golang.org/x/net version.
5. Add telemetry scrubber component.
6. Added support for customizing telemetry destination at runtime and injecting a default during the
   build.
7. Security patches for prometheus and configmap-reload.
8. Security patches for prometheus/mysqld_exporter.
9. Security patches for prometheus/node_exporter.

42.26
1. IWO SPECIFIC RELEASE: Fix when multiple controllers are managing a resource in a conflicting manner, they can get stuck in an endless reconciliation cycle.

42.25
1. Add Kafka Kinesis connector component for telemetry.
2. Enabled Azure Infrastructure Probe by default if azure is enabled.
3. Added `telemtry.frontEnd.enabled` config to indicate frontEnd telemetry feature is enabled or disabled. 
4. Added missing resources to helm charts and crd, so it can be configured through cr.
5. Updated prometheus-kafka-adapter image to 1.8.1 tag with updated golang version.
6. Added new metrics-adapter-aws component to helm charts. Disabled by default.

42.24
1. Added parkingEnabled config to indicate suspend features are enabled/disabled.
2. Allow suspend services deploy on OpenShift platform
3. Fixed Client network service to push logs to rsyslog.
4. Add new telemetry counters: turbo_schedule_overrides, turbo_timespan_schedules
5. Add new telemetry gauge: turbo_suspendable_entities
6. Added power-modeler/server-power-modeler module to helm charts
7. Changed prometheus-server, node-exporter, pushgateway and alertmanager versions for security 
   issue. Also, disabled alertmanager and pushgatway as they are not used.

42.23
1. Add new telemetry gauge: turbo_actions
2. Remove NAMESPACE from API component environment - no longer required

42.22
1. Set the operator to point to the icr.io/cpopen/turbonomic registry
2. Change CustomImageName to false, to pull in the proper image names in the icr registry

42.21
1. Use data streams for kinesis kafka connect and deploy access key secret from script

42.20
1. Fixed a bug where log messages would get lost in a Turbo Secure Connect environment
2. Disable the default containerized DB creation step for new installation by adding an `externalDbIp` field under the `spec/global` section of the CR yaml file.

42.19
1. Added the AWS Kinesis connector to the helm charts
2. Add new telemetry gauge: turbo_automated_entities
3. Support field upgrading when suspend enabled

42.18
1. Fix IBM PowerVM probe charts
2. Rename ibmpowerhmc to powervm
3. Add support for Azure and GCP Infra probes.
4. Added config needed for enforcer engine of suspend
5. Added config needed for action orchestrator status listener engine of suspend

42.17
1. Added support for running Prometheus server using a namespaced role.
2. Moved out-of-the-box scrape jobs for Prometheus behind feature flags.
3. Disabled by default certain Prometheus helper pods that aren't currently required.

42.16
1. Fixed a bug where prometheus-server pod would get stuck in `ContainerCreating` state in 
   Kubernetes `1.14.3`.
2. Enabled Azure Billing Probe by default if azure is enabled.
3. Support individually defined properties for syslog file size and count in CR.

42.15
1. Inject NAMESPACE into the API component environment for use by the telemetry API.
2. Add helm charts for Azure Pricing Probe.

42.14
1. Removed containers responsible for sending telemetry to DataCloud from Prometheus server pod.
2. Added container responsible for sending telemetry to a Kafka topic to Prometheus server pod.
3. Various improvements related to telemetry testing, troubleshooting and configuration.
4. Make consul persistent volume sizing configurable through the CR.

42.13
1. Bootstrap hydra startup with system secret that it needs and DSN

42,12
1. add helm charts to add volumes for kube secrets

42.11
1. Added hydra to the helm charts.

42.10
1. Created the probe for Tanium integration

42.9
1. Update nginx helm template for hydra configuration.

42.8
1. ---

42.7
1. Listen and redirect from HTTP to HTTPS with Istio VirtualGateway

42.6
1. Provide whitelist ip filtering for nginx into remoteMediation path for remote probe-tp communication
2. Created the probe for Flexera integration

42.5
1. Removed data cloud flat collector
2. Updated Prometheus server version to 2.32.0
3. Updated Prometheus->DataCloud gateway version
4. Enabled GCP probe by default 
5. Enable the IBM FlashSystem probe by default

42.4
1. Use v1 clusterrolebinding for prometheus server kubernetes cluster role

42.3
1. Remove openjdk from baseimage
2. Support mTLS between kafka and services
3. Remove buffer pool for container db
4. SaaS Reporting: Self-Provisioning Grafana Image

42.2
1. Remove arangodb
2. Create probe for ibm-flashstorage
3. Add a second DataCloud gateway targeting graph to XL back-end telemetry

Compatibility Matrix
--------------------

This section will list which t8c-operator version is shipped with which Turbo platform release.  
This doesn't mean that from a specific Turbo release the customer needs to use that specific 
operator version (even if we recommend it).  
As a guideline, an old operator version can be used, but compatibility is guaranteed only when the 
major version is the same one. In this case, Turbo will work, but extra functionality might not 
(see the changelog list above for details).  
If an old operator with a major version difference is used, then expect breaking changes, as 
illustrated in the changelog, and follow the instructions to change the CR, in order to upgrade 
to newer versions.

| Turbo platform (CWOM in parenthesis) | t8c-operator |
|--------------------------------------|--------------|
| 8.4.4 (3.2.4)                        | 42.5         |
| 8.4.3 (3.2.3)                        | 42.5         |
| 8.4.2 (3.2.2)                        | 42.4         |
| 8.4.1 (3.2.1)                        | 42.4         |
| 8.4.0 (3.2.0)                        | 42.3         |
| 8.3.6 (3.1.6)                        | 42.3         |
| 8.3.5 (3.1.5)                        | 42.3         |
| 8.3.4 (3.1.4)                        | 42.2         |
| 8.3.3 (3.1.3)                        | 42.1         |
| 8.3.2 (3.1.2)                        | 42.1         |
| 8.3.1 (3.1.1)                        | 42.0         |
| 8.3.0 (3.1.0)                        | 8.2          |
| 8.2.1 - 8.2.7 (3.0.1 - 3.0.7)        | 8.2          |
| 8.1.2 - 8.2.0                        | 8.1          |
| 8.0.3 - 8.1.1                        | 8.0          |
| 8.0.0 - 8.0.2                        | 7.22         |


