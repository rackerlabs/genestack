---
hide:
  - footer
---

# Envoy Gateway API

The [Envoy Gateway](https://gateway.envoyproxy.io/) is an open-source project that provides an implementation
of the Gateway API using Envoyproxy as the data plane. The Gateway API is a set of APIs that allow users to configure
API gateways using a declarative configuration model.

## Installation

Run the helm command to install Envoy Gateway.

??? example "Run the Envoy Gateway deployment Script `/opt/genestack/bin/install-envoy-gateway.sh`"

    ``` shell
    --8<-- "bin/install-envoy-gateway.sh"
    ```

The install script will deploy Envoy Gateway to the `envoy-gateway-system` namespace via Helm.

## Setup

??? example "Run the Envoy Gateway setup Script `/opt/genestack/bin/setup-envoy-gateway.sh`"

    ``` shell
    --8<-- "bin/setup-envoy-gateway.sh"
    ```

The setup script will ask the following questions:

* Enter a valid email address for use with ACME, press enter to skip"
* Enter the domain name for the gateway"

These values will be used to generate a certificate for the gateway and set the routes used within the flex-gateway,
typically for OpenStack. This script can also be fully automated by providing the required values as arguments.

!!! example "Run the Envoy Gateway setup Script with arguments"

    ``` shell
    ACME_EMAIL="username@your.domain.tld" GATEWAY_DOMAIN="your.domain.tld" /opt/genestack/bin/setup-envoy-gateway.sh
    ```

## Validation

At this stage, Envoy Gateway should be operational. To validate the configuration, run the following command.

``` shell
kubectl -n openstack get httproute
```

``` shell
kubectl -n envoy-gateway get gateways.gateway.networking.k8s.io flex-gateway
```

## Troubleshooting

If you encounter any issues, check the logs of the `envoy-gateway` deployment.

``` shell
kubectl logs -n envoy-gateway-system deployment/envoy-gateway
```
