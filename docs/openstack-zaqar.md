!!! genestack "TECH PREVIEW"

# Deploy Zaqar

Zaqar is a multi-tenant cloud messaging and notification service for web and mobile developers. It features a REST API 
which developers can use to send messages between various components of their SaaS and mobile applications.

OpenStack components can use Zaqar to inform events to end users and communication with guest agent that run in the 
"over-cloud" layer. This document outlines the deployment of OpenStack Zaqar using Genestack.

!!! note

    Zaqar Websocket API is not supported for now in Genestack. It maybe added in a future release.

## Create secrets

!!! note "Secret generation has been moved to the install-zaqar.sh script"

## Run the package deployment

!!! example "Run the Zaqar deployment Script `/opt/genestack/bin/install-zaqar.sh`"

    ``` shell
    --8<-- "bin/install-zaqar.sh"
    ```

!!! tip

    You may need to provide custom values to configure your OpenStack services.
    For a simple single region or lab deployment you can supply an additional
    overrides flag using the example found at
    `base-helm-configs/aio-example-openstack-overrides.yaml`.

## Validate functionality

``` shell
kubectl --namespace openstack exec -ti openstack-admin-client -- openstack messaging queue list
```
