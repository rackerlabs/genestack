# Deploy Ceilometer

OpenStack Ceilometer is the telemetry service within the OpenStack ecosystem, responsible for collecting and delivering usage data across various OpenStack services. Ceilometer plays a critical role in monitoring and metering the performance and resource consumption of cloud infrastructure, providing essential data for billing, benchmarking, and operational insights. By aggregating metrics such as CPU usage, network bandwidth, and storage consumption, Ceilometer enables cloud operators to track resource usage, optimize performance, and ensure compliance with service-level agreements. In this document, we will discuss the deployment of OpenStack Ceilometer using Genestack. With Genestack, the deployment of Ceilometer is made more efficient, ensuring that comprehensive and reliable telemetry data is available to support the effective management and optimization of cloud resources.

## Prerequisites

Ceilometer in Genestack depends on Gnocchi for metric storage and indexing.
Before installing Ceilometer, ensure the following are already healthy:

- [Gnocchi](openstack-gnocchi.md) is installed and `gnocchi-api` has ready endpoints.
- [PostgreSQL](infrastructure-postgresql.md) is installed for Gnocchi indexer storage.
- A Ceph backend is available for Gnocchi metric storage.
  - Internal Ceph: [Rook (Ceph) - In Cluster](storage-ceph-rook-internal.md)
  - External Ceph: see the Ceph options in [Deploy Gnocchi](openstack-gnocchi.md)

If Gnocchi is not healthy, Ceilometer pods will remain in their init dependency
wait state until `gnocchi-api`, `ceilometer-db-sync`, and `ceilometer-ks-user`
are all resolved.

## Secrets

!!! note

    Secrets are generated and applied automatically by the install script.

## Run the package deployment

!!! example "Run the Ceilometer deployment Script"

    ``` shell
    /opt/genestack/bin/install.sh --service ceilometer
    ```

!!! tip

    In other cases such as a multi-region deployment you may want to view the [Multi-Region Support](multi-region-support.md) guide to for a workflow solution.

## Validate the deployment

### Confirm install idempotency

Run the install script a second time and confirm it completes without error.

``` shell
sudo /opt/genestack/bin/install.sh --service ceilometer
```

### Confirm Ceilometer pods are running

``` shell
kubectl get jobs,pods -n openstack | grep ceilometer
```

Expected steady state:
- `ceilometer-db-sync` is `Complete`
- `ceilometer-ks-user` is `Complete`
- `ceilometer-central` is `Running`
- `ceilometer-compute` pods are `Running`
- `ceilometer-notification` pods are `Running`

### Capture pod resource usage

``` shell
kubectl top pods -n openstack | grep ceilometer
```

## Verify Ceilometer Workers

As there is no Ceilometer API, we will do a quick validation against the
Gnocchi API via a series of `openstack metric` commands to confirm that
Ceilometer workers are ingesting metric and event data then persisting them
to storage.

### Verify metric resource types exist

The Ceilomter db-sync job will create the various resource types in Gnocchi.
Without them, metrics can't be stored, so let's verify they exist. The
output should include named resource types and some attributes for resources
like `instance`, `instance_disk`, `network`, `volume`, etc.

``` shell
kubectl exec -it openstack-admin-client -n openstack -- openstack metric resource-type list
```

### Verify metric resources

Confirm that resources are populating in Gnocchi

``` shell
kubectl exec -it openstack-admin-client -n openstack -- openstack metric resource list
```

### Verify metrics

Confirm that metrics can be retrieved from Gnocchi

``` shell
kubectl exec -it openstack-admin-client -n openstack -- openstack metric list
```
