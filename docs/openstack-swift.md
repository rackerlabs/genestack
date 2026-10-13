!!! genestack "TECH PREVIEW"

# Deploy Swift

OpenStack Swift is a highly available, distributed, eventually consistent object store. Genestack deploys Swift with the
upstream openstack-helm `swift` chart and the `ghcr.io/rackerlabs/genestack-images/swift` image. That single image
provides every Swift role: proxy, account, container and object servers with their replicators, auditors, updaters,
reaper and expirer, as well as `swift-ring-builder` and the `rsync` replication daemon.

For background on Swift itself see [Swift Object Storage](openstack-object-storage-swift.md) and the
[Swift Operators Guide](openstack-swift-operators-guide.md).

## Operator supplied storage and ring settings

Genestack does not choose disks or ring layouts for you. Before deploying Swift you must:

1. Label the nodes that will run the Swift storage DaemonSet.

    ``` shell
    kubectl label node <node-name> openstack-storage-node=enabled
    ```

2. Format and mount every data device on each storage node under `/srv/node/<device>` (XFS is recommended).

    ``` shell
    mkfs.xfs -L sdb /dev/sdb
    mkdir -p /srv/node/sdb
    mount -o noatime LABEL=sdb /srv/node/sdb
    ```

3. Describe the devices and ring parameters in `/etc/genestack/helm-configs/swift/swift-helm-overrides.yaml`.

    ``` yaml
    ring:
      partition_power: 14   # 2^14 partitions; size this for the cluster's final disk count
      replicas: 3
      min_part_hours: 24
      devices:
        - name: sdb         # must match the mountpoint under /srv/node/
          weight: 100
        - name: sdc
          weight: 100
      shared_storage:
        storageClassName: general-multi-attach   # any ReadWriteMany storage class
    ```

!!! warning "Ring and hash path settings"

    `partition_power` cannot be changed after the rings are built, and the swift hash path prefix/suffix (stored in the
    `swift-hash-path-prefix` and `swift-hash-path-suffix` secrets) must never change once data has been written. Back
    these secrets and the ring builder files up.

!!! note "Ring builder scope"

    The upstream chart's ring builder job adds the listed devices for the IP of the node the job runs on, in region 1,
    zone 1. Multi-node, multi-zone or multi-region rings need to be built by the operator and supplied to the cluster.

## Create secrets

!!! note "Information about the secrets used"

    Service secrets are managed idempotently by this service's install script. The installer creates any missing
    Kubernetes secrets (`swift-admin`, `swift-hash-path-prefix`, `swift-hash-path-suffix`) and reuses existing values.

## Run the package deployment

!!! example "Run the Swift deployment Script `/opt/genestack/bin/install-swift.sh`"

    ``` shell
    --8<-- "bin/install-swift.sh"
    ```

!!! tip

    You may need to provide custom values to configure your OpenStack services.
    For a simple single region or lab deployment you can supply an additional
    overrides flag using the example found at
    `base-helm-configs/aio-example-openstack-overrides.yaml`.

## Public endpoint

The Swift proxy is exposed through the Envoy Gateway using the `swift-https` listener and the
`custom-swift-gateway-route` HTTPRoute found in `etc/gateway-api`. Update the hostname `swift.your.domain.tld`, and
set the public endpoint in your endpoint overrides.

``` yaml
endpoints:
  object_store:
    host_fqdn_override:
      public:
        tls: {}
        host: swift.your.domain.tld
    port:
      api:
        public: 443
    scheme:
      public: https
```

## Middleware

The base overrides enable `s3api`/`s3token` (S3 compatible API using Keystone EC2 credentials), `keystonemiddleware`
authentication and `ceilometermiddleware`. The ceilometer middleware uses the `noop` driver by default; set
`conf.proxy_server."filter:ceilometer".driver` to `messagingv2` and provide a transport URL when Ceilometer is enabled.

## Validate functionality

``` shell
kubectl --namespace openstack exec -ti openstack-admin-client -- openstack container create genestack-test
kubectl --namespace openstack exec -ti openstack-admin-client -- openstack container list
```
