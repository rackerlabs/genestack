# Deploy Cinder

OpenStack Cinder is a core component of the OpenStack cloud computing platform, responsible for providing scalable, persistent block storage to cloud instances. It allows users to manage volumes, snapshots, and backups, enabling efficient storage operations within both private and public cloud environments. This document details the deployment of OpenStack Cinder within Genestack.

> Genestack facilitates the deployment process by leveraging Kubernetes' orchestration capabilities, ensuring seamless integration and management of Cinder services spanning across storage types, platforms and environments.

## Create secrets

!!! note "Secret generation has been moved to the install-cinder.sh script"

## Run the package deployment

!!! example "Run the Cinder deployment Script `/opt/genestack/bin/install-cinder.sh`"

    ``` shell
    --8<-- "bin/install-cinder.sh"
    ```

!!! tip

    You may need to provide custom values to configure your openstack services, for a simple single region or lab deployment you can supply an additional overrides flag using the example found at `base-helm-configs/aio-example-openstack-overrides.yaml`.
    In other cases such as a multi-region deployment you may want to view the [Multi-Region Support](multi-region-support.md) guide to for a workflow solution.

!!! genestack "External Ceph Storage Backend"

    If Cinder will be deployed with an external Ceph storage backend, review the
    [OpenStack Cinder Ceph Store](openstack-cinder-ceph-store.md) operator
    documentation for additional steps and setup.

## Demo

[![asciicast](https://asciinema.org/a/629808.svg)](https://asciinema.org/a/629808)
