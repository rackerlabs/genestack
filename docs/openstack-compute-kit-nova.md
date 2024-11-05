# Deploy Nova

!!! example "Run the Nova deployment Script `bin/install-nova.sh`"

    ``` shell
    --8<-- "bin/install-nova.sh"
    ```

!!! tip

    You may need to provide custom values to configure your openstack services, for a simple single region or lab deployment you can supply an additional overrides flag using the example found at `base-helm-configs/aio-example-openstack-overrides.yaml`.
    In other cases such as a multi-region deployment you may want to view the [Multi-Region Support](multi-region-support.md) guide to for a workflow solution.

!!! note

    The above command is setting the ceph as disabled. While the K8S infrastructure has Ceph, we're not exposing ceph to our openstack environment.

If running in an environment that doesn't have hardware virtualization extensions add the following two `set` switches to the install command.

``` shell
--set conf.nova.libvirt.virt_type=qemu --set conf.nova.libvirt.cpu_mode=none
```

!!! tip

    You may need to provide custom values to configure your openstack services, for a simple single region or lab deployment you can supply an additional overrides flag using the example found at `base-helm-configs/aio-example-openstack-overrides.yaml`.
    In other cases such as a multi-region deployment you may want to view the [Multi-Region Support](multi-region-support.md) guide to for a workflow solution.

## Custom Nova Listeners

!!! note "This step is not needed if all listeners were applied when the Gateway API was deployed"

??? abstract "Example listener patch file found in `/opt/genestack/etc/gateway-api/listeners`"

    ``` yaml
    --8<-- "etc/gateway-api/listeners/nova-https.json"
    ```

### Modify the Nova Listener Patches

This example changes the placeholder domain to `<YOUR_DOMAIN>`. Review the [gateway listener documentation](https://gateway-api.sigs.k8s.io/api-types/gateway)
for more information on listener types.

#### Nova Patch

``` shell
mkdir -p /etc/genestack/gateway-api/listeners
sed 's/your.domain.tld/<YOUR_DOMAIN>/g' \
    /opt/genestack/etc/gateway-api/listeners/nova-https.json \
    > /etc/genestack/gateway-api/listeners/nova-https.json
```

#### Novnc Patch

``` shell
mkdir -p /etc/genestack/gateway-api/listeners
sed 's/your.domain.tld/<YOUR_DOMAIN>/g' \
    /opt/genestack/etc/gateway-api/listeners/novnc-https.json \
    > /etc/genestack/gateway-api/listeners/novnc-https.json
```

#### Metadata Patch

``` shell
mkdir -p /etc/genestack/gateway-api/listeners
sed 's/your.domain.tld/<YOUR_DOMAIN>/g' \
    /opt/genestack/etc/gateway-api/listeners/metadata-https.json \
    > /etc/genestack/gateway-api/listeners/metadata-https.json
```

#### Apply the Nova Listener Patch

``` shell
kubectl patch -n nginx-gateway gateway flex-gateway \
              --type='json' \
              --patch-file /etc/genestack/gateway-api/listeners/nova-https.json
```

#### Apply the Novnc Listener Patch

``` shell
kubectl patch -n nginx-gateway gateway flex-gateway \
              --type='json' \
              --patch-file /etc/genestack/gateway-api/listeners/novnc-https.json
```

#### Apply the Metadata Listener Patch

``` shell
kubectl patch -n nginx-gateway gateway flex-gateway \
              --type='json' \
              --patch-file /etc/genestack/gateway-api/listeners/metadata-https.json
```

## Custom Nova Routes

!!! note "This step is not needed if all routes were applied when the Gateway API was deployed"

A custom gateway route can be used when setting up the service. The custom route make it possible to for a domain like `your.domain.tld` to be used for the service.

??? abstract "Example routes file found in `/opt/genestack/etc/gateway-api/routes`"

    ``` yaml
    --8<-- "etc/gateway-api/routes/custom-nova-gateway-route.yaml"
    ```

### Modifying the Nova Routes

This example changes the placeholder domain to `<YOUR_DOMAIN>`. Review the [gateway route documentation](https://gateway-api.sigs.k8s.io/api-types/httproute)
for more information on route types.

#### Nova Route

``` shell
mkdir -p /etc/genestack/gateway-api/routes
sed 's/your.domain.tld/<YOUR_DOMAIN>/g' \
    /opt/genestack/etc/gateway-api/routes/custom-nova-gateway-route.yaml \
    > /etc/genestack/gateway-api/routes/custom-nova-gateway-route.yaml
```

#### Novnc Route

``` shell
mkdir -p /etc/genestack/gateway-api/routes
sed 's/your.domain.tld/<YOUR_DOMAIN>/g' \
    /opt/genestack/etc/gateway-api/routes/custom-novnc-gateway-route.yaml \
    > /etc/genestack/gateway-api/routes/custom-novnc-gateway-route.yaml
```

#### Metadata Route

``` shell
mkdir -p /etc/genestack/gateway-api/routes
sed 's/your.domain.tld/<YOUR_DOMAIN>/g' \
    /opt/genestack/etc/gateway-api/routes/custom-metadata-gateway-route.yaml \
    > /etc/genestack/gateway-api/routes/custom-metadata-gateway-route.yaml
```

#### Apply the Nova Route

``` shell
kubectl --namespace openstack apply -f /etc/genestack/gateway-api/routes/custom-nova-gateway-route.yaml
```

#### Apply the Novnc Route

``` shell
kubectl --namespace openstack apply -f /etc/genestack/gateway-api/routes/custom-novnc-gateway-route.yaml
```

#### Apply the Metadata Route

``` shell
kubectl --namespace openstack apply -f /etc/genestack/gateway-api/routes/custom-metadata-gateway-route.yaml
```
