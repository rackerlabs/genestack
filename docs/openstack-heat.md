# Deploy Heat

OpenStack Heat is the orchestration service within the OpenStack ecosystem, designed to automate the deployment of cloud applications by orchestrating infrastructure resources such as compute instances, storage volumes, and networking components. Heat allows users to define the infrastructure and application stack in a template format, which can then be deployed and managed as a single unit. This capability facilitates the automated, repeatable, and consistent deployment of complex cloud environments, reducing manual intervention and minimizing errors. In this document, we will cover the deployment of OpenStack Heat using Genestack. With Genestack, the deployment of Heat is optimized, ensuring that cloud applications are efficiently orchestrated and managed, leading to improved scalability and reliability.

## Create secrets

!!! note "Information about the secretes used"

    Manual secret generation is only required if you haven't run the `create-secrets.sh` script located in `/opt/genestack/bin`.

    ??? example "Manual secret generation"

        ``` shell
        kubectl --namespace openstack \
                create secret generic heat-rabbitmq-password \
                --type Opaque \
                --from-literal=username="heat" \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-64};echo;)"
        kubectl --namespace openstack \
                create secret generic heat-db-password \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        kubectl --namespace openstack \
                create secret generic heat-admin \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        kubectl --namespace openstack \
                create secret generic heat-trustee \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        kubectl --namespace openstack \
                create secret generic heat-stack-user \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        ```

## Run the package deployment

``` shell
cd /opt/genestack/submodules/openstack-helm

helm upgrade --install heat ./heat \
  --namespace=openstack \
    --timeout 120m \
    -f /opt/genestack/base-helm-configs/heat/heat-helm-overrides.yaml \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.heat.password="$(kubectl --namespace openstack get secret heat-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.heat_trustee.password="$(kubectl --namespace openstack get secret heat-trustee -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.heat_stack_user.password="$(kubectl --namespace openstack get secret heat-stack-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.heat.password="$(kubectl --namespace openstack get secret heat-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set conf.heat.database.slave_connection="mysql+pymysql://heat:$(kubectl --namespace openstack get secret heat-db-password -o jsonpath='{.data.password}' | base64 -d)@mariadb-cluster-secondary.openstack.svc.cluster.local:3306/heat" \
    --set endpoints.oslo_messaging.auth.admin.password="$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.heat.password="$(kubectl --namespace openstack get secret heat-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)" \
    --post-renderer /opt/genestack/base-kustomize/kustomize.sh \
    --post-renderer-args heat/base
```

!!! tip

    You may need to provide custom values to configure your openstack services, for a simple single region or lab deployment you can supply an additional overrides flag using the example found at `base-helm-configs/aio-example-openstack-overrides.yaml`.
    In other cases such as a multi-region deployment you may want to view the [Multi-Region Support](multi-region-support.md) guide to for a workflow solution.

## Validate functionality

``` shell
kubectl --namespace openstack exec -ti openstack-admin-client -- openstack --os-interface internal orchestration service list
```

### Custom Routes

!!! note "This step is not needed if all routes were applied when the Gateway API was deployed"

A custom gateway route can be used when setting up the service. The custom route make it possible to for a domain like `your.domain.tld` to be used for the service.

??? abstract "Example routes file found in `/opt/genestack/etc/gateway-api/routes`"

    ``` yaml
    --8<-- "etc/gateway-api/routes/custom-heat-gateway-route.yaml"
    ```

#### Modify the Route

This example changes the placeholder domain to `<YOUR_DOMAIN>`. Review the [gateway route documentation](https://gateway-api.sigs.k8s.io/api-types/httproute)
for more information on route types.

##### Heat Route

``` shell
mkdir -p /etc/genestack/gateway-api/routes
sed 's/your.domain.tld/<YOUR_DOMAIN>/g' \
    /opt/genestack/etc/gateway-api/routes/custom-heat-gateway-route.yaml \
    > /etc/genestack/gateway-api/routes/custom-heat-gateway-route.yaml
```

##### Cloudformation Route

``` shell
mkdir -p /etc/genestack/gateway-api/routes
sed 's/your.domain.tld/<YOUR_DOMAIN>/g' \
    /opt/genestack/etc/gateway-api/routes/custom-cloudformation-gateway-route.yaml \
    > /etc/genestack/gateway-api/routes/custom-cloudformation-gateway-route.yaml
```

#### Apply the Heat Route

``` shell
kubectl --namespace openstack apply -f /etc/gateway-api/routes/custom-heat-gateway-route.yaml
```

#### Apply the Cloudformation Route

``` shell
kubectl --namespace openstack apply -f /etc/gateway-api/routes/custom-cloudformation-gateway-route.yaml
```

## Demo

[![asciicast](https://asciinema.org/a/629807.svg)](https://asciinema.org/a/629807)
