# Deploy Octavia

OpenStack Octavia is the load balancing service within the OpenStack ecosystem, providing scalable and automated load balancing for cloud applications. Octavia is designed to ensure high availability and reliability by distributing incoming network traffic across multiple instances of an application, preventing any single instance from becoming a bottleneck or point of failure. It supports various load balancing algorithms, health monitoring, and SSL termination, making it a versatile tool for managing traffic within cloud environments. In this document, we will explore the deployment of OpenStack Octavia using Genestack. By leveraging Genestack, the deployment of Octavia is streamlined, ensuring that load balancing is seamlessly incorporated into both private and public cloud environments, enhancing the performance and resilience of cloud applications.

## Create secrets

!!! note "Information about the secretes used"

    Manual secret generation is only required if you haven't run the `create-secrets.sh` script located in `/opt/genestack/bin`.

    ??? example "Example secret generation"

        ``` shell
        kubectl --namespace openstack \
                create secret generic octavia-rabbitmq-password \
                --type Opaque \
                --from-literal=username="octavia" \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-64};echo;)"
        kubectl --namespace openstack \
                create secret generic octavia-db-password \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        kubectl --namespace openstack \
                create secret generic octavia-admin \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        kubectl --namespace openstack \
                create secret generic octavia-certificates \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        ```

## Run the package deployment

!!! example "Run the Octavia deployment Script `bin/install-octavia.sh`"

    ``` shell
    --8<-- "bin/install-octavia.sh"
    ```

!!! tip

    You may need to provide custom values to configure your openstack services, for a simple single region or lab deployment you can supply an additional overrides flag using the example found at `base-helm-configs/aio-example-openstack-overrides.yaml`.
    In other cases such as a multi-region deployment you may want to view the [Multi-Region Support](multi-region-support.md) guide to for a workflow solution.

## Demo

[![asciicast](https://asciinema.org/a/629814.svg)](https://asciinema.org/a/629814)
