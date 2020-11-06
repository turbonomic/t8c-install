# Turbonomic Platform Operator

[![License](https://img.shields.io/:license-apache-blue.svg)](http://www.apache.org/licenses/LICENSE-2.0.html)

The Turbonomic Platform Operator (t8c-operator) makes it easy for Turbonomic
Administrators to deploy and operate Turbonomic Platform deployments in a Kubernetes
infrastructure. Packaged as a container, it uses the [operator pattern](https://kubernetes.io/docs/concepts/extend-kubernetes/operator/)
to manage Turbonomic-specific [custom resource](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/),
following best practices to manage all the underlying Kubernetes objects for you. 

This repository is used to build the Turbonomic Platform Operator (t8c-operator).

> **NOTE** Documentation on how to deploy the Turbonomic Platform on kubernetes is being maintained in this project's wiki.  Start [here](https://github.com/turbonomic/t8c-install/wiki).


## Prerequisites 

You must have [Docker Engine](https://docs.docker.com/install/) installed to
build the Turbonomic Platform Operator. The [Kubernetes Operator SDK](https://github.com/operator-framework/operator-sdk)
also must be installed to build this project.

```
git clone -b v0.15.0 https://github.com/operator-framework/operator-sdk
cd operator-sdk
make install
```

You may need to add `$GOPATH/bin` to you path to run the `operator-sdk`
command line tool:

```
export PATH=${PATH}:${GOPATH}/bin
```

## Cloning this repository

```
git clone https://github.com/turbonomic/t8c-install.git
cd t8c-install/operator
```


## Building the operator

You can build the operator by just running `make`.

Other make targets include (more info below):

* `make all`: builds the `turbonomic/t8c-operator` docker image (same as `make image`)
* `make image`: builds the `turbonomic/t8c-operator` docker image
* `make package`: generates tarball of the `turbonomic/t8c-operator` docker image and installation YAML file
* `make local`: builds the t8c-operator binary for test and debugging purposes
* `make clean`: removes the binary build output and `turbonomic/t8c-operator` container image
* `make run`: runs the t8c operator locally, monitoring the Kubernetes cluster configured in your current `kubectl` context
* `make fmt`: runs `go fmt` on all `*.go` source files in this project
* `make lint`: runs the `golint` utility on all `*.go` source files in this project


## Pushing Your Turbonomic Platform Operator Image

If you are using a local, single-node Kubernetes cluster like
[minikube](https://minikube.sigs.k8s.io/) or [Docker Desktop](https://www.docker.com/products/docker-desktop),
you only need to build the `turbonomic/t8c-operator` image.
You can skip the rest of this section.

If possible, we recommend re-tagging your custom-built images and pushing
them to a remote registry that your Kubernetes workers are able to pull from.

## Running the Turbonomic Platform Operator

### Running as a foreground process

Use this to run the operator as a local foreground process on your machine:
```
make run
```
This will use your current Kubernetes context from `~/.kube/config`.

### Running in Local and Remote Clusters

To deploy Turbonomic into a Kubernetes cluster, follow the documentation [here](https://github.com/turbonomic/t8c-install/wiki).

Remember the custom resource defines your Turbonomic instance's configuration. To modify the Turbonomic platform, leverage the custom resource to make changes and apply:
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

