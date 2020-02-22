Deploy the Turbonomic Operator
````
kubectl create ns turbonomic
kubectl create -f https://raw.githubusercontent.com/turbonomic/t8c-install/7.17.1/operator/deploy/service_account.yaml -n turbonomic
kubectl create -f https://raw.githubusercontent.com/turbonomic/t8c-install/7.17.1/operator/deploy/role.yaml -n turbonomic
kubectl create -f https://raw.githubusercontent.com/turbonomic/t8c-install/7.17.1/operator/deploy/role_binding.yaml -n turbonomic
kubectl create -f https://raw.githubusercontent.com/turbonomic/t8c-install/7.17.1/operator/deploy/crds/charts_v1alpha1_xl_crd.yaml -n turbonomic
kubectl create -f https://raw.githubusercontent.com/turbonomic/t8c-install/7.17.1/operator/deploy/operator.yaml -n turbonomic
````

If you are deploying on Openshift, change the security context of the project to the 'anyuid' SCC
````
oc adm policy add-scc-to-group anyuid system:serviceaccounts:turbonomic
````

Create or modify the Turbonomic custom resource, to deploy an instance of Turbonomic within the namespace
````
kubectl apply -f https://raw.githubusercontent.com/turbonomic/t8c-install/7.17.1/operator/deploy/crds/charts_v1alpha1_xl_cr.yaml -n turbonomic
````
