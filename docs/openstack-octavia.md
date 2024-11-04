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

### Custom Listeners

!!! note "This step is not needed if all listeners were applied when the Gateway API was deployed"

??? abstract "Example listener patch file found in `/opt/genestack/etc/gateway-api/listeners`"

    ``` yaml
    --8<-- "etc/gateway-api/listeners/octavia-https.json"
    ```

#### Modify the Listener Patch

This example changes the placeholder domain to `<YOUR_DOMAIN>`. Review the [gateway documentation](https://gateway-api.sigs.k8s.io/api-types/gateway)
for more information on listener types.

``` shell
mkdir -p /etc/genestack/gateway-api/listeners
sed 's/your.domain.tld/<YOUR_DOMAIN>/g' \
    /opt/genestack/etc/gateway-api/listeners/octavia-https.json \
    > /etc/genestack/gateway-api/listeners/octavia-https.json
```

#### Apply the Listener Patch

``` shell
kubectl patch -n nginx-gateway gateway flex-gateway \
              --type='json' \
              --patch-file /etc/genestack/gateway-api/listeners/octavia-https.json
```

### Custom Routes

!!! note "This step is not needed if all routes were applied when the Gateway API was deployed"

A custom gateway route can be used when setting up the service. The custom route make it possible to for a domain like `your.domain.tld` to be used for the service.

??? abstract "Example routes file found in `/opt/genestack/etc/gateway-api/routes`"

    ``` yaml
    --8<-- "etc/gateway-api/routes/custom-octavia-gateway-route.yaml"
    ```

#### Modify the Route

This example changes the placeholder domain to `<YOUR_DOMAIN>`. Review the [gateway route documentation](https://gateway-api.sigs.k8s.io/api-types/httproute)
for more information on route types.

``` shell
mkdir -p /etc/genestack/gateway-api/routes
sed 's/your.domain.tld/<YOUR_DOMAIN>/g' \
    /opt/genestack/etc/gateway-api/routes/custom-octavia-gateway-route.yaml \
    > /etc/genestack/gateway-api/routes/custom-octavia-gateway-route.yaml
```

#### Apply the Route

``` shell
kubectl --namespace openstack apply -f /etc/genestack/gateway-api/routes/custom-octavia-gateway-route.yaml
```

## Demo

[![asciicast](https://asciinema.org/a/629814.svg)](https://asciinema.org/a/629814)
