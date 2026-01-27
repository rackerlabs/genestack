# Deploy Trove

OpenStack Trove is the Database as a Service (DBaaS) component of the OpenStack cloud computing platform, providing scalable and reliable database provisioning and management capabilities. It enables users to deploy, manage, and scale database instances without the complexity of manual database administration. This document details the deployment of OpenStack Trove within Genestack.

> Genestack facilitates the deployment process by leveraging Kubernetes' orchestration capabilities, ensuring seamless integration and management of Trove services across different database engines and environments.

## Create secrets

!!! note "Information about the secrets used"

    Manual secret generation is only required if you haven't run the `create-secrets.sh` script located in `/opt/genestack/bin`.

    ??? example "Example secret generation"

        ``` shell
        kubectl --namespace openstack \
                create secret generic trove-rabbitmq-password \
                --type Opaque \
                --from-literal=username="trove" \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-64};echo;)"
        kubectl --namespace openstack \
                create secret generic trove-db-password \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        kubectl --namespace openstack \
                create secret generic trove-admin \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        ```

## Define policy configuration

!!! note "Information about the default policy rules used"

    The default RabbitMQ policy sets quorum queues target group size to 3 for
    the `trove` vhost. This can be changed in `base-kustomize/trove/base/policies.yaml`.

    ??? example "Default RabbitMQ policy"

        ``` yaml
        apiVersion: rabbitmq.com/v1beta1
        kind: Policy
        metadata:
          name: trove-quorum-three-replicas
          namespace: openstack
        spec:
          name: trove-quorum-three-replicas
          vhost: "trove"
          pattern: ".*"
          applyTo: queues
          definition:
            target-group-size: 3
          priority: 0
          rabbitmqClusterReference:
            name: rabbitmq
        ```

## Run the package deployment

!!! example "Run the Trove deployment Script `/opt/genestack/bin/install-trove.sh`"

    ``` shell
    --8<-- "bin/install-trove.sh"
    ```

!!! tip

    You may need to provide custom values to configure your openstack services, for a simple single region or lab deployment you can supply an additional overrides flag using the example found at `base-helm-configs/aio-example-openstack-overrides.yaml`.
    In other cases such as a multi-region deployment you may want to view the [Multi-Region Support](multi-region-support.md) guide to for a workflow solution.

## Validate the Deployment

After deployment, verify that Trove services are running:

``` shell
kubectl --namespace openstack get pods -l application=trove
```

Check the Trove API endpoint:

``` shell
openstack database service list
```

## Database Instance Management

### Create a Database Instance

``` shell
openstack database instance create my-database \
    --flavor <flavor-id> \
    --size 10 \
    --datastore mysql \
    --datastore-version 5.7 \
    --nic net-id=<network-id>
```

### List Database Instances

``` shell
openstack database instance list
```

### Show Database Instance Details

``` shell
openstack database instance show my-database
```

### Create Database and Users

``` shell
# Create a database
openstack database db create my-database myapp_db

# Create a user with access to the database
openstack database user create my-database myapp_user myapp_password --databases myapp_db

# List databases
openstack database db list my-database

# List users
openstack database user list my-database
```

## Supported Datastores

Trove supports multiple database engines including:

- MySQL
- MariaDB
- PostgreSQL
- MongoDB
- Redis
- Cassandra

Configure datastore images and versions according to your requirements in the Helm overrides.

## Database Images

Before using Trove, you need to build and upload database images. For MySQL:

### Build MySQL 8.4 Image

``` shell
# Build and upload MySQL 8.4 image
/opt/genestack/scripts/build-trove-mysql-image.sh
```

### Configure Datastores

``` shell
# Setup MySQL datastores and versions
/opt/genestack/scripts/setup-trove-datastores.sh
```

For detailed instructions on building database images, see the [MySQL Images Guide](openstack-trove-mysql-images.md).

## Troubleshooting

### Check Trove Logs

``` shell
# API logs
kubectl --namespace openstack logs -l application=trove,component=api

# Conductor logs
kubectl --namespace openstack logs -l application=trove,component=conductor

# Taskmanager logs
kubectl --namespace openstack logs -l application=trove,component=taskmanager
```

### Common Issues

1. **Database instance creation fails**: Ensure that Nova, Neutron, and Cinder are properly configured and accessible
2. **Guest agent communication issues**: Verify network connectivity between Trove and database instances
3. **Image not found**: Ensure datastore images are properly uploaded to Glance

## Configuration Options

Key configuration options in `trove-helm-overrides.yaml`:

- `conf.trove.DEFAULT.default_datastore`: Default database engine
- `conf.trove.DEFAULT.management_networks`: Management network for guest instances
- `conf.trove.DEFAULT.network_driver`: Network driver configuration
- `pod.resources`: Resource requests and limits for Trove components

For advanced configuration, refer to the [OpenStack Trove documentation](https://docs.openstack.org/trove/latest/).
