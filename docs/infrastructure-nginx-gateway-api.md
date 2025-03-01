---
hide:
  - footer
---

# NGINX Gateway API

The [NGINX Gateway Fabric](https://github.com/nginxinc/nginx-gateway-fabric) is an open-source project that provides an
implementation of the Gateway API using NGINX as the data plane.

## Installation

Run the helm command to install NGINX Gateway.

??? example "Run the NGINX Gateway deployment Script `/opt/genestack/bin/install-nginx-gateway.sh`"

    ``` shell
    --8<-- "bin/install-nginx-gateway.sh"
    ```

The install script will deploy NGINX Gateway to the `nginx-gateway` namespace via Helm.

## Setup

??? example "Run the NGINX Gateway setup Script `/opt/genestack/bin/setup-nginx-gateway.sh`"

    ``` shell
    --8<-- "bin/setup-nginx-gateway.sh"
    ```

The setup script will ask the following questions:

* Enter a valid email address for use with ACME, press enter to skip"
* Enter the domain name for the gateway"

These values will be used to generate a certificate for the gateway and set the routes used within the flex-gateway,
typically for OpenStack. This script can also be fully automated by providing the required values as arguments.

!!! example "Run the NGINX Gateway setup Script with arguments"

    ``` shell
    ACME_EMAIL="username@your.domain.tld" GATEWAY_DOMAIN="your.domain.tld" /opt/genestack/bin/setup-nginx-gateway.sh
    ```

## Validation

At this point, flex-gateway has a listener pointed to the port 80 matching *.your.domain.tld hostname. The
HTTPRoute resource configures routes for this gateway. Here, we match all path and simply pass any request
from the matching hostname to kube-prometheus-stack-prometheus backend service.

``` shell
kubectl -n openstack get httproute
```

``` shell
kubectl -n nginx-gateway get gateways.gateway.networking.k8s.io flex-gateway
```
