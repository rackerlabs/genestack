---
hide:
  - footer
---

# NGINX Gateway API

The [NGINX Gateway Fabric](https://github.com/nginxinc/nginx-gateway-fabric) is an open-source project that provides an
implementation of the Gateway API using NGINX as the data plane.

## Install the Gateway API Resource from Kubernetes

=== "Stable _(Recommended)_"

    ``` shell
    kubectl kustomize "https://github.com/nginxinc/nginx-gateway-fabric/config/crd/gateway-api/standard?ref=v1.4.0" | kubectl apply -f -
    ```

=== "Experimental"

    The experimental version of the Gateway API is available in the `v1.6.1` checkout. Use with caution.

    ``` shell
    kubectl kustomize "https://github.com/nginx/nginx-gateway-fabric/config/crd/gateway-api/experimental?ref=v1.6.1" | kubectl apply -f -
    ```

## Install the NGINX Gateway Fabric controller

The NGINX Gateway Fabric controller is a Kubernetes controller that manages the Gateway API resources.

### Create the Namespace

``` shell
kubectl apply -f /opt/genestack/manifests/nginx-gateway/nginx-gateway-namespace.yaml
```

!!! tip

    If attempting to perform an **upgrade** of an existing Gateway API deployment, note that the Helm install does not automatically upgrade the CRDs for
    this resource. To upgrade them, refer to the process outlined by the
    [Nginx upgrade documentation](https://docs.nginx.com/nginx-gateway-fabric/installation/installing-ngf/helm/#upgrade-nginx-gateway-fabric-crds). You
    can safely ignore this note for new installations.

=== "Stable _(Recommended)_"

    Edit the file `/etc/genestack/helm-configs/nginx-gateway-fabric/helm-overrides.yaml`.

    !!! example "Create an empty override file"

        If no overrides are needed, create an empty file.

        ``` shell
        echo "---" | tee /etc/genestack/helm-configs/nginx-gateway-fabric/helm-overrides.yaml
        ```

    ``` shell
    pushd /opt/genestack/submodules/nginx-gateway-fabric/charts || exit 1
    helm upgrade --install nginx-gateway-fabric ./nginx-gateway-fabric \
        --namespace=nginx-gateway \
        --create-namespace \
        -f /opt/genestack/base-helm-configs/nginx-gateway-fabric/helm-overrides.yaml \
        -f /etc/genestack/helm-configs/nginx-gateway-fabric/helm-overrides.yaml \
        --post-renderer /etc/genestack/kustomize/kustomize.sh \
        --post-renderer-args gateway/overlay
    popd || exit 1
    ```

=== "Experimental"

    The experimental version of the Gateway API is available in the `v1.6.1` checkout. Use with caution.

    Update the submodule with the experimental version of the Gateway API.

    Edit the file `/etc/genestack/helm-configs/nginx-gateway-fabric/helm-overrides.yaml`.

    !!! example "Create the experimental override file"

        ``` yaml
        ---
        nginxGateway:
        replicaCount: 3
        gwAPIExperimentalFeatures:
            enable: true
        service:
        ## The externalTrafficPolicy of the service. The value Local preserves the client source IP.
        externalTrafficPolicy: Cluster
        ## The annotations of the NGINX Gateway Fabric service.
        annotations:
            "metallb.universe.tf/address-pool": "gateway-api-external"
            "metallb.universe.tf/allow-shared-ip": "openstack-external-svc"
        ```

    Run the helm command to install the experimental version of the Gateway API.

    ``` shell
    helm upgrade --install nginx-gateway-fabric oci://ghcr.io/nginx/charts/nginx-gateway-fabric \
        --create-namespace \
        --namespace=nginx-gateway \
        -f /etc/genestack/helm-configs/nginx-gateway-fabric/helm-overrides.yaml \
        --post-renderer /etc/genestack/kustomize/kustomize.sh \
        --post-renderer-args gateway/overlay \
        --version 1.6.1
    ```

Once deployed ensure a system rollout has been completed for Cert Manager.

``` shell
kubectl rollout restart deployment cert-manager --namespace cert-manager
```

## Create the shared gateway resource

``` shell
kubectl kustomize /etc/genestack/kustomize/gateway/nginx-gateway-fabric | kubectl apply -f -
```

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

At this point, flex-gateway has a listener pointed to the port 80 matching *.your.domain.tld hostname. The HTTPRoute resource configures routes
for this gateway. Here, we match all path and simply pass any request from the matching hostname to kube-prometheus-stack-prometheus backend service.
