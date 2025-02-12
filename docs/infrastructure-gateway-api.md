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

## Move from Ingress to Gateway APIs

Since Gateway APIs are successor to Ingress Controllers there needs to be a one time migration from Ingress to GW API resources.

!!! tip "Learn more about migrating to the Gateway API: [Ingress Migration](https://gateway-api.sigs.k8s.io/guides/migrating-from-ingress/#migrating-from-ingress)"

## Resource Models in Gateway API

There are 3 main resource models in gateway apis:

1. GatewayClass - Mostly managed by a controller.
2. Gateway - An instance of traffic handling infra like a LB.
3. Routes - Defines HTTP-specific rules for mapping traffic from a Gateway listener to a representation of backend network endpoints.

!!! warning "k8s Gateway API is NOT the same as API Gateways"

While both sound the same, API Gateway is a more of a general concept that defines a set of resources that exposes capabilities of a backend service but
also provide other functionalities like traffic management, rate limiting, authentication and more. It is geared towards commercial API management and monetisation.

From the gateway api sig:

!!! note

    Most Gateway API implementations are API Gateways to some extent, but not all API Gateways are Gateway API implementations.

## Controller Selection

There are various implementations of the Gateway API. In this document, we will cover two of them:

=== "NGINX Gateway Fabric _(Recommended)_"

    [NGINX Gateway Fabric](https://github.com/nginxinc/nginx-gateway-fabric) is an open-source project that provides an implementation of the Gateway
    API using nginx as the data plane.

    ### Create the Namespace

    ``` shell
    kubectl create ns nginx-gateway
    ```

    ### Install the Gateway API Resource from Kubernetes

    === "Stable _(Recommended)_"

        ``` shell
        kubectl kustomize "https://github.com/nginxinc/nginx-gateway-fabric/config/crd/gateway-api/standard?ref=v1.4.0" | kubectl apply -f -
        ```

    === "Experimental"

        ``` shell
        kubectl kustomize "https://github.com/nginxinc/nginx-gateway-fabric/config/crd/gateway-api/experimental?ref=v1.4.0" | kubectl apply -f -
        ```

    ### Install the NGINX Gateway Fabric controller

    !!! tip

        If attempting to perform an **upgrade** of an existing Gateway API deployment, note that the Helm install does not automatically upgrade the CRDs for
        this resource. To upgrade them, refer to the process outlined by the
        [Nginx upgrade documentation](https://docs.nginx.com/nginx-gateway-fabric/installation/installing-ngf/helm/#upgrade-nginx-gateway-fabric-crds). You
        can safely ignore this note for new installations.

    === "Stable _(Recommended)_"

        ``` shell
        cd /opt/genestack/submodules/nginx-gateway-fabric/charts

        helm upgrade --install nginx-gateway-fabric ./nginx-gateway-fabric \
                    --namespace=nginx-gateway \
                    -f /etc/genestack/helm-configs/nginx-gateway-fabric/helm-overrides.yaml
        ```

    === "Experimental"

        ``` shell
        cd /opt/genestack/submodules/nginx-gateway-fabric/charts

        helm upgrade --install nginx-gateway-fabric ./nginx-gateway-fabric \
                    --namespace=nginx-gateway \
                    -f /etc/genestack/helm-configs/nginx-gateway-fabric/helm-overrides.yaml \
                    --set nginxGateway.gwAPIExperimentalFeatures.enable=true
        ```

    Once deployed ensure a system rollout has been completed for Cert Manager.

    ``` shell
    kubectl rollout restart deployment cert-manager --namespace cert-manager
    ```

    ### Create the shared gateway resource

    === "Stable _(Recommended)_"

        ``` shell
        kubectl kustomize /etc/genestack/kustomize/gateway/nginx-gateway-fabric | kubectl apply -f -
        ```

    === "Experimental"

        Edit the file `/etc/genestack/kustomize/gateway/nginx-gateway-fabric/internal-gateway-api.yaml` to set the `apiVersion` according to the experimental version of your choice. Review the Gateway [API Compatibility Matrix](https://docs.nginx.com/nginx-gateway-fabric/overview/gateway-api-compatibility).

        ``` shell
        kubectl kustomize /etc/genestack/kustomize/gateway/nginx-gateway-fabric | kubectl apply -f -
        ```

=== "Envoyproxy"

    [Envoyproxy](https://gateway.envoyproxy.io/) is an open-source project that provides an implementation of the Gateway API using Envoyproxy as the data plane.

    ### Installation

    Update the `/etc/genestack/kustomize/envoyproxy-gateway/base/values.yaml` file according to your requirements.

    Apply the configuration using the following command:

    ``` shell
    kubectl kustomize --enable-helm /etc/genestack/kustomize/envoyproxy-gateway/overlay | kubectl apply -f -
    ```

    ### After installation

    You need to create Gateway and HTTPRoute resources based on your requirements

    !!! example "exposing an application using Gateway API (Envoyproxy)"

        In this example, we will demonstrate how to expose an application through a gateway. Apply the Kustomize configuration which will create `Gateway` resource:

        ``` shell
        kubectl kustomize /etc/genestack/kustomize/gateway/envoyproxy | kubectl apply -f -
        ```

    Once gateway is created, user can expose an application by creating `HTTPRoute` resource.

    ??? abstract "Sample `HTTPRoute` resource"

        ``` yaml
        --8<-- "etc/gateway-api/gateway-envoy-http-routes.yaml"
        ```

    !!! example "Example modifying and apply the routes"

        ``` shell
        mkdir -p /etc/genestack/gateway-api
        sed 's/your.domain.tld/<YOUR_DOMAIN>/g' /opt/genestack/etc/gateway-api/gateway-envoy-http-routes.yaml > /etc/genestack/gateway-api/gateway-envoy-http-routes.yaml
        kubectl apply -f /etc/genestack/gateway-api/gateway-envoy-http-routes.yaml
        ```

----

## Deploy with Let's Encrypt Certificates

By default, certificates are issued by an instance of the selfsigned-cluster-issuer. This section focuses on replacing that with a
Let's Encrypt issuer to ensure valid certificates are deployed in our cluster.

[![asciicast](https://asciinema.org/a/h7npXnDjkSpn3uQtuQwWG9zju.svg)](https://asciinema.org/a/h7npXnDjkSpn3uQtuQwWG9zju)

### Apply the Let's Encrypt Cluster Issuer

Before we can have Cert Manager start coordinating Let's Encrypt certificate
requests for us, we need to add an ACME issuer with a valid, monitored
email (for expiration reminders and other important ACME related information).

``` yaml
read -p "Enter a valid email address for use with ACME: " ACME_EMAIL; \
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ${ACME_EMAIL}
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          gatewayHTTPRoute:
            parentRefs:
            - group: gateway.networking.k8s.io
              kind: Gateway
              name: flex-gateway
              namespace: nginx-gateway
EOF
```
!!! note

    It is also possible to use cert-manager to create [self-signed CA for Gateway API](https://docs.rackspacecloud.com/gateway-api-ca-issuer/)

## Patch Gateway with valid listeners

By default, a generic Gateway is created using a hostname of `*.cluster.local`. To add specific hostnames/listeners to the gateway, you can either
create a patch or update the gateway YAML to include your specific hostnames and then apply the patch/update. Each listener must have a
unique name.

??? abstract "An example patch file you can modify to include your own domain name can be found at `/opt/genestack/etc/gateway-api/listeners/gateway-api/http-wildcard-listener.json`"

    ``` json
    --8<-- "etc/gateway-api/listeners/http-wildcard-listener.json"
    ```

!!! example "Example modifying the Gateway listener patches"

    ``` shell
    mkdir -p /etc/genestack/gateway-api/listeners
    for listener in $(ls -1 /opt/genestack/etc/gateway-api/listeners); do
        sed 's/your.domain.tld/<YOUR_DOMAIN>/g' /opt/genestack/etc/gateway-api/listeners/$listener > /etc/genestack/gateway-api/listeners/$listener
    done
    ```

``` shell
kubectl patch -n nginx-gateway gateway flex-gateway \
              --type='json' \
              --patch="$(jq -s 'flatten | .' /etc/genestack/gateway-api/listeners/*)"
```

## Apply Related Gateway routes

Another example with most of the OpenStack services is located at `/opt/genestack/etc/gateway-api/routes/http-wildcard-listener.yaml`. Similarly, you must modify
and apply them as shown below, or apply your own.

??? abstract "Example routes file"

    ``` yaml
    --8<-- "etc/gateway-api/routes/http-wildcard-listener.yaml"
    ```

All routes can be found at `/etc/genestack/gateway-api/routes`.

!!! example "Example modifying all available Gateway routes with `your.domain.tld`"

    ``` shell
    mkdir -p /etc/genestack/gateway-api/routes
    for route in $(ls -1 /opt/genestack/etc/gateway-api/routes); do
        sed 's/your.domain.tld/<YOUR_DOMAIN>/g' /opt/genestack/etc/gateway-api/routes/$route > /etc/genestack/gateway-api/routes/$route
    done
    ```

``` shell
kubectl apply -f /etc/genestack/gateway-api/routes
```

## Patch Gateway with Let's Encrypt Cluster Issuer

??? abstract "Example patch to enable LetsEncrypt `/etc/genestack/gateway-api/gateway-letsencrypt.yaml`"

    ``` yaml
    --8<-- "etc/gateway-api/gateway-letsencrypt.yaml"
    ```

``` shell
kubectl patch --namespace nginx-gateway \
              --type merge \
              --patch-file /etc/genestack/gateway-api/gateway-letsencrypt.yaml \
              gateway flex-gateway
```

## Example Implementation with Prometheus UI (NGINX Gateway Fabric)

In this example we will look at how Prometheus UI is exposed through the gateway. For other services the gateway kustomization file for the service.

First, create the shared gateway and then the httproute resource for prometheus.

??? abstract "Example patch to enable Prometheus `/etc/genestack/gateway-api/gateway-prometheus.yaml`"

    ``` yaml
    --8<-- "etc/gateway-api/gateway-prometheus.yaml"
    ```

!!! example "Example modifying Prometheus' Gateway deployment"

    ``` shell
    mkdir -p /etc/genestack/gateway-api
    sed 's/your.domain.tld/<YOUR_DOMAIN>/g' /opt/genestack/etc/gateway-api/gateway-prometheus.yaml > /etc/genestack/gateway-api/gateway-prometheus.yaml
    ```

``` shell
kubectl apply -f /etc/genestack/gateway-api/gateway-prometheus.yaml
```

At this point, flex-gateway has a listener pointed to the port 80 matching *.your.domain.tld hostname. The HTTPRoute resource configures routes
for this gateway. Here, we match all path and simply pass any request from the matching hostname to kube-prometheus-stack-prometheus backend service.

## Cross Namespace Routing

Gateway API has support for multi-ns and cross namespace routing. Routes can be deployed into different Namespaces and Routes can attach to Gateways across
Namespace boundaries. This allows user access control to be applied differently across Namespaces for Routes and Gateways, effectively segmenting access and
control to different parts of the cluster-wide routing configuration.

More information on cross namespace routing can be found [here](https://gateway-api.sigs.k8s.io/guides/multiple-ns/).
