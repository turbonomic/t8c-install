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

If you are deploying on Openshift, change the security context of the project to the 'anyuid' SCC
````
oc adm policy add-scc-to-group anyuid system:serviceaccounts:turbonomic
````

## Creating Turbonomic Platform Deployment

Create or modify the Turbonomic custom resource, to deploy an instance of Turbonomic within the namespace
````
kubectl apply -f https://raw.githubusercontent.com/turbonomic/t8c-install/master/operator/deploy/crds/charts_v1alpha1_xl_cr.yaml -n turbonomic
````

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

