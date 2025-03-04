# Custom Listeners

!!! note "This step is not needed if all listeners were applied when the Gateway API was deployed"

??? abstract "Example listener patch file found in `/opt/genestack/etc/gateway-api/listeners`"

    ``` yaml
    --8<-- "etc/gateway-api/listeners/<SERVICE_NAME>-https.json"
    ```

## Modify the Listener Patch

This example changes the placeholder domain to `<YOUR_DOMAIN>`. Review the [gateway documentation](https://gateway-api.sigs.k8s.io/api-types/gateway)
for more information on listener types.

``` shell
mkdir -p /etc/genestack/gateway-api/listeners
sed 's/your.domain.tld/<YOUR_DOMAIN>/g' \
    /opt/genestack/etc/gateway-api/listeners/<SERVICE_NAME>-https.json \
    > /etc/genestack/gateway-api/listeners/<SERVICE_NAME>-https.json
```

## Apply the Listener Patch

``` shell
kubectl patch -n nginx-gateway gateway flex-gateway \
              --type='json' \
              --patch-file /etc/genestack/gateway-api/listeners/<SERVICE_NAME>-https.json
```

## Custom Routes

!!! note "This step is not needed if all routes were applied when the Gateway API was deployed"

A custom gateway route can be used when setting up the service. The custom route make it possible for a domain like `your.domain.tld` to be used.

??? abstract "Example routes file found in `/opt/genestack/etc/gateway-api/routes`"

    ``` yaml
    --8<-- "etc/gateway-api/routes/custom-<SERVICE_NAME>-gateway-route.yaml"
    ```

## Modify the Route

This example changes the placeholder domain to `<YOUR_DOMAIN>`. Review the [gateway route documentation](https://gateway-api.sigs.k8s.io/api-types/httproute)
for more information on route types.

``` shell
mkdir -p /etc/genestack/gateway-api/routes
sed 's/your.domain.tld/<YOUR_DOMAIN>/g' \
    /opt/genestack/etc/gateway-api/routes/custom-<SERVICE_NAME>-gateway-route.yaml \
    > /etc/genestack/gateway-api/routes/custom-<SERVICE_NAME>-gateway-route.yaml
```

#### Apply the Route

``` shell
kubectl --namespace openstack apply -f /etc/genestack/gateway-api/routes/custom-<SERVICE_NAME>-gateway-route.yaml
```
