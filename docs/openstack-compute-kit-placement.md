# Deploy Placement

!!! example "Run the Placement deployment Script `bin/install-placement.sh`"

    ``` shell
    --8<-- "bin/install-placement.sh"
    ```

## Custom Listeners

!!! note "This step is not needed if all listeners were applied when the Gateway API was deployed"

??? abstract "Example listener patch file found in `/opt/genestack/etc/gateway-api/listeners`"

    ``` yaml
    --8<-- "etc/gateway-api/listeners/placement-https.json"
    ```

### Modify the Listener Patch

This example changes the placeholder domain to `<YOUR_DOMAIN>`. Review the [gateway documentation](https://gateway-api.sigs.k8s.io/api-types/gateway)
for more information on listener types.

``` shell
mkdir -p /etc/genestack/gateway-api/listeners
sed 's/your.domain.tld/<YOUR_DOMAIN>/g' \
    /opt/genestack/etc/gateway-api/listeners/placement-https.json \
    > /etc/genestack/gateway-api/listeners/placement-https.json
```

### Apply the Listener Patch

``` shell
kubectl patch -n nginx-gateway gateway flex-gateway \
              --type='json' \
              --patch-file /etc/genestack/gateway-api/listeners/placement-https.json
```

## Custom Placement Routes

!!! note "This step is not needed if all routes were applied when the Gateway API was deployed"

A custom gateway route can be used when setting up the service. The custom route make it possible to for a domain like `your.domain.tld` to be used for the service.

??? abstract "Example routes file found in `/opt/genestack/etc/gateway-api/routes`"

    ``` yaml
    --8<-- "etc/gateway-api/routes/custom-placement-gateway-route.yaml"
    ```

### Modify the Placement Route

This example changes the placeholder domain to `<YOUR_DOMAIN>`. Review the [gateway route documentation](https://gateway-api.sigs.k8s.io/api-types/httproute)
for more information on route types.

``` shell
mkdir -p /etc/genestack/gateway-api/routes
sed 's/your.domain.tld/<YOUR_DOMAIN>/g' \
    /opt/genestack/etc/gateway-api/routes/custom-placement-gateway-route.yaml \
    > /etc/genestack/gateway-api/routes/custom-placement-gateway-route.yaml
```

### Apply the Placement Route

``` shell
kubectl --namespace openstack apply -f /etc/genestack/gateway-api/routes/custom-placement-gateway-route.yaml
```
