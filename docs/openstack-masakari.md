# Deploy Masakari

OpenStack Masakari is the High Availability (HA) service for instances (VMs) in OpenStack.
Provides instance high availability by automatically recovering virtual machine workloads
Compute host failures (node crashes, hardware failure).
VM process failures (QEMU process crashes).
Guest OS failures (detected through monitoring agents). This document outlines the deployment of OpenStack Masakari using Genestack.

## Create secrets

!!! note "Information about the secrets used"

    Manual secret generation is only required if you haven't run the
    `create-secrets.sh` script located in `/opt/genestack/bin`.

    ??? example "Example secret generation"

        ``` shell
        kubectl --namespace openstack \
                create secret generic masakari-rabbitmq-password \
                --type Opaque \
                --from-literal=username="masakari" \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-64};echo;)"
        kubectl --namespace openstack \
                create secret generic masakari-db-password \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        kubectl --namespace openstack \
                create secret generic masakari-admin \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        ```

## Run the package deployment

!!! example "Run the Masakari deployment Script `/opt/genestack/bin/install-masakari.sh`"

    ``` shell
    --8<-- "bin/install-masakari.sh"
    ```

!!! tip

    You may need to provide custom values to configure your OpenStack services.
    For a simple single region or lab deployment you can supply an additional
    overrides flag using the example found at
    `base-helm-configs/aio-example-openstack-overrides.yaml`.

## Validate functionality

``` shell
kubectl --namespace openstack exec -ti openstack-admin-client -- openstack segment list
```
