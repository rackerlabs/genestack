# Deploy Neutron

``` shell
cd /opt/genestack/submodules/openstack-helm

helm upgrade --install neutron ./neutron \
  --namespace=openstack \
    --timeout 120m \
    -f /opt/genestack/base-helm-configs/neutron/neutron-helm-overrides.yaml \
    --set conf.metadata_agent.DEFAULT.metadata_proxy_shared_secret="$(kubectl --namespace openstack get secret metadata-shared-secret -o jsonpath='{.data.password}' | base64 -d)" \
    --set conf.ovn_metadata_agent.DEFAULT.metadata_proxy_shared_secret="$(kubectl --namespace openstack get secret metadata-shared-secret -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.neutron.password="$(kubectl --namespace openstack get secret neutron-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.nova.password="$(kubectl --namespace openstack get secret nova-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.placement.password="$(kubectl --namespace openstack get secret placement-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.designate.password="$(kubectl --namespace openstack get secret designate-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.ironic.password="$(kubectl --namespace openstack get secret ironic-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.neutron.password="$(kubectl --namespace openstack get secret neutron-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set conf.neutron.database.slave_connection="mysql+pymysql://neutron:$(kubectl --namespace openstack get secret neutron-db-password -o jsonpath='{.data.password}' | base64 -d)@mariadb-cluster-secondary.openstack.svc.cluster.local:3306/neutron" \
    --set endpoints.oslo_messaging.auth.admin.password="$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.neutron.password="$(kubectl --namespace openstack get secret neutron-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set conf.neutron.ovn.ovn_nb_connection="tcp:$(kubectl --namespace kube-system get service ovn-nb -o jsonpath='{.spec.clusterIP}:{.spec.ports[0].port}')" \
    --set conf.neutron.ovn.ovn_sb_connection="tcp:$(kubectl --namespace kube-system get service ovn-sb -o jsonpath='{.spec.clusterIP}:{.spec.ports[0].port}')" \
    --set conf.plugins.ml2_conf.ovn.ovn_nb_connection="tcp:$(kubectl --namespace kube-system get service ovn-nb -o jsonpath='{.spec.clusterIP}:{.spec.ports[0].port}')" \
    --set conf.plugins.ml2_conf.ovn.ovn_sb_connection="tcp:$(kubectl --namespace kube-system get service ovn-sb -o jsonpath='{.spec.clusterIP}:{.spec.ports[0].port}')" \
    --post-renderer /opt/genestack/base-kustomize/kustomize.sh \
    --post-renderer-args neutron/base
```

!!! tip

    You may need to provide custom values to configure your openstack services, for a simple single region or lab deployment you can supply an additional overrides flag using the example found at `base-helm-configs/aio-example-openstack-overrides.yaml`.
    In other cases such as a multi-region deployment you may want to view the [Multi-Region Support](multi-region-support.md) guide to for a workflow solution.

!!! info

    The above command derives the OVN north/south bound database from our K8S environment. The insert `set` is making the assumption we're using **tcp** to connect.

## Custom Listeners

!!! note "This step is not needed if all listeners were applied when the Gateway API was deployed"

??? abstract "Example listener patch file found in `/opt/genestack/etc/gateway-api/listeners`"

    ``` yaml
    --8<-- "etc/gateway-api/listeners/neutron-https.json"
    ```

This example changes the placeholder domain to `<YOUR_DOMAIN>`. Review the [gateway documentation](https://gateway-api.sigs.k8s.io/api-types/gateway)
for more information on listener types.

### Modify the Listener Patch

``` shell
mkdir -p /etc/genestack/gateway-api/listeners
sed 's/your.domain.tld/<YOUR_DOMAIN>/g' \
    /opt/genestack/etc/gateway-api/listeners/neutron-https.json \
    > /etc/genestack/gateway-api/listeners/neutron-https.json
```

### Apply the Listener Patch

``` shell
kubectl patch -n nginx-gateway gateway flex-gateway \
              --type='json' \
              --patch-file /etc/genestack/gateway-api/listeners/neutron-https.json
```

## Custom Neutron Routes

!!! note "This step is not needed if all routes were applied when the Gateway API was deployed"

A custom gateway route can be used when setting up the service. The custom route make it possible to for a domain like `your.domain.tld` to be used for the service.

??? abstract "Example routes file found in `/opt/genestack/etc/gateway-api/routes`"

    ``` yaml
    --8<-- "etc/gateway-api/routes/custom-neutron-gateway-route.yaml"
    ```

### Modify the Neutron Route

This example changes the placeholder domain to `<YOUR_DOMAIN>`. Review the [gateway route documentation](https://gateway-api.sigs.k8s.io/api-types/httproute)
for more information on route types.

``` shell
mkdir -p /etc/genestack/gateway-api/routes
sed 's/your.domain.tld/<YOUR_DOMAIN>/g' \
    /opt/genestack/etc/gateway-api/routes/custom-neutron-gateway-route.yaml \
    > /etc/genestack/gateway-api/routes/custom-neutron-gateway-route.yaml
```

### Apply the Neutron Route

``` shell
kubectl --namespace openstack apply -f /etc/genestack/gateway-api/routes/custom-neutron-gateway-route.yaml
```

## Neutron MTU settings / Jumbo frames / overlay networks on instances

!!! warning You will likely need to increase the MTU as described here if you want to support creating L3 overlay networks (via any software that creates nested networks, such as _Genestack_ itself, VPN, etc.) on your nova instances. Your physical L2 network will need jumbo frames to support this. You will likely end up with an MTU of 1280 for overlay networks on instances if you don't, and the abnormally small MTU can cause various problems, perhaps even reaching a size too small for the software to support).

[Neutron documentation on MTU considerations](https://docs.openstack.org/neutron/latest/admin/config-mtu.html)

As an example of changing some values of interest, in a file for your Neutron
Helm overrides, you can use a stanza like:

```
conf:
  neutron:
    DEFAULT:
      global_physnet_mtu: 9000
  plugins:
    ml2_conf:
      ml2:
        path_mtu: 4000
        physical_network_mtus: physnet1:1500
```

(You can see the Neutron helm overrides file in the installation command above
as `-f /opt/genestack/base-helm-configs/neutron/neutron-helm-overrides.yaml`,
but you can supply this information with a second `-f` switch in a separate
overrides file for your environment if desired. If so, place your second
`-f` after the first.)

With the settings in the example, physical networks get a default MTU of 9000 in
`global_physnet_mtu`. You can override this for specific networks in
`physical_network_mtus`, which shows `physnet1` with an MTU of 1500 here, which
handles public Internet traffic in this case, which shouldn't get jumbo frames.

`path_mtu` sets the MTU for tenant or project networks. For `path_mtu` 4000 in
the example, nova instances will get an MTU of 3942 after 58 bytes of overhead.
