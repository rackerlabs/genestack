# Deploy Masakari

OpenStack Masakari is the High Availability (HA) service for instances (VMs) in OpenStack.
Provides instance high availability by automatically recovering virtual machine workloads
Compute host failures (node crashes, hardware failure).
VM process failures (QEMU process crashes).
Guest OS failures (detected through monitoring agents). This document outlines the deployment of OpenStack Masakari using Genestack.

## Create secrets

!!! note "Information about the secrets used"

    Service secrets are managed idempotently by this service's install script. The installer creates any missing Kubernetes secrets and reuses existing values.

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
