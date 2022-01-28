Turbonomic K8S Operator
====================

The Turbonomic Kubernetes Operator (aka t8c-operator) is a k8s operator that is used to simplify 
the deployment of the Turbonomic platform over a k8s cluster.

The t8c-operator consists of:
* a docker image (that includes the operator software itself)
* a CRD file that defines the k8s CustomResourceDefinition object (aka the api definition) of 
  kind "Xl"
* a CR file that creates an instance of "Xl", with a specific configuration

We ship a default config/CR file, but ultimately every customer will have its own modified CR 
file that they will adapt to their environment and deployment solution. 

Operator Backward Compatibility
-------------------------------
The customer CR file is not under our direct control.  
**We need to maintain backward compatiblity on it, as much as possible.**

Those are the guidelines that we need to follow when changing its code:
* We cannot release a different operator binary under the same version. If the binary is 
  different, then we need to upgrade the version.
  * This means that any changes to the operator files need to be released under a new docker 
    image version.
* Backward-compatibility NON-breaking changes:
  * Increase the minor version
  * Document the change made in the [CHANGELOG](CHANGELOG.md) file
* Backward-compatibility breaking changes:
    * Increase the major version
    * Document the change made in the [CHANGELOG](CHANGELOG.md) file and write instructions for the customer on 
      how to migrate its CR file to the new version.


**Multi-operator deployment scenarios:**  
There are some deployment scenarios where multiple operators might be involved, hence there can 
be multiple versions of the operator running, related to the same Turbo instance.
* IWO:
  * One instance of the t8c-operator will control the main platform (tp, ao, market, group, ...), 
    running in the cloud
  * Another instance of the t8c-operator will run inside the Assist VM, controlling the remote 
    onPrem probes. This instance (and the controlled probes) might not be upgraded at the same 
    time as the one running on cloud, but at a later time
  * This means that those 2 instances can run 2 totally different operator versions; they are 
    independent, and there are no compatibility concerns (but backward compatibility should 
    still be maintained at probe protocol and application layer, not at operator layer)  
* KubeTurbo
  * The t8c-operator will control the main platform (tp, ao, market, group, ...), running in a 
    k8s cluster
  * A specific kubeturbo operator will run in another k8s cluster (the one to monitor). This 
    instance (and the kubeturbo probe it controls) might not be upgraded at the same as the one 
    above, but at a later time.
  * Those are 2 totally different operators, hence the versions will be different. They are
    independent, and there are no compatibility concerns (but backward compatibility should
    still be maintained at probe protocol and application layer, not at operator layer)  
