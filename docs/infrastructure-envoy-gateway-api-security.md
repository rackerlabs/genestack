# Security Policies

From [Envoy documentation](https://gateway.envoyproxy.io/docs/concepts/introduction/gateway_api_extensions/security-policy/):

SecurityPolicy is an Envoy Gateway extension to the Kubernetes Gateway API that allows you to define authentication and authorization requirements for traffic entering your gateway. It acts as a security layer that only properly authenticated and authorized requests are allowed through your backend services.

In this section we will be implementing [oidc](https://gateway.envoyproxy.io/docs/tasks/security/oidc/) authentication to auth using Azure AD.

!!! note "You must have deployed Envoy Gateway already and installed the CRDs before this will work"

## Create the HTTPRoute

!!! note "The examples used here reference alertmanager.  You will change the settings as necessary for your application/s"

``` yaml title="alertmanager-gw-route.yaml"
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  annotations:
  name: alertmanager-gateway-route
  namespace: prometheus
spec:
  hostnames:
  - alertmanager.example.com
  parentRefs:
  - group: gateway.networking.k8s.io
    kind: Gateway
    name: flex-internal-gateway
    namespace: internal
    sectionName: am-https
  rules:
  - backendRefs:
    - group: ""
      kind: Service
      name: kube-prometheus-stack-alertmanager
      port: 9093
      weight: 1
    matches:
    - path:
        type: PathPrefix
        value: /
```

`kubectl apply -f alertmanager-gw-route.yaml`

### Check/update your listener

Make sure you have a listener configured on your gateway for the HTTPRoute you created.  As an example, you should have something like the following in your gateway configuration:

``` yaml
  - allowedRoutes:
      namespaces:
        from: All
    hostname: alertmanager.example.com
    name: am-https
    port: 443
    protocol: HTTPS
    tls:
      certificateRefs:
      - group: ""
        kind: Secret
        name: alertmanager-envoy-secret
      mode: Terminate
```


## Register an OIDC application

Registering the Azure OIDC application is beyond the scope of this article.  You will need to add a redirect url and you will need to know your client and tenant ids as well as your client secret.  Once you have all that information, you may proceed to configuring the Kubernetes secret and security policy. 

## Kubernetes secret

You will need to create a kubernetes secret that contains the client secret for your Azure application.  You can either use a yaml file or paste the secret on the command line.

=== "CLI"
    ``` shell
    read -s CLIENT_SECRET
    read -p "Please enter the application namespace: " APP_NAMESPACE
    read -p "Please enter the application name: " APP_NAME
    kubectl -n ${APP_NAMESPACE} create secret generic azuread-client-secret-${APP_NAME} --from-literal=client-secret=${CLIENT_SECRET}
    ```

=== "YAML"
    ``` yaml title="azuread-client-secret-APP_NAME.yaml"
    apiVersion: v1
    data:
      client-secret: <BASE64_ENCODED_CLIENT_SECRET>
    kind: Secret
    metadata:
      name: azuread-client-secret
      namespace: <APP_NAMESPACE>
    type: Opaque
    ```

    `kubectl apply -f azuread-client-secret-<APP_NAME>`


## Create the Security Policy

``` yaml title="alertmanager-sp.yaml"
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  annotations:
  generation: 1
  name: azuread-oidc-policy
  namespace: <APP_NAMESPACE>
spec:
  oidc:
    clientID: <CLIENT_ID>
    clientSecret:
      group: ""
      kind: Secret
      name: azuread-client-secret-<APP_NAME>
    logoutPath: /<APP_NAME>/logout
    provider:
      issuer: https://login.microsoftonline.com/<TENANT_ID>/v2.0
    redirectURL: https://alertmanager.example.com/<APP_NAME>/oauth2/callback
  targetRefs:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: <HTTPROUTE_NAME>
```

`kubectl -f apply alertmanager-sp.yaml`

!!! note "Your redirect URL in the SecurityPolicy must match what you configured in your OIDC application"
