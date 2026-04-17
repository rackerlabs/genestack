# Deploy Ironic

OpenStack Ironic is the bare metal provisioning service within the OpenStack ecosystem, responsible for managing physical servers in a manner similar to how Nova manages virtual machines. Ironic enables operators to provision, deploy, and manage bare metal machines, treating them as first-class resources in the cloud. It supports a wide range of hardware through standard interfaces such as IPMI, Redfish, and vendor-specific drivers, allowing automated control of power, boot devices, and deployment workflows.
Ironic integrates with other OpenStack services such as Keystone for authentication, Glance for image management, Neutron for networking, and Placement for resource tracking. It provides flexible deployment options, including traditional image-based provisioning as well as newer container-native approaches. With features like automated cleaning, hardware inspection, and rescue capabilities, Ironic ensures that bare metal resources are securely prepared and efficiently utilized.
In this document, we will discuss the deployment of OpenStack Ironic using Genestack. Genestack streamlines the deployment and lifecycle management of Ironic by leveraging containerized services and Kubernetes orchestration. It simplifies scaling, improves operational consistency, and integrates Ironic seamlessly into the broader OpenStack control plane, enabling reliable and secure bare metal provisioning at scale.

## Create secrets

!!! note "Information about the secretes used"

    Manual secret generation is only required if you haven't run the `create-secrets.sh` script located in `/opt/genestack/bin`.

    ??? example "Manual secret generation"

        ``` shell
        kubectl --namespace openstack \
                create secret generic ironic-rabbitmq-password \
                --type Opaque \
                --from-literal=username="ironic" \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-64};echo;)"
        kubectl --namespace openstack \
                create secret generic ironic-db-password \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        kubectl --namespace openstack \
                create secret generic ironic-admin \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        ```

## Run the package deployment

!!! example "Run the Heat deployment Script `/opt/genestack/bin/install-ironic.sh`"

    ``` shell
    --8<-- "bin/install-ironic.sh"
    ```

!!! tip

    You may need to provide custom values to configure your openstack services, for a simple single region or lab deployment you can supply an additional overrides flag using the example found at `base-helm-configs/aio-example-openstack-overrides.yaml`.
    In other cases such as a multi-region deployment you may want to view the [Multi-Region Support](multi-region-support.md) guide to for a workflow solution. You may also have to define additional policy for accessing the baremetal cli as ironic has multi-tenancy feature in place.

## Validate functionality

``` shell
kubectl --namespace openstack exec -ti openstack-admin-client -- openstack baremetal conductor list
```
