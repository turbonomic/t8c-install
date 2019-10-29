Deploy the Turbonomic Operator
````
kubectl create ns turbonomic
kubectl create -f https://raw.githubusercontent.com/turbonomic/t8c-install/master/operator/deploy/service_account.yaml -n turbonomic
kubectl create -f https://raw.githubusercontent.com/turbonomic/t8c-install/master/operator/deploy/role.yaml -n turbonomic
kubectl create -f https://raw.githubusercontent.com/turbonomic/t8c-install/master/operator/deploy/role_binding.yaml -n turbonomic
kubectl create -f https://raw.githubusercontent.com/turbonomic/t8c-install/master/operator/deploy/crds/charts_v1alpha1_xl_crd.yaml -n turbonomic
kubectl create -f https://raw.githubusercontent.com/turbonomic/t8c-install/master/operator/deploy/operator.yaml -n turbonomic
````

Create or modify the Turbonomic custom resource, to deploy an instance of Turbonomic within the namespace
````
kubectl apply -f https://raw.githubusercontent.com/turbonomic/t8c-install/master/operator/deploy/crds/charts_v1alpha1_xl_cr.yaml
````
