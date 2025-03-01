---
hide:
  - footer
---

# Gateway API

Gateway API is L4 and L7 layer routing project in Kubernetes. It represents next generation of k8s Ingress, LB and Service Mesh APIs.
For more information on the project see: [Gateway API SIG.](https://gateway-api.sigs.k8s.io/)

!!! genestack

    For each externally exposed service, example: keystone endpoint, we have a GatewayAPI resource setup to use listeners on services with matching rules based on
    hostname, for example `keystone.your.domain.tld`. When a request comes in to the f5 vip for this the vip is setup to pass the traffic to the Metallb
    external vip address. Metallb then forwards the traffic to the appropriate service endpoint for the gateway controller which matches the hostname and passes the
    traffic onto the right service. The same applies to internal services. Anything that matches `your.domain.tld` hostname can be considered internal and handled accordingly.

    ``` mermaid
    flowchart LR
        External --> External_VIP_Address --> MetalLB_VIP_Address --> Gateway_Service
    ```

The k8s Gateway API is NOT the same an API Gateway. While both sound the same, API Gateway is a more of a general
concept that defines a set of resources that exposes capabilities of a backend service but also provide other
functionalities like traffic management, rate limiting, authentication and more. It is geared towards commercial
API management and monetisation.

## Cross Namespace Routing

Gateway API has support for multi-ns and cross namespace routing. Routes can be deployed into different Namespaces and Routes can attach to Gateways across
Namespace boundaries. This allows user access control to be applied differently across Namespaces for Routes and Gateways, effectively segmenting access and
control to different parts of the cluster-wide routing configuration.

More information on cross namespace routing can be found [here](https://gateway-api.sigs.k8s.io/guides/multiple-ns/).

## Resource Models in Gateway API

| Type | Description |
| ---- | ----------- |
| [GatewayClass](https://gateway-api.sigs.k8s.io/api-types/gatewayclass/) | Represents a class of Gateway instances. |
| [Gateway](https://gateway-api.sigs.k8s.io/api-types/gateway/) | Represents a single Gateway instance. |
| [HTTPRoute](https://gateway-api.sigs.k8s.io/api-types/httproute/) | Represents a set of HTTP-specific rules for mapping traffic to a backend. |
| [Listener](https://gateway-api.sigs.k8s.io/reference/spec/#gateway.networking.k8s.io/v1.Listener) | Represents a network endpoint that can accept incoming traffic. |

## Choosing a Gateway API Implementation

Within Genestack, multiple options are available for use as Gateway API implementations. The following table provides a comparison of the available options.

| Backend Options | Status | <div style="width:256px">Overview</div> |
| --------------- | ------ | --------------------------------------- |
| [Envoy](infrastructure-envoy-gateway-api.md) | **Recommended** | Feature rich, large community, recommended for Production environments. |
| [NGINX](infrastructure-nginx-gateway-api.md) | | Stable codebase, simple implementation |
