## Kubeturbo Deploy via Helm Charts

Review the prerequisites defined in the [Deploy Overview](https://github.com/turbonomic/kubeturbo/tree/master/deploy/README.md)

[Helm](https://helm.sh/) is a kubernetes package manager that allows you to more easily manage charts, which are a way to package all resources associated with an application.  Helm provides a way to package, deploy and update using simple commands, and provides a way to customize or update parameters of your resources, without the worry of yaml formatting. For more info see: [Helm: The Kubernetes Package Manager](https://github.com/helm/helm)  

To use this method, you will already have a helm client and tiller server installed, and are familiar with how to use helm and chart repositories. Go to [Helm Docs](https://helm.sh/docs/using_helm/%23quickstart-guide) to get started.

The Helm Chart provided [here](https://github.com/turbonomic/kubeturbo/tree/master/deploy/kubeturbo) will deploy kubeturbo and create the following resources: 
1. Create a Namespace or Project (default is "turbo")
1. Service Account and binding to cluster-admin clusterrole (default is "turbo-user" with "turbo-all-binding" role)
1. ConfigMap for kubeturbo to connect to the Turbonomic server
1. Deploy kubeturbo Pod

Note:
* When deploying kubeturbo using helm, the user will create charts that will create resources requiring cluster admin role.  [Review Tiller and role-based access control requirements](https://docs.helm.sh/using_helm/#tiller-and-role-based-access-control).  Tiller will need to run with an SA that has [cluster role access](https://github.com/fnproject/fn-helm/issues/21).
* The image tag used will depend somewhat on your Turbo Server version.  For Server versions of 6.1.x - 6.2.x, use tag "6.2".  For Server versions of 6.3.1+, use "6.3".  Running CWOM? Go here to see conversion chart for [CWOM -> Turbonomic Server -> kubeturbo version](https://github.com/turbonomic/kubeturbo/tree/master/deploy/version_mapping_kubeturbo_Turbo_CWOM.md).

#### Helm Install

To install, the following command consists of the typical values you would specify.  Substitute your environment values where you see a {}:

`   helm install --name {DEPLOYMENT_NAME} {CHARTLOCATION_OR_REPO} --namespace turbo --set serverMeta.turboServer={TURBOSERVER_URL} --set serverMeta.version={TURBOSERVER_VERSION} --set restAPIConfig.opsManagerUserName={TURBOSERVER_ADMINUSER} --set restAPIConfig.opsManagerPassword={TURBOSERVER_ADMINUSER_PWD} --set targetConfig.targetName={CLUSTER_IDENTIFIER}`

Note it is advised to do a dry run first: `helm install --dry-run --debug`

#### Values

The following table shows the values exposed which are also seen in the file [values.yaml](https://github.com/turbonomic/kubeturbo/tree/master/deploy/kubeturbo_helm/values.yaml), and values that are default and/or required are noted as such.

Parameter|Default Value|Required / Opt to Change|Parameter Type
------------ | ------------- | --------------- | -------------
image.repository|turbonomic/kubeturbo|optional|path to repo
image.tag|6.3|optional|kubeturbo tag
image.pullPolicy|IfNotPresent|optional| 
serverMeta.version| |required|number x.y
serverMeta.turboServer| |required|https URL to log into Server
restAPIConfig.opsManagerUserName| |required|local or AD user with admin role
restAPIConfig.opsManagerPassword| |required|admin's password
targetConfig.targetName|"Your_k8s_cluster"|optional but required for multiple clusters|String, how you want to identify your cluster
args.logginglevel|2|optional|number
args.kubelethttps|true|optional, change to false if k8s 1.10 or older|bolean
args.kubeletport|10250|optional, change to 10255 if k8s 1.10 or older|number
args.stitchuuid|true|optional, change to false if IaaS is VMM, Hyper-V|bolean
masterNodeDetectors.nodeNamePatterns|node name includes `.*master.*`|optional but equired to avoid suspending masters identified by node name. If no match, this is ignored.| string, regex used, example:  `.*master.*`
masterNodeDetectors.nodeLabels|any value for label key value `node-role.kubernetes.io/master`|optional but required to avoid suspending masters identified by node label key value pair, If no match, this is ignored.|regex used, specify the key as **masterNodeDetectors.nodeLabelsKey** such as  `node-role.kubernetes.io/master` and the value as **masterNodeDetectors.nodeLabelsValue** such as `.*`
daemonPodDetectors.daemonPodNamespaces1 and daemonPodNamespaces2|daemonSet kinds are by default allow for node suspension. Adding this parameter changes default.|Optional but required to identify pods in the namespace to be ignored for cluster consolidation| regex used, values in quotes & comma separated`"kube-system","kube-service-catalog","openshift-.*"`
daemonPodDetectors.daemonPodNamePatterns|daemonSet kinds are by default allow for node suspension. Adding this parameter changes default.|Optional but required to identify pods matching this pattern to be ignored for cluster consolidation|regex used `.*ignorepod.*`

For more on `masterNodeDetectors` and `daemonPodDetectors` go to [YAMLS_README.md](https://github.com/turbonomic/kubeturbo/tree/master/deploy/kubeturbo_yamls/YAMLS_README.md) under kubeturbo/deploy/kubeturbo_yamls/

#### Updating Turbo Server
When you update the Turbonomic or CWOM Server, you will need to update the configMap resource to reflect the new version.
NOTE: Starting with kubeturbo 6.3+, you do not need to make this configMap modification if updating to a minor version like 6.3.0 -> 6.3.1, which will now be automatically handled.  You would only need to make this change if you are making a major change, going from 6.3.x -> 6.4.x, or 6.3.x -> 7.x.

1. After the update, obtain the new version.  To get this from the UI, go to Settings -> Updates -> About and use the numeric version such as “6.3” or “6.4” (Build details not required)
1. You will update the version value - substitute your values for {}:  `helm upgrade --name {helmChart}{chart location or repo} --namespace turbo --set serverMeta.version={Turbo_Server_Version}`
1. Insure kubeturbo pod restarted to pick up new value
1. Repeat for every kubernetes / OpenShift cluster with a kubeturbo pod

#### Updating Kubeturbo Image
You may be instructed to update the kubeturbo pod image.  Determine which new tag you will be using.  You will either be instructed by Turbonomic to use a new image, or you may want to refresh the image to pick up a security patch.

1. You will update the version value - substitute your values for {}:  `helm upgrade –name {helmChart}{chart location or repo} –namespace turbo –set image.repository={new repo location, if changed} –set image.tag={new tag value, if changed} –set image.pullPolicy=Always`
1. Use image.pullPolicy of “Always” if the image location and tag have not changed, to force the newer image to be pulled. Default value is “IfNotPresent”.
1. Insure kubeturbo pod redeployed with new image
1. Repeat for every kubernetes / OpenShift cluster with a kubeturbo pod

There's no place like home... go back to the [Turbonomic Overview](https://github.com/turbonomic/kubeturbo/tree/master/README.md) or the [Deploy Overview](https://github.com/turbonomic/kubeturbo/tree/master/deploy/README.md).