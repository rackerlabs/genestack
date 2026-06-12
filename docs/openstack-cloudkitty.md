# Deploy Cloudkitty

OpenStack Cloudkitty is the rating and chargeback service for OpenStack 
helps operators measure, rate, and bill tenants (projects) for the resources 
they consume in an OpenStack cloud. 
This document outlines the deployment of OpenStack Cloudkitty using Genestack.

## Secrets

!!! note

    Secrets are generated and applied automatically by the install script.

## Run the package deployment

!!! example "Run the Cloudkitty deployment Script"

    ``` shell
    /opt/genestack/bin/install.sh --service cloudkitty
    ```

!!! tip

    You may need to provide custom values to configure your OpenStack services.
    For a simple single region or lab deployment you can supply an additional
    overrides flag using the example found at
    `base-helm-configs/aio-example-openstack-overrides.yaml`.

## Validate functionality

``` shell
kubectl --namespace openstack exec -ti openstack-admin-client -- openstack rating module list
```
