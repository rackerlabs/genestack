# Deploy Freezer

Freezer is a disaster recovery and backup-as-a-service component for OpenStack.
It provides a way to back up various resources, such as virtual machine instances,
databases, and file systems.

It allows users to schedule backups, restore data, and manage the lifecycle of their
backups to ensure data protection and business continuity within an OpenStack cloud.

This document outlines the deployment of OpenStack Freezer using Genestack.

## Create secrets

!!! note "Information about the secrets used"

    Manual secret generation is only required if you haven't run the
    `create-secrets.sh` script located in `/opt/genestack/bin`.

    ??? example "Example secret generation"

        ``` shell
        kubectl --namespace openstack \
                create secret generic freezer-db-password \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        kubectl --namespace openstack \
                create secret generic freezer-admin \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        ```

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
