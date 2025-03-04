# Deploy Glance

OpenStack Glance is the image service within the OpenStack ecosystem, responsible for discovering, registering, and retrieving virtual machine images. Glance provides a centralized repository where users can store and manage a wide variety of VM images, ranging from standard operating system snapshots to custom machine images tailored for specific workloads. This service plays a crucial role in enabling rapid provisioning of instances by providing readily accessible, pre-configured images that can be deployed across the cloud. In this document, we will outline the deployment of OpenStack Glance using Genestack. The deployment process is streamlined, ensuring Glance is robustly integrated with other OpenStack services to deliver seamless image management and retrieval.

## Create secrets

!!! note "Information about the secretes used"

    Manual secret generation is only required if you haven't run the `create-secrets.sh` script located in `/opt/genestack/bin`.

    ??? example "Example secret generation"

        ``` shell
        kubectl --namespace openstack \
                create secret generic glance-rabbitmq-password \
                --type Opaque \
                --from-literal=username="glance" \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-64};echo;)"
        kubectl --namespace openstack \
                create secret generic glance-db-password \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        kubectl --namespace openstack \
                create secret generic glance-admin \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        ```

!!! info

    Before running the Glance deployment you should configure the backend which is defined in the `helm-configs/glance/glance-helm-overrides.yaml` file. The default is a making the assumption we're running with Ceph deployed by Rook so the backend is configured to be cephfs with multi-attach functionality. While this works great, you should consider all of the available storage backends and make the right decision for your environment.

## Run the package deployment

!!! example "Run the Glance deployment Script `bin/install-glance.sh`"

    ``` shell
    --8<-- "bin/install-glance.sh"
    ```

!!! tip

    You may need to provide custom values to configure your openstack services, for a simple single region or lab deployment you can supply an additional overrides flag using the example found at `base-helm-configs/aio-example-openstack-overrides.yaml`.
    In other cases such as a multi-region deployment you may want to view the [Multi-Region Support](multi-region-support.md) guide to for a workflow solution.

!!! note

    The defaults disable `storage_init` because we're using **pvc** as the image backend type. In production this should be changed to swift.

## Validate functionality

``` shell
kubectl --namespace openstack exec -ti openstack-admin-client -- openstack image list
```

!!! genestack "External Image Store"

    If glance will be deployed with an external swift storage backend, review the
    [OpenStack Glance Swift Store](openstack-glance-swift-store.md) operator documentation
    for additional steps and setup.

## Demo

[![asciicast](https://asciinema.org/a/629806.svg)](https://asciinema.org/a/629806)
