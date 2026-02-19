# Deploy Freezer

Freezer is a disaster recovery and backup-as-a-service component for OpenStack.
It provides a way to back up various resources, such as virtual machine instances,
databases, and file systems.

It allows users to schedule backups, restore data, and manage the lifecycle of their
backups to ensure data protection and business continuity within an OpenStack cloud.

This document outlines the deployment of OpenStack Freezer using Genestack.

## Create secrets

!!! note "Secret generation has been moved to the install-freezer.sh script"

## Run the package deployment

!!! example "Run the Freezer deployment Script `/opt/genestack/bin/install-freezer.sh`"

    ``` shell
    --8<-- "bin/install-freezer.sh"
    ```

!!! tip

    You may need to provide custom values to configure your OpenStack services.
    For a simple single region or lab deployment you can supply an additional
    overrides flag using the example found at
    `base-helm-configs/aio-example-openstack-overrides.yaml`.

## Validate functionality

``` shell
kubectl --namespace openstack exec -ti openstack-admin-client -- freezer host-list
```
