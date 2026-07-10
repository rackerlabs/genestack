# Create our basic OpenStack namespace

The following command will generate our OpenStack namespace and ensure we have everything needed to proceed with the deployment.

``` shell
kubectl apply -k /etc/genestack/kustomize/openstack/base
```

!!! note

    Secrets are now generated and applied automatically by the install scripts.
    Manual secret generation is no longer required.
