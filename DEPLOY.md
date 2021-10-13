# Getting Started with the Turbonomic Platform Operator

The Turbonomic Platform Operator (t8c-operator) makes it easy for Turbonomic
Administrators to deploy and operate Turbonomic Platform deployments in a Kubernetes
infrastructure. Packaged as a container, it uses the [operator pattern](https://kubernetes.io/docs/concepts/extend-kubernetes/operator/)
to manage Turbonomic-specific [custom resource](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/),
following best practices to manage all the underlying Kubernetes objects for you. 

The Turbonomic Platform is a namespace bound application,
it is assumed to be deployed in its own namespace.
One can create multiple namespaces for separate instances of the Turbonomic Platform even within the same kubernetes cluster.
This guide is intended to help new users get up and running with the
Turbonomic Platform Operator. It is divided into the following sections:

* [Installing the Turbonomic Platform Operator](#installing-the-turbonomic-platform-operator)
* [Prerequisites for Deploying on Openshift](#prerequisites-for-deploying-on-openshift)
* [Create a Turbonomic Platform Deployment](#create-turbonomic-deployments)
* [Delete the Turbonomic Deployment and the Turbonomic Platform Operator](#delete-turbonomic-deployments)

## Installing the Turbonomic Platform Operator
````
kubectl create ns turbonomic
kubectl create -f https://raw.githubusercontent.com/turbonomic/t8c-install/master/operator/deploy/service_account.yaml -n turbonomic
kubectl create -f https://raw.githubusercontent.com/turbonomic/t8c-install/master/operator/deploy/role.yaml -n turbonomic
kubectl create -f https://raw.githubusercontent.com/turbonomic/t8c-install/master/operator/deploy/role_binding.yaml -n turbonomic
kubectl create -f https://raw.githubusercontent.com/turbonomic/t8c-install/master/operator/deploy/crds/charts_v1alpha1_xl_crd.yaml
kubectl create -f https://raw.githubusercontent.com/turbonomic/t8c-install/master/operator/deploy/operator.yaml -n turbonomic
````

## Prerequisites for Deploying on Openshift

If you are deploying on Openshift, you need to use the group id from the uid-range assigned to the project:
````
spec:
  global:
    securityContext:
      fsGroup: 1000630000
````

Or you can change the security context of the project to the 'anyuid' SCC
````
oc adm policy add-scc-to-group anyuid system:serviceaccounts:turbonomic
````

## Creating Turbonomic Platform Deployment

Create or modify the Turbonomic custom resource, to deploy an instance of Turbonomic within the namespace
````
kubectl apply -f https://raw.githubusercontent.com/turbonomic/t8c-install/master/operator/deploy/crds/charts_v1alpha1_xl_cr.yaml -n turbonomic
````
Verify the health of the deployed application using the built-in readiness function
````
$ kubectl get pods -n turbonomic
NAME                                     READY   STATUS    RESTARTS   AGE
action-orchestrator-5d86c8778d-6khdz     1/1     Running   0          17d
api-5fd7d4cc78-2sgfc                     1/1     Running   0          17d
arangodb-869bc7d67f-mfsft                1/1     Running   0          17d
auth-7684b48577-tcvdk                    1/1     Running   0          17d
clustermgr-5bd8659f78-2jmbs              1/1     Running   0          17d
consul-6997b8c685-6lkqd                  1/1     Running   0          17d
cost-85b9f79c8b-mnbp7                    1/1     Running   0          17d
db-5db7d45-st628                         1/1     Running   0          17d
group-755cb57596-nwk27                   1/1     Running   0          17d
history-5b67f56b7d-csnr9                 1/1     Running   0          17d
kafka-56575dbf95-xprhc                   1/1     Running   0          17d
market-6bf844bf5d-cgzzx                  1/1     Running   0          17d
mediation-appdynamics-74bcd499bc-llmgp   1/1     Running   0          17d
mediation-aws-6758b4b8d9-qqbxp           1/1     Running   0          17d
mediation-awsbilling-78445fd745-m9rlf    1/1     Running   0          17d
mediation-awscost-67c8c856f5-dm852       1/1     Running   0          17d
nginx-f97c5595f-fl9mc                    1/1     Running   0          17d
plan-orchestrator-7d6d567c4-gdr8q        1/1     Running   0          17d
repository-795777d875-zbj2n              1/1     Running   0          17d
rsyslog-76f779b4-z7czj                   1/1     Running   0          17d
topology-processor-b6bb6bc6d-w4c48       1/1     Running   0          17d
zookeeper-67d68bb4d7-hdrwr               1/1     Running   0          17d
````

## Using a custom StorageClass instead of the default one

If you are deploying into a cluster, where there is no default StorageClass defined, you can
specify the StorageClassName to use for persistent volumes:
````
spec:
  global:
    storageClassName: ocs-storagecluster-ceph-rbd
````
Alternatively you can designate a default StorageClass:

````
kubectl patch storageclass ocs-storagecluster-ceph-rbd -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
````

## Leveraging a custom ingress instead of the default nginx shipped with turbonomic

If the cluster has a preferred ingress setup, the default ingress can be disabled,
and use Openshift application routes to the ui/api can be created by the operator:
````
spec:
  nginxingress:
    enabled: false
  openshiftingress:
    enabled: true
````
Or put the nginx component behind an Openshift application route
````
spec:
  nginx:
    nginxIsPrimaryIngress: false
    httpsredirect: false
  openshiftingress:
    enabled: true
````

### Supported Kubernetes Versions

    OpenShift release 3.4 or higher, Kubernetes version 1.8 or higher including any k8s upstream compliant distribution

### Minimum Specifications for a Kubernetes cluster

These specifications apply to a cluster with a single master node - i.e. the simplest possible cluster setup.

    32 GB or more of RAM, 4 CPUs or more and 800 GB of persistent storage (300 GB with an external RDS database)

### Recommended Kubernetes cluster configuration

Follow the best practices for a minimum cluster configuration
for [Kubernetes](https://kubernetes.io/docs/setup/#production-environment)
or [Openshift](https://istio.io/docs/setup/platform-setup/openshift/)

### Secure communication across components

Leverage a ServiceMesh implementation to [authenticate, encrypt](https://istio.io/docs/tasks/security/authentication/mutual-tls/)
and [control](https://istio.io/docs/reference/config/networking/destination-rule/) communication between microservices

### Automate SSL certificate management

Follow the best practices for using the [cert-manager](https://cert-manager.io/docs/installation/kubernetes/) project

### Backup and restore the application and the persistent state

Leverage kubernetes native backup and restore tools like [Velero](https://velero.io/docs/master/)

### Delete the Turbonomic Deployment and the Turbonomic Platform Operator

Delete the Turbonomic custom resource, to destroy an instance of Turbonomic within the namespace
````
kubectl delete -f https://raw.githubusercontent.com/turbonomic/t8c-install/master/operator/deploy/crds/charts_v1alpha1_xl_cr.yaml -n turbonomic
````

You can stop and remove the operator by running
````
kubectl delete -f https://raw.githubusercontent.com/turbonomic/t8c-install/master/operator/deploy/operator.yaml -n turbonomic
kubectl delete -f https://raw.githubusercontent.com/turbonomic/t8c-install/master/operator/deploy/role_binding.yaml -n turbonomic
kubectl delete -f https://raw.githubusercontent.com/turbonomic/t8c-install/master/operator/deploy/role.yaml -n turbonomic
kubectl delete -f https://raw.githubusercontent.com/turbonomic/t8c-install/master/operator/deploy/service_account.yaml -n turbonomic
kubectl delete -f https://raw.githubusercontent.com/turbonomic/t8c-install/master/operator/deploy/crds/charts_v1alpha1_xl_crd.yaml
kubectl delete ns turbonomic
````

