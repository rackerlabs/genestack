# Deploy Nova

``` shell
cd /opt/genestack/submodules/openstack-helm

helm upgrade --install nova ./nova \
  --namespace=openstack \
    --timeout 120m \
    -f /opt/genestack/base-helm-configs/nova/nova-helm-overrides.yaml \
    --set conf.nova.neutron.metadata_proxy_shared_secret="$(kubectl --namespace openstack get secret metadata-shared-secret -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.nova.password="$(kubectl --namespace openstack get secret nova-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.neutron.password="$(kubectl --namespace openstack get secret neutron-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.ironic.password="$(kubectl --namespace openstack get secret ironic-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.placement.password="$(kubectl --namespace openstack get secret placement-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.cinder.password="$(kubectl --namespace openstack get secret cinder-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.nova.password="$(kubectl --namespace openstack get secret nova-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db_api.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db_api.auth.nova.password="$(kubectl --namespace openstack get secret nova-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db_cell0.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db_cell0.auth.nova.password="$(kubectl --namespace openstack get secret nova-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set conf.nova.database.slave_connection="mysql+pymysql://nova:$(kubectl --namespace openstack get secret nova-db-password -o jsonpath='{.data.password}' | base64 -d)@mariadb-cluster-secondary.openstack.svc.cluster.local:3306/nova" \
    --set conf.nova.api_database.slave_connection="mysql+pymysql://nova:$(kubectl --namespace openstack get secret nova-db-password -o jsonpath='{.data.password}' | base64 -d)@mariadb-cluster-secondary.openstack.svc.cluster.local:3306/nova_api" \
    --set conf.nova.cell0_database.slave_connection="mysql+pymysql://nova:$(kubectl --namespace openstack get secret nova-db-password -o jsonpath='{.data.password}' | base64 -d)@mariadb-cluster-secondary.openstack.svc.cluster.local:3306/nova_cell0" \
    --set endpoints.oslo_messaging.auth.admin.password="$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.nova.password="$(kubectl --namespace openstack get secret nova-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set network.ssh.public_key="$(kubectl -n openstack get secret nova-ssh-keypair -o jsonpath='{.data.public_key}' | base64 -d)"$'\n' \
    --set network.ssh.private_key="$(kubectl -n openstack get secret nova-ssh-keypair -o jsonpath='{.data.private_key}' | base64 -d)"$'\n' \
    --post-renderer /opt/genestack/base-kustomize/kustomize.sh \
    --post-renderer-args nova/base
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
kubectl --namespace openstack apply -f /etc/gateway-api/routes/custom-nova-gateway-route.yaml
```

#### Apply the Novnc Route

``` shell
kubectl --namespace openstack apply -f /etc/gateway-api/routes/custom-novnc-gateway-route.yaml
```

#### Apply the Metadata Route

``` shell
kubectl --namespace openstack apply -f /etc/gateway-api/routes/custom-metadata-gateway-route.yaml
```
