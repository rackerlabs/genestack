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

For deployments that need separate internal and external gateways, see
[Envoy Gateway Internal and External Gateway Runbooks](infrastructure-envoy-gateway-multi-gateway.md).

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
By default HTTP01 challenge method is enabled, requiring the gateway API to be exposed to a routable IP address.
Alternative challenge modes can be used, such as DNS01, requiring a DNS plugin to be configured.
The DNS plugin uses access credentials or tokens to inject the `_acme-challenge` TXT record carrying the challenge token
to prove the ownership of the domain.

``` shell
Current pre-configured DNS plugins:
  godaddy         GoDaddy DNS (requires webhook)
  rackspace       Rackspace Cloud DNS (requires webhook)
  cloudflare      Cloudflare DNS (built-in support)
  route53         AWS Route53 (built-in support)
  azuredns        Azure DNS (built-in support)
  google          Google Cloud DNS (built-in support)
  digitalocean    DigitalOcean DNS (built-in support)
  acmedns         ACME-DNS (built-in support)
  rfc2136         RFC2136 Dynamic DNS (built-in support)
```


!!! example "Run the Envoy Gateway setup Script with arguments"

    ``` shell
    /opt/genestack/bin/setup-envoy-gateway.sh \
      --email username@your.domain.tld \
      --domain your.domain.tld
    ```

### Route request timeouts

Envoy applies a default route timeout of 15 seconds to every HTTPRoute that does not set a timeout,
either through `spec.rules[].timeouts` on the route or through a `BackendTrafficPolicy` that targets
it. Genestack sets timeouts with a `BackendTrafficPolicy` next to the service that needs them, and
only in one place per route: if a route sets `spec.rules[].timeouts`, the policy's timeout is
ignored.

Two OpenStack routes need more than the default:

* **Glance** — bulk image transfers (`base-kustomize/glance/base/glance-backendtrafficpolicy.yaml`).
* **Nova** — attaching a volume. For compute API microversions below `2.101`,
  `POST /servers/{server_id}/os-volume_attachments` blocks in nova-api until nova-compute has
  reserved a device name for the instance, and that reservation waits behind any attach or detach
  already running for the same instance (roughly 10 seconds each). Attaching several volumes to one
  server in quick succession therefore exceeds 15 seconds: Envoy returns `504 upstream request
  timeout` to the client while nova still completes the attach, and the client and the cloud
  disagree about the result. `base-kustomize/nova/base/nova-backendtrafficpolicy.yaml` sets
  `requestTimeout: 120s` so the request is allowed to finish; raise it to match the largest number
  of volumes your users attach to a single server at once. Clients that send microversion `2.101`
  or newer receive `202 Accepted` immediately and are not affected.

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
kubectl logs -n envoyproxy-gateway-system deployment/envoy-gateway
```
