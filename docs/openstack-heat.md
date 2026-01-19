# Deploy Heat

OpenStack Heat is the orchestration service within the OpenStack ecosystem, designed to automate the deployment of cloud applications by orchestrating infrastructure resources such as compute instances, storage volumes, and networking components. Heat allows users to define the infrastructure and application stack in a template format, which can then be deployed and managed as a single unit. This capability facilitates the automated, repeatable, and consistent deployment of complex cloud environments, reducing manual intervention and minimizing errors. In this document, we will cover the deployment of OpenStack Heat using Genestack. With Genestack, the deployment of Heat is optimized, ensuring that cloud applications are efficiently orchestrated and managed, leading to improved scalability and reliability.

## Create secrets

!!! note "Secret generation has been moved to the install-heat.sh script"

## Run the package deployment

!!! example "Run the Heat deployment Script `/opt/genestack/bin/install-heat.sh`"

    ``` shell
    --8<-- "bin/install-heat.sh"
    ```

!!! tip

    You may need to provide custom values to configure your openstack services, for a simple single region or lab deployment you can supply an additional overrides flag using the example found at `base-helm-configs/aio-example-openstack-overrides.yaml`.
    In other cases such as a multi-region deployment you may want to view the [Multi-Region Support](multi-region-support.md) guide to for a workflow solution.

## Validate functionality

``` shell
kubectl --namespace openstack exec -ti openstack-admin-client -- openstack --os-interface internal orchestration service list
```

## Demo

[![asciicast](https://asciinema.org/a/629807.svg)](https://asciinema.org/a/629807)
