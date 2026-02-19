# Deploy Blazar

OpenStack Blazar is the resource reservation service in OpenStack. It enables
tenants and operators to reserve resources (such as compute hosts) for a
timeframe, supporting capacity planning and guaranteed availability use cases.
This document outlines the deployment of OpenStack Blazar using Genestack.

## Create secrets

!!! note "Secret generation has been moved to the install-blazar.sh script"

## Define policy configuration

!!! note "Information about the default policy rules used"

    The default RabbitMQ policy sets quorum queues target group size to 3 for
    the `blazar` vhost. This can be changed in `base-kustomize/blazar/base/policies.yaml`.

    ??? example "Default RabbitMQ policy"

        ``` yaml
        apiVersion: rabbitmq.com/v1beta1
        kind: Policy
        metadata:
          name: blazar-quorum-three-replicas
          namespace: openstack
        spec:
          name: blazar-quorum-three-replicas
          vhost: "blazar"
          pattern: ".*"
          applyTo: queues
          definition:
            target-group-size: 3
          priority: 0
          rabbitmqClusterReference:
            name: rabbitmq
        ```
## add blazar filters
  To add blazar filters via an override file, create or update:
  /etc/genestack/helm-configs/nova/nova-helm-overrides.yaml
  With this content:

    conf:
      nova:
        filter_scheduler:
          available_filters: blazarnova.scheduler.filters.blazar_filter.BlazarFilter
          enabled_filters: BlazarFilter
      
## Run the package deployment

!!! example "Run the Blazar deployment Script `/opt/genestack/bin/install-blazar.sh`"

    ``` shell
    --8<-- "bin/install-blazar.sh"
    ```

!!! tip

    You may need to provide custom values to configure your OpenStack services.
    For a simple single region or lab deployment you can supply an additional
    overrides flag using the example found at
    `base-helm-configs/aio-example-openstack-overrides.yaml`.

## Validate functionality

``` shell
kubectl --namespace openstack exec -ti openstack-admin-client -- blazar host-list
```
