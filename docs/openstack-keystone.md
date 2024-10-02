# Deploy Keystone

OpenStack Keystone is the identity service within the OpenStack ecosystem, serving as the central authentication and authorization hub for all OpenStack services. Keystone manages user accounts, roles, and permissions, enabling secure access control across the cloud environment. It provides token-based authentication and supports multiple authentication methods, including username/password, LDAP, and federated identity. Keystone also offers a catalog of services, allowing users and services to discover and communicate with other OpenStack components. In this document, we will discuss the deployment of OpenStack Keystone using Genestack. Genestack simplifies the deployment and scaling of Keystone, ensuring robust authentication and authorization across the OpenStack architecture, and enhancing the overall security and manageability of cloud resources.

## Create secrets

!!! note "Information about the secretes used"

    Manual secret generation is only required if you haven't run the `create-secrets.sh` script located in `/opt/genestack/bin`.

    ??? example "Example secret generation"

        ``` shell
        kubectl --namespace openstack \
                create secret generic keystone-rabbitmq-password \
                --type Opaque \
                --from-literal=username="keystone" \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-64};echo;)"
        kubectl --namespace openstack \
                create secret generic keystone-db-password \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        kubectl --namespace openstack \
                create secret generic keystone-admin \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        kubectl --namespace openstack \
                create secret generic keystone-credential-keys \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        ```

## Run the package deployment

``` shell
cd /opt/genestack/submodules/openstack-helm

helm upgrade --install keystone ./keystone \
    --namespace=openstack \
    --wait \
    --timeout 120m \
    -f /etc/genestack/helm-configs/keystone/keystone-helm-overrides.yaml \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.keystone.password="$(kubectl --namespace openstack get secret keystone-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set conf.keystone.database.slave_connection="mysql+pymysql://keystone:$(kubectl --namespace openstack get secret keystone-db-password -o jsonpath='{.data.password}' | base64 -d)@mariadb-cluster-secondary.openstack.svc.cluster.local:3306/keystone" \
    --set endpoints.oslo_messaging.auth.admin.password="$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.keystone.password="$(kubectl --namespace openstack get secret keystone-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)" \
    --post-renderer /etc/genestack/kustomize/kustomize.sh \
    --post-renderer-args keystone/base
```

!!! tip

    You may need to provide custom values to configure your openstack services, for a simple single region or lab deployment you can supply an additional overrides flag using the example found at `base-helm-configs/aio-example-openstack-overrides.yaml`.
    In other cases such as a multi-region deployment you may want to view the [Multi-Region Support](multi-region-support.md) guide to for a workflow solution.

!!! note

    The image used here allows the system to run with RXT global authentication federation. The federated plugin can be seen here, https://github.com/cloudnull/keystone-rxt

Deploy the openstack admin client pod (optional)

``` shell
kubectl --namespace openstack apply -f /etc/genestack/manifests/utils/utils-openstack-client-admin.yaml
```

## Validate functionality

``` shell
kubectl --namespace openstack exec -ti openstack-admin-client -- openstack user list
```

### Custom Listeners

!!! note "This step is not needed if all listeners were applied when the Gateway API was deployed"

??? abstract "Example listener patch file found in `/opt/genestack/etc/gateway-api/listeners`"

    ``` yaml
    --8<-- "etc/gateway-api/listeners/keystone-https.json"
    ```

#### Modify the Listener Patch

This example changes the placeholder domain to `<YOUR_DOMAIN>`. Review the [gateway listener documentation](https://gateway-api.sigs.k8s.io/api-types/gateway)
for more information on listener types.

``` shell
mkdir -p /etc/genestack/gateway-api/listeners
sed 's/your.domain.tld/<YOUR_DOMAIN>/g' \
    /opt/genestack/etc/gateway-api/listeners/keystone-https.json \
    > /etc/genestack/gateway-api/listeners/keystone-https.json
```

#### Apply the Listener Patch

``` shell
kubectl patch -n nginx-gateway gateway flex-gateway \
              --type='json' \
              --patch-file /etc/genestack/gateway-api/listeners/keystone-https.json
```

### Custom Routes

!!! note "This step is not needed if all routes were applied when the Gateway API was deployed"

A custom gateway route can be used when setting up the service. The custom route make it possible to for a domain like `your.domain.tld` to be used for the service.

??? abstract "Example routes file found in `/opt/genestack/etc/gateway-api/routes`"

    ``` yaml
    --8<-- "etc/gateway-api/routes/custom-keystone-gateway-route.yaml"
    ```

#### Modify the Route

This example changes the placeholder domain to `<YOUR_DOMAIN>`. Review the [gateway documentation](https://gateway-api.sigs.k8s.io/api-types/httproute)
for more information on route types.

``` shell
mkdir -p /etc/genestack/gateway-api/routes
sed 's/your.domain.tld/<YOUR_DOMAIN>/g' \
    /opt/genestack/etc/gateway-api/routes/custom-keystone-gateway-route.yaml \
    > /etc/genestack/gateway-api/routes/custom-keystone-gateway-route.yaml
```

#### Apply the Route

``` shell
kubectl --namespace openstack apply -f /etc/genestack/gateway-api/routes/custom-keystone-gateway-route.yaml
```

## Demo

[![asciicast](https://asciinema.org/a/629802.svg)](https://asciinema.org/a/629802)
