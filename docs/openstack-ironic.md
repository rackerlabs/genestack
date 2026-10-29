# Deploy Ironic

OpenStack Ironic is the bare metal provisioning service within the OpenStack ecosystem, responsible for managing physical servers in a manner similar to how Nova manages virtual machines. Ironic enables operators to provision, deploy, and manage bare metal machines, treating them as first-class resources in the cloud. It supports a wide range of hardware through standard interfaces such as IPMI, Redfish, and vendor-specific drivers, allowing automated control of power, boot devices, and deployment workflows.
Ironic integrates with other OpenStack services such as Keystone for authentication, Glance for image management, Neutron for networking, and Placement for resource tracking. It provides flexible deployment options, including traditional image-based provisioning as well as newer container-native approaches. With features like automated cleaning, hardware inspection, and rescue capabilities, Ironic ensures that bare metal resources are securely prepared and efficiently utilized.
In this document, we will discuss the deployment of OpenStack Ironic using Genestack. Genestack streamlines the deployment and lifecycle management of Ironic by leveraging containerized services and Kubernetes orchestration. It simplifies scaling, improves operational consistency, and integrates Ironic seamlessly into the broader OpenStack control plane, enabling reliable and secure bare metal provisioning at scale.

## Create secrets

!!! note "Information about the secrets used"

    Service secrets are managed idempotently by this service's install script. The installer creates any missing Kubernetes secrets and reuses existing values.

## Run the package deployment

!!! example "Run the Heat deployment Script `/opt/genestack/bin/install-ironic.sh`"

    ``` shell
    --8<-- "bin/install-ironic.sh"
    ```

!!! tip

    In other cases such as a multi-region deployment you may want to view the [Multi-Region Support](multi-region-support.md) guide to for a workflow solution. You may also have to define additional policy for accessing the baremetal cli as ironic has multi-tenancy feature in place.

## Validate functionality

``` shell
kubectl --namespace openstack exec -ti openstack-admin-client -- openstack baremetal conductor list
```
