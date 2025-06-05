# Deploy Cinder

OpenStack Cinder is a core component of the OpenStack cloud computing platform, responsible for providing scalable, persistent block storage to cloud instances. It allows users to manage volumes, snapshots, and backups, enabling efficient storage operations within both private and public cloud environments. This document details the deployment of OpenStack Cinder within Genestack.

> Genestack facilitates the deployment process by leveraging Kubernetes' orchestration capabilities, ensuring seamless integration and management of Cinder services spanning across storage types, platforms and environments.

## Create secrets

!!! note "Information about the secretes used"

    Manual secret generation is only required if you haven't run the `create-secrets.sh` script located in `/opt/genestack/bin`.

    ??? example "Example secret generation"

        ``` shell
        kubectl --namespace openstack \
                create secret generic cinder-rabbitmq-password \
                --type Opaque \
                --from-literal=username="cinder" \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-64};echo;)"
        kubectl --namespace openstack \
                create secret generic cinder-db-password \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        kubectl --namespace openstack \
                create secret generic cinder-admin \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        ```

## Run the package deployment

!!! example "Run the Cinder deployment Script `/opt/genestack/bin/install-cinder.sh`"

    ``` shell
    --8<-- "bin/install-cinder.sh"
    ```

!!! tip

    You may need to provide custom values to configure your openstack services, for a simple single region or lab deployment you can supply an additional overrides flag using the example found at `base-helm-configs/aio-example-openstack-overrides.yaml`.
    In other cases such as a multi-region deployment you may want to view the [Multi-Region Support](multi-region-support.md) guide to for a workflow solution.

## Demo

[![asciicast](https://asciinema.org/a/629808.svg)](https://asciinema.org/a/629808)
