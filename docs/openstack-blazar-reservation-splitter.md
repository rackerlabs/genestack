# Blazar Reservation Splitter

The Blazar Reservation Splitter is a companion service for OpenStack Blazar that automatically processes reservation events. It listens to RabbitMQ messages for lease events (specifically `lease.event.start_lease`) and splits out individual reservations from the payload, and publishes separate notification events for each reservation to Ceilometer. This enables Ceilometer to create individual Gnocchi metrics for each reservation in a lease.

## Create secrets

!!! note "Information about the secrets used"

    Service secrets are managed idempotently by this service's install script. The installer creates any missing Kubernetes secrets and reuses existing values.

## Run the package deployment

!!! example "Run the Blazar Reservation Splitter deployment Script `/opt/genestack/bin/install-blazar-reservation-splitter.sh`"

    ``` shell
    --8<-- "bin/install-blazar-reservation-splitter.sh"
    ```

!!! tip

    You may need to provide custom values to configure your services. Refer to
    `base-helm-configs/blazar-reservation-splitter/blazar-reservation-splitter-helm-overrides.yaml`
    for available configuration options.

!!! success

    If the installation is successful, you should see the blazar-reservation-splitter pod running in the openstack namespace.

## Validate functionality

``` shell
kubectl --namespace openstack get pods -l app.kubernetes.io/name=blazar-reservation-splitter
kubectl --namespace openstack logs -l app.kubernetes.io/name=blazar-reservation-splitter
```
