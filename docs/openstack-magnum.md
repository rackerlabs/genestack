# Deploy Magnum

OpenStack Magnum is the container orchestration service within the OpenStack ecosystem, designed to provide an easy-to-use interface for deploying and managing container clusters, such as Kubernetes. Magnum enables cloud users to harness the power of containerization by allowing them to create and manage container clusters as first-class resources within the OpenStack environment. This service integrates seamlessly with other OpenStack components, enabling containers to take full advantage of OpenStack’s networking, storage, and compute capabilities. In this document, we will outline the deployment of OpenStack Magnum using Genestac. By utilizing Genestack, the deployment of Magnum is streamlined, allowing organizations to efficiently manage and scale containerized applications alongside traditional virtual machine workloads within their cloud infrastructure.

!!! note

    Before Magnum can be deployed, you must setup and deploy [Barbican](openstack-barbican.md) first.

## Create secrets

!!! note "Information about the secrets used"

    Manual secret generation is only required if you haven't run the `create-secrets.sh` script located in `/opt/genestack/bin`.

    ??? example "Example secret generation"

        ``` shell
        kubectl --namespace openstack \
                create secret generic magnum-rabbitmq-password \
                --type Opaque \
                --from-literal=username="magnum" \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-64};echo;)"
        kubectl --namespace openstack \
                create secret generic magnum-db-password \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        kubectl --namespace openstack \
                create secret generic magnum-admin \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        ```

## Run the package deployment

!!! example "Run the Magnum deployment Script `bin/install-magnum.sh`"

    ``` shell
    --8<-- "bin/install-magnum.sh"
    ```

!!! tip

    You may need to provide custom values to configure your openstack services, for a simple single region or lab deployment you can supply an additional overrides flag using the example found at `base-helm-configs/aio-example-openstack-overrides.yaml`.
    In other cases such as a multi-region deployment you may want to view the [Multi-Region Support](multi-region-support.md) guide to for a workflow solution.

## Validate functionality

``` shell
kubectl --namespace openstack exec -ti openstack-admin-client -- openstack coe cluster list
```

## Create a Default Public ClusterTemplate

User must have the admin role to create the public ClusterTemplate. For instructions on creating the default public ClusterTemplate and using it to deploy a new Kubernetes cluster, please refer to the ClusterTemplate section in the [Magnum Kubernetes Cluster Setup Guide](https://docs.rackspacecloud.com/magnum-kubernetes-cluster-setup-guide/#clustertemplate).
