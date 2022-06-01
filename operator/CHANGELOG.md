T8C-Operator Changelog
====================

Operator Versions
---------------------
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


