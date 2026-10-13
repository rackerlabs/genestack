!!! genestack "TECH PREVIEW"

# Deploy Swift

OpenStack Swift is a highly available, distributed, eventually consistent object store. Genestack deploys Swift with the
upstream openstack-helm `swift` chart and the `ghcr.io/rackerlabs/genestack-images/swift` image. That single image
provides every Swift role: proxy, account, container and object servers with their replicators, auditors, updaters,
reaper and expirer, as well as `swift-ring-builder` and the `rsync` replication daemon.

For background on Swift itself see [Swift Object Storage](openstack-object-storage-swift.md) and the
[Swift Operators Guide](openstack-swift-operators-guide.md).

## Node placement

| Component | Kind | Node label |
|:--|:--|:--|
| `swift-proxy` | Deployment | `openstack-control-plane=enabled` (same as the other OpenStack APIs) |
| `swift-storage` (account, container and object servers, replicators, auditors, updaters, rsync) | DaemonSet, `hostNetwork` | `swift-storage-node=enabled` |
| `swift-ring-builder` and keystone jobs | Job | `openstack-control-plane=enabled` |

``` shell
kubectl label node <storage-node> swift-storage-node=enabled
```

When nodes are labeled by the Genestack ansible role, put the Swift storage hosts in the `swift_storage_nodes`
inventory group.

## Operator supplied storage and ring settings

Genestack does not choose disks or ring layouts for you. Before deploying Swift you must:

1. Format and mount every data device on each storage node under `/srv/node/<device>` (XFS is recommended). The
   storage pods use host networking, so each device is reached on the node's IP.

    ``` shell
    mkfs.xfs -L sdb /dev/sdb
    mkdir -p /srv/node/sdb
    mount -o noatime LABEL=sdb /srv/node/sdb
    ```

2. Describe every device in `/etc/genestack/helm-configs/swift/swift-helm-overrides.yaml`.

    ``` yaml
    ring:
      partition_power: 14   # 2^14 partitions, cannot be changed later; keep <= 15 (see below)
      replicas: 3
      min_part_hours: 24
      devices:
        - name: sdb          # mountpoint under /srv/node on that node
          ip: 172.16.0.11    # the storage node's IP
          region: 1          # optional, default 1
          zone: 1            # optional, default 1
          weight: 100        # optional, default 100
        - name: sdb
          ip: 172.16.0.12
          zone: 2
        - name: sdb
          ip: 172.16.0.13
          zone: 3
    ```

!!! warning "Hash path secrets"

    The swift hash path prefix/suffix (stored in the `swift-hash-path-prefix` and `swift-hash-path-suffix` secrets)
    must never change once data has been written. Back these secrets up.

## Configuration and ring storage

All Swift configuration and rings live in Kubernetes secrets in the `openstack` namespace:

| Secret | Contents | Managed by |
|:--|:--|:--|
| `swift-etc` | `swift.conf`, `proxy-server.conf`, `account/container/object-server.conf`, `rsyncd.conf`, `container-sync-realms.conf` | helm (the chart's ConfigMap is converted to a Secret by `base-kustomize/swift/base`) |
| `swift-ring-config` | ring parameters and the device list rendered from `ring.*`, plus the ring job scripts | helm |
| `swift-rings` | `account.ring.gz`, `container.ring.gz`, `object.ring.gz` | `swift-ring-builder` job |
| `swift-ring-builders` | `account.builder`, `container.builder`, `object.builder` | `swift-ring-builder` job |

`swift-rings` and `swift-ring-builders` are not part of the helm release, so they survive an uninstall. The proxy and
every storage container mount the ring files from `swift-rings`; there is no shared PVC and no hostPath `/etc/swift`.

!!! danger "Back up the ring builders"

    The builder files are the source of truth for partition placement. Losing `swift-ring-builders` means the rings
    cannot be safely changed again. The ring job refuses to build new rings if `swift-rings` exists without
    `swift-ring-builders`. Back up both secrets after every ring change:

    ``` shell
    kubectl -n openstack get secret swift-rings swift-ring-builders -o yaml > swift-rings-backup-$(date +%F).yaml
    ```

Because the builders are kept in a secret (1 MiB limit), keep `ring.partition_power` at 15 or lower.

### How the ring builder job works

The `swift-ring-builder` job runs on a control plane node:

1. `fetch-builders` loads the existing builders from `swift-ring-builders`, if present.
2. `build-rings` creates the builders on first run, then makes the builders match `ring.devices`: it adds new devices
   and updates weights and replicas, then rebalances. `min_part_hours` is honored, so a single run moves at most one
   replica of any partition.
3. `publish-rings` writes `swift-rings` and `swift-ring-builders`. If the rings changed, it runs
   `kubectl rollout restart` on `deployment/swift-proxy` and `daemonset/swift-storage` so every pod loads the new rings.

Devices that are in the ring but no longer in `ring.devices` are not removed automatically; the job logs a warning.

### Updating or rebalancing the rings

1. Edit `ring.devices` (add devices or nodes, change weights) in your swift overrides.
2. Delete the completed job, then rerun the installer so helm recreates it with the new device list:

    ``` shell
    kubectl -n openstack delete job swift-ring-builder
    /opt/genestack/bin/install-swift.sh
    kubectl -n openstack logs job/swift-ring-builder -c build-rings
    kubectl -n openstack logs job/swift-ring-builder -c publish-rings
    ```

3. The proxy and storage pods are restarted automatically when the rings change. Watch the rollout and replication:

    ``` shell
    kubectl -n openstack rollout status daemonset/swift-storage
    kubectl -n openstack rollout status deployment/swift-proxy
    kubectl -n openstack exec ds/swift-storage -c swift-object -- swift-recon -r
    ```

4. To add capacity gradually, increase the weight in steps and repeat after each `min_part_hours` window. To
   rebalance without device changes (for example after `min_part_hours` has passed), just delete the job and rerun the
   installer.

To remove a device, set its `weight` to `0` and rerun until it holds no partitions. Then remove it from the builders
with `swift-ring-builder` (run in a pod with the builders from `swift-ring-builders`), update the secrets, and drop it
from `ring.devices`.

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

The base overrides enable `s3api`/`s3token` (S3 compatible API using Keystone EC2 credentials) and `keystonemiddleware`
authentication.

The ceilometer middleware is installed in the image and its `filter:ceilometer` section is configured, but it is not in
the pipeline by default. To enable Swift telemetry once Ceilometer is deployed, add `ceilometer` before `proxy-server`
in the pipeline and provide the notification transport in your swift overrides:

``` yaml
conf:
  proxy_server:
    "pipeline:main":
      pipeline: catch_errors gatekeeper healthcheck proxy-logging cache listing_formats container_sync bulk ratelimit s3api s3token authtoken keystoneauth copy container-quotas account-quotas slo dlo versioned_writes symlink proxy-logging ceilometer proxy-server
    "filter:ceilometer":
      url: rabbit://<user>:<password>@rabbitmq.openstack.svc.cluster.local:5672/ceilometer
```

## Validate functionality

``` shell
kubectl --namespace openstack exec -ti openstack-admin-client -- openstack container create genestack-test
kubectl --namespace openstack exec -ti openstack-admin-client -- openstack container list
```
