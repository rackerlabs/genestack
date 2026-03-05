# Blazar Reservation Splitter

The Blazar Reservation Splitter is a companion service for OpenStack Blazar that automatically processes reservation events. It listens to RabbitMQ messages for lease events (specifically `lease.event.start_lease`) and splits out individual reservations from the payload, and publishes separate notification events for each reservation to Ceilometer. This enables Ceilometer to create individual Gnocchi metrics for each reservation in a lease.

## Create secrets

!!! note "Information about the secrets used"

    Manual secret generation is only required if you haven't run the
    `create-secrets.sh` script located in `/opt/genestack/bin`.

    ??? example "Example secret generation"

        ``` shell
        kubectl --namespace openstack \
                create secret generic blazar-reservation-splitter-rabbitmq-password \
                --type Opaque \
                --from-literal=username="blazar-reservation-splitter" \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-64};echo;)"
        ```

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
