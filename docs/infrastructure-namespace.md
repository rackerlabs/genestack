# Create our basic OpenStack namespace

The following command will generate our OpenStack namespace and ensure we have everything needed to proceed with the deployment.

``` shell
kubectl apply -k /etc/genestack/kustomize/openstack/base
```
!!! tip "Secret generation has been moved to the individual installation scripts."
