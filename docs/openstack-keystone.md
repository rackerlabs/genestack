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

!!! example "Run the Keystone deployment Script `/opt/genestack/bin/install-keystone.sh`"

    ``` shell
    --8<-- "bin/install-keystone.sh"
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

## Demo

[![asciicast](https://asciinema.org/a/629802.svg)](https://asciinema.org/a/629802)
