# Release 2026.2.0

This release note set is organized by component to make upgrade planning and validation easier.

[Product Matrix](product-matrix-2026.2.0.md)

## Components

- [Platform Foundations](#platform-foundations)
- [Observability and Telemetry](#observability-and-telemetry)
- [Kubernetes and Container Platform](#kubernetes-and-container-platform)
- [Networking and Load Balancing](#networking-and-load-balancing)
- [Compute and Scheduling](#compute-and-scheduling)
- [Identity and Secrets](#identity-and-secrets)
- [Storage, Images, and Data Protection](#storage-images-and-data-protection)
- [Orchestration](#orchestration)

## Additional Changes From Git History

These items were derived from commit history in the same tag range when no curated reno note was present.

- [Platform Foundations Git History](#platform-foundations-git-history)
- [Observability and Telemetry Git History](#observability-and-telemetry-git-history)
- [Kubernetes and Container Platform Git History](#kubernetes-and-container-platform-git-history)
- [Networking and Load Balancing Git History](#networking-and-load-balancing-git-history)
- [Compute and Scheduling Git History](#compute-and-scheduling-git-history)
- [Identity and Secrets Git History](#identity-and-secrets-git-history)
- [Storage, Images, and Data Protection Git History](#storage-images-and-data-protection-git-history)
- [Orchestration Git History](#orchestration-git-history)
- [Other Git History](#other-git-history)

## Platform Foundations

### Cert-Manager

#### New Features

- The cert-manager installation path is now chart-based and uses the upstream OCI-distributed cert-manager Helm chart source (`oci://quay.io/jetstack`) instead of the legacy repository-based chart reference (`https://charts.jetstack.io`). This aligns Genestack with the current cert-manager chart distribution model and keeps chart, CRD, and image updates on the Helm-managed installation path.

- Bootstrap now installs `cmctl` through the shared Genestack support functions so cert-manager API readiness checks can be run consistently from Genestack utility hosts. Cert-manager backup, reporting, solver inspection, and post-upgrade gate helper scripts have also been added under `scripts/cert-manager-support/`.

#### Preloads

- A new GitHub Actions composite action (`.github/actions/get-chart-version/`) has been added to resolve pinned chart versions from `helm-chart-versions.yaml`. All existing Helm CI workflows (barbican, blazar, cinder, designate, etc.) now use this action to pass the exact `--version` flag to `helm template`, ensuring CI templates stay in sync with deployment overrides.

#### Upgrade Notes

- The validated Genestack cert-manager upgrade path is a successive minor-version upgrade from `v1.15.3` to `v1.19.5` using staged maintenance hops: `v1.15.3` -> `v1.16.x` -> `v1.17.x` -> `v1.18.x` -> `v1.19.5`. Operators should follow one-minor-version hops and review the upstream upgrade notes for each target minor version before proceeding.

- Existing deployments should install `cmctl` before running the cert-manager maintenance and validation workflow. New bootstrap installs install `cmctl` automatically. Existing hosts can install it:

  ```shell
  cd /opt/genestack
  source scripts/lib/functions.sh
  ensureCmctl
  ```

- Operators should back up cert-manager custom resources and TLS secrets before upgrading and run the included post-upgrade gate after each staged hop or after the final upgrade.

- Review any local `Certificate` resources that rely on inherited private-key rotation behavior. In cert-manager `v1.18` and later, certificates without an explicit `spec.privateKey.rotationPolicy` inherit `Always`. CA certificates and other trust anchors should have an intentional policy set before upgrade so that key rotation is controlled rather than accidental.

#### Security Notes

- cert-manager has been updated to `v1.19.5`. This keeps Genestack on the intended `v1.19` minor branch while picking up the supported patch level, including the `v1.19.3` fix for `GHSA-gx3x-vq4p-mhhv` / `CVE-2026-25618` and later vulnerability-related patch updates. Base Genestack does not use DNS01 by default, but environments with custom DNS01 ACME solvers should treat this patch level as security-relevant.

#### Bug Fixes

- Set `rotationPolicy: Never` on the Genestack `public-endpoint-ca-cert` certificate so the CA private key is not automatically rotated during future certificate reissuance under the cert-manager `v1.18` and later default behavior.

### Memcached

#### Upgrade Notes

- Memcached now serves OpenStack clients through direct per-pod hostnames instead of a session-affinity Service. Each consuming chart's `endpoints.oslo_cache` block declares the StatefulSet, so the helm-toolkit endpoint macro renders `memcache_servers` as the full pod list (`memcached-0..N.<svc-fqdn>:11211`). Clients shard keys across all replicas and detect dead pods on their own, eliminating the single-VIP failure mode and the need for autoscaling on the cache tier.

#### Other Notes

- The cache backend was switched to `oslo_cache.memcache_pool` to take advantage of long-lived pooled connections and explicit dead-server handling, which pairs naturally with the per-pod server list.

### Redis

#### Upgrade Notes

- Gnocchi's incoming-measure store now defaults to Redis via the in-cluster `redis-sentinel` service instead of Ceph; aggregated time-series storage continues to use Ceph. The redis-sentinel cluster deployed by the redis-operator is therefore a prerequisite for the next `install-gnocchi.sh` run. Pending incoming bundles still queued in the Ceph incoming pool at the moment of the switchover are orphaned -- `gnocchi-metricd` only reads from Redis after the upgrade -- so roll the chart during a quiet window or after metricd has caught up. No aggregated time-series data is affected.

- The Gnocchi `low` archive policy's `back_window` was raised from 0 to 1 (one 5-minute granularity, ~5 minutes of permissible lateness) to absorb intra-batch timestamp reordering. Measures arriving microseconds behind a peer in the same metricd batch are no longer silently dropped at ingestion. `back_window` is monotonic and cannot be decreased on an existing policy.

#### Other Notes

- Together these changes let event-driven Swift telemetry -- notification-emitted `storage.objects.outgoing.bytes` and the new `storage.objects.http.class.{a,b,c}` request-class counters -- keep up with production-shape workloads without metricd backlog growth on the `gnocchi.metrics` Ceph pool.

## Platform Foundations Git History

### Cert-Manager

- Fix: OSPC-2163: pin helm chart versions in CI workflows

- Fix: Document update and bug fixes found during deploy (#1621)

### Proxy Environment Handling

- Release 2026.2 cherry picks (#1671)

- Chore: tune hpa to stateless services only (#1622)

- OSPC-1843 Get database instances building in lab (#1612)

### MariaDB Operator

- changing the dashboard json file to classic from v2 resource (#1655)

- Chore: Updating various grafana dashboards (#1638)

- Chore: remove aio (#1623)

- Chore: update maint plans for 2026.1.1 (#1582)

- Update infrastructure-mariadb-ops.md (#1587)

- Feature: add mariadb-backup-secrets to create-secrets.sh and update docs (#1573)

- Chore: disable innodb_snapshot_isolation (#1560)

- Chore: update mariadb replication settings for legacy openstack tables in 11.8.5 (#1540)

- Text only maint plan fixes (#1529)

- Feature: add mariadb-operator upgrade maint runbooks (#1527)

### Memcached

- Performance: increase memory limits (#1649)

- Fix: increase memcache pod memory limit (#1616)

- Chore: Updating otel config for multi memcached metrics (#1614)

- Fix: Align name with chart StatefulSet (#1593)

- Feature: enable sticky session timeout and memcache persistence (#1584)

### RabbitMQ

- Updated rabbitmq dashboard after otel deployment (#1653)

- Fix: Adjusting otel rabbitmq timeout to better handle many queues (#1645)

- Fix: Removing unused rabbit permissions to avoid event warnings (#1557)

- Feature: update rabbitmq/topology operator (#1535)

### Redis

- Fix: split operator and replication installs (#1654)

- Fix: move tooz coordination to redis (#1650)

## Observability and Telemetry

### OpenTelemetry Stack

#### Prelude

OpenTelemetry observability stack has been significantly enhanced and retuned.

#### New Features

- **etcd metrics**: A new `prometheus/etcd` scrape config has been added, scraping etcd metrics on port 2381 using the `etcd` node label and the `node-role.kubernetes.io/etcd` label for filtering.

- **Pod annotation scraping**: A new `prometheus/pod_annotations` scrape config has been added for Kubernetes pod-level metrics, replacing the disabled `podAnnotations` preset.

- **cadvisor and node-exporter**: New `prometheus/cadvisor` and `prometheus/node_exporter` scrape configs have been added with proper intervals (20s/15s for cadvisor, 40s/30s for node-exporter). The node-exporter textfile collector volume is now `readOnly: false`.

- **Envoy Gateway metrics**: New scrape configs for `envoy-gateway-proxy` (port 19001, `/stats/prometheus`) and `envoy-gateway` (metrics endpoint on envoyproxy-gateway-system namespace) have been added.

- **Log processing improvements**: The filelog operator has been refactored to use the `container` type parser for pod logs instead of manual CRI unwrapping. Multiline recombining now uses `send_quiet` error handling and is gated to only match known OpenStack/Horizon log patterns. The catch-all parser now handles `[\s\S]*` to preserve newlines.

#### Bug Fixes

- etcd scrape timeout increased from 30s to 60s to handle slower etcd metrics responses.

- RabbitMQ OTel scrape timeout increased to 30s with collection interval of 60s to handle workloads with many queues.

- RabbitMQ exporter scrape config now pulls only RabbitMQ endpoints (not all service endpoints).

- cadvisor/node-exporter and envoy-gateway OTel scrape configs updated for proper metric labeling.

- Log collection configuration fixed for missing and additional logs with improved regex parsing.

#### Other Notes

- Loki default log retention has been updated.

### Ceilometer

#### New Features

- Ceilometer now adds `trove` to the messaging notification URLs, enabling telemetry collection from the Trove database-as-a-service component.

- **Swift HTTP request-class metrics**: Account-level Swift HTTP request-class counters are now published with per-storage-policy suffixes. Ceilometer bins each successful `objectstore.http.request` into one of three tiers by HTTP method:
  - `storage.objects.http.class.a.policy:<type>:<name>` (put/post/copy)
  - `storage.objects.http.class.b.policy:<type>:<name>` (get)
  - `storage.objects.http.class.c.policy:<type>:<name>` (delete/head/options)

  Requests that cannot be attributed to a storage policy (account-level requests, container POST/DELETE, pre-controller failures) are counted against `.policy:none`.

- **Container-scoped Swift outgoing bytes**: A new `storage.containers.objects.outgoing.bytes` metric provides per-container visibility, distinct from the account-level `storage.objects.outgoing.bytes`.

- **ResellerAdmin role**: Ceilometer now assigns the `ResellerAdmin` role in addition to `admin` for the ceilometer service user under `endpoints.identity.auth`.

#### Other Notes

- The three class meters for Swift HTTP request-class counters use a whitelist regex for `policy_name` (currently only `Policy-0`). When operators add new Swift storage policies that should be billed separately, two edits are required: (1) add `.policy:<type>:<name>` entries under `swift_account` in `gnocchi_resources`, and (2) extend the `policy_name` whitelist regex in the three class meters.

### Observability Stack

#### New Features

- Libvirt exporter metric capability including Grafana dashboard

- Observability stack maintenance documentation

### Grafana Dashboards

#### Other Notes

- Several Grafana dashboards have been refreshed for the OpenTelemetry migration:
  - `mariadb_galera.json` — new Galera-specific dashboard replacing the old `mariadb_metrics.json` (Grafana 12.2.0 format)
  - `rabbitmq_metrics.json` — updated after OTel deployment
  - `memcached_metrics.json` — updated with OTel-based metrics
  - `project_lookup.json` — updated for OTel migration
  - `open_alerts.json` — updated for OTel migration
  - The old `galera_mariadb_overview.json` and `blackbox_exporter.json` dashboards have been removed (replaced by OTel-native collection)

### Longhorn

#### Other Notes

- A staged Longhorn upgrade maintenance runbook has been added covering the 1.8.0 -> 1.11.1 upgrade path with hops: 1.8.0 -> 1.9.1 -> 1.10.2 -> 1.11.1. The runbook documents required CRD stored-version migration steps.

## Observability and Telemetry Git History

### Observability Stack

- Fix: Updating otel scrape configs for cadvisor/node-exporter (#1658)

- Fix: Updating otel scrape configs for envoy-gateway (#1657)

- Fix: Adjusting otel default kube-pods scrape configs (#1643)

- Fix: Adjusting log collection config for missing and additional logs (#1642)

- Feature: OSPC-2093: Exposing etcd metrics and updating the monitoring stack to collect those metrics (#1586)

- Fix: Add statefulset to oslo_cache (#1595)

- Fix: Updating k8sattributes for improved log indexes (#1554)

- Chore: Updating docs for libvirt exporter metrics/info (#1548)

- Feature: Adding libvirt exporter metric capability including grafana dashboard (#1546)

- Chore: Adding observability stack maintenance doc and maintenance plan (#1523)

- Fix: Updating otel/postgres for proper postgres monitoring user creation (#1509)

- Fix: disable otel postgres by default (#1504)

- Fix otel installer (#1503)

### Ceilometer

- OSPC-1721 OpenStack Trove - Ceilometer integration (#1648)

- Feature: distinct container egress metric (#1627)

- Chore: remove newline at end of file (#1537)

- Fix: Use socket for libvirt connection (#1531)

- Chore: Add swift to messaging URLs (#1517)

- Feature: remove stale container creation from genestack (#1510)

### Gnocchi

- Fix: Set coordination URL with query params (#1597)

- Fix: Extend resource retention to 90d (#1579)

## Kubernetes and Container Platform

### Kubernetes

#### Prelude

Kubernetes has been upgraded from v1.33.5 to v1.35.4 and kubespray has been bumped to v2.31.0.

#### New Features

- `etcd_metrics_port: 2381` is now set by default in `ansible/inventory/genestack/group_vars/etcd.yml`, enabling etcd metrics to be exposed on a dedicated HTTP port (no TLS required). This is required for the monitoring stack to scrape etcd without mTLS certificates.

#### Upgrade Notes

- Kube-OVN OVN TLS certificates are now generated with proper DNS SANs (`ovn`, `ovn-nb`, `ovn-sb`, `ovn-northd`, and their `.kube-system.svc` variants) during installation via `bin/install-kube-ovn.sh`.

- The `kube_version` in `ansible/inventory/genestack/group_vars/k8s_cluster/k8s-cluster.yml` has been updated from `1.33.5` to `1.35.4`.

- Kube-OVN OVN TLS certificates are now generated with proper DNS SANs (`ovn`, `ovn-nb`, `ovn-sb`, `ovn-northd`, and their `.kube-system.svc` variants) during installation via `bin/install-kube-ovn.sh`.

- The `kube_version` in `ansible/inventory/genestack/group_vars/k8s_cluster/k8s-cluster.yml` has been updated from `1.33.5` to `1.35.4`.

### PostgreSQL

#### Prelude

PostgreSQL configuration has been significantly retuned for production workloads.

#### Upgrade Notes

- The PostgreSQL Cluster parameters have been updated with larger resource allocations and improved logging:
  - `shared_buffers` increased from `2GB` to `8GB`
  - `max_connections` increased from `1024` to `4096`
  - `log_statement` changed from `"all"` to `none`
  - Added `log_autovacuum_min_duration: "1000"`, `log_min_duration_statement: "500"`, `log_temp_files: "10240"`, `log_truncate_on_rotation: "on"`, `log_directory: ../pg_log`, `log_filename: postgresql-%u.log`, and other structured logging improvements

#### Other Notes

- A maintenance runbook for PostgreSQL operator helm adoption is available at `docs/postgres-operator-helm-adoption.md`.

### Host Setup

#### Other Notes

- The Helm and yq installation tasks have been removed from `ansible/playbooks/host-setup.yml` (the localhost block). Tool installation is now handled entirely by `scripts/lib/functions.sh` via the `ensureHelm` and `ensureYq` functions, with support for airgapped/internal artifactory environments via `GITHUB_MIRROR_URL`, `HELM_DOWNLOAD_BASE_URL`, `YQ_DOWNLOAD_URL`, and similar override variables.

### Freezer

#### Other Notes

- Freezer provides comprehensive backup and restore capabilities for OpenStack environments, supporting multiple backup types: QCOW2 image based VM backup, RAW image based VM backup, client local filesystem backup, client local LVM filesystem backup, MySQL DB backup, Mongo DB backup, and Cinder volume backup.

- The static vendor data inject job automatically appends the freezer cloud-init script to the Nova `static-vendor-data` ConfigMap, enabling automatic freezer agent installation on every new VM at first boot. Documentation is available at `docs/openstack-freezer-vendordata.md`.

### Memcached

#### Other Notes

- Memcached cache size (`conf.memcached.memory`) increased from 4096 to 6144. The pod memory limit has been correspondingly increased from 6144Mi to 8192Mi to maintain the 1.25-1.5x safety margin.

### Container Images

#### Upgrade Notes

- All OpenStack service container images have been updated from the `2024.1-latest` (Dalmatian) stream to the `2025.1-latest` (Epoxy) release stream. This is a major OpenStack release upgrade and affects:
  - Heat helper images: `heat:2024.1-latest` -> `heat:2025.1-latest`
  - Designate images: `designate:2024.1-latest` -> `designate:2025.1-latest`
  - CloudKitty images: `cloudkitty:2024.1-latest` -> `cloudkitty:2025.1-latest`
  - Horizon images: `horizon:2024.1-latest` -> `horizon:2025.1-latest`
  - Masakari images: `masakari:2024.1-latest` -> `masakari:2025.1-latest`
  - Manila images: `manila:2024.1-1763166117` -> `manila:2025.1-latest`
  - Octavia images (kustomize): `octavia:2024.1-latest` -> `octavia:2025.1-latest`
  - Ironic chart bumped from `2024.2.121+13651f45` to `2025.1.4+ed289c1cd`

- The Ceph helper image used by Cinder and Nova has been updated from `ceph-config-helper:ubuntu_jammy_19.2.2-1-20250414` to `ceph-config-helper:ubuntu_jammy_19.2.3-1-20250805`.

### Oslo Cache Cleanup

#### Deprecations

- `oslo_cache.memcache_pool` configuration has been removed from the Helm overrides for all OpenStack services that do not actively use memcache caching: barbican, blazar, designate, ironic, cinder, glance, manila, masakari, and octavia. This removes unused memcache pool connections and their associated overhead. Services that still rely on memcache (keystone, nova, neutron, swift) retain their cache configuration.

## Kubernetes and Container Platform Git History

### Magnum

- Docs: add CAPI-based Magnum guide and deprecate legacy cluster setup (#1572)

### Kube-OVN

- This corrects performance issues with kube-ovn (#1604)

### Kubernetes

- Fix: pin k8s to latest supported version in kubespray 2.31.0 (#1660)

- Feature: bump k8s to 1.35.6 and kubespray to v2.31.0 (#1659)

- OSPC-2145 Build and use labs when connected to AppGate

- Fixing Kubernetes upgrade plan (#1617)

## Networking and Load Balancing

### Neutron / OVN

#### Bug Fixes

- **World-writable stevedore cache files**: Fixed by adding a `patch-fix-world-writable-files.yaml` kustomize patch that sets `umask 0022` before starting the `neutron-ovn-metadata-agent` and `neutron-ovn-vpn-agent` containers. This prevents the creation of world-writable stevedore cache files that could be exploited by other processes.

- **br-overlay revert**: Reverted a breaking change that had switched the default OVN bridge interface. The default remains `br-overlay` for existing deployments.

### Octavia

#### Upgrade Notes

- Octavia container image updated from `2024.1-latest` to `2025.1-latest` in the base kustomize overlays.

### Designate

#### Known Issues

- The designate service cleaner is not functional and uses a temporary master branch container image (`kernelpanic53/rackerlabs-designate:2026-master`) as a fix.

## Networking and Load Balancing Git History

### Designate

- Chore: Remove superflous .conf.cache overrides for services without that memcache support (#1636)

### Neutron / OVN

- Chore: Update deprecated kubectl flag in doc (#1646)

- Fix: OSPC-2153: prevent world-writable stevedore cache files in ovn agents (#1644)

- Feature: add Ironic OVN annotation examples for provisioning network and config update (#1581)

- Chore: fix install-neutron.sh to use charts secret-keystone template (#1549)

- Chore: enable neutron keystone_secret manifest (#1556)

### MetalLB

- doc(metallb): Update MetalLB maintenance plan with detailed commands (#1577)

### Envoy Gateway

- fix hyperconverged lab Gateway listener setup (#1602)

- Feature: support airgap and internal artifactory sources (#1562)

## Compute and Scheduling

### Envoy Gateway Multi-Gateway

#### New Features

- **Config mode support**: A new `--config` / `--gateway-config` option has been added to `bin/install-envoy-gateway.sh` and `bin/setup-envoy-gateway.sh`. Config mode deploys Envoy using a YAML configuration file that defines multiple gateways (external + internal), each with separate GatewayClasses, MetalLB pools, listeners, certificates, and HTTPRoutes.

- **Multi-gateway support**: Config mode enables separate internal and external Envoy Gateway deployments. The internal gateway provides cluster-internal access (for services like Grafana, Prometheus, Loki) while the external gateway handles public-facing traffic.

- **ACME integration**: Config mode supports Let's Encrypt HTTP01 for external routes via the `HYPERCONVERGED_ENVOY_GATEWAY_ACME=true` environment variable.

- **Node affinity**: The config-mode EnvoyProxy configures Envoy data-plane pods with `node-role.kubernetes.io/worker` node affinity, with HPA min 2 / max 9 and resource-based autoscaling (60% CPU, 500Mi memory).

- **Config-mode namespace**: A dedicated `envoy-gateway` namespace manifest with privileged PodSecurity standards has been added.

- **Config-mode issuer**: A `flex-gateway-issuer` ClusterIssuer and `public-endpoint-ca-cert` Certificate with `rotationPolicy: Never` have been added for config-mode deployments.

#### Bug Fixes

- The `setup-envoy-gateway.sh` script has been rewritten with `set -euo pipefail` for better error handling. The script now supports a `--config` mode for multi-gateway deployments alongside the legacy single-gateway mode.

- The `install-envoy-gateway.sh` script now supports `--config` and `--gateway-config` arguments and accepts pass-through Helm arguments.

#### Other Notes

- The `setup-infrastructure.sh` script now checks for `ENVOY_GATEWAY_CONFIG_FILE` and uses config mode if set, otherwise falls back to the legacy single-gateway deployment.

- Hyperconverged lab scripts (`scripts/hyperconverged-lab.sh`, `scripts/lib/hyperconverged-common.sh`) support `--envoy-gateway-config`, `--envoy-gateway-acme`, `--internal-metallb-ip`, and related environment variables for multi-gateway lab deployments.

- Documentation for multi-gateway Envoy deployments is available at `docs/infrastructure-envoy-gateway-multi-gateway.md`.

- A `cleanup-envoy-httproutes.sh` script and `generate-envoy-gateway-config.sh` helper have been added for cutover management from legacy single-gateway to multi-gateway config mode.

### Redis Operator

#### Bug Fixes

- The Redis Operator installation has been split into separate operator and replication installs. The `install-redis-operator.sh` script now only installs the operator; replication cluster installation is handled by the new `install-redis-replication.sh` script.

#### Other Notes

- The Redis Operator Helm overrides file has been created at `base-helm-configs/redis-operator/redis-operator-helm-overrides.yaml`.

- The base kustomize directory has been renamed from `redis-operator-replication` to `redis-operator`.

### Nova

#### New Features

- **Nova VM reset action**: Member/reader rules have been added to allow project users to reset their own VM instances (`os_compute_api:os-admin-actions:reset_state` policy set to `rule:project_member_or_admin`).

- **Archive deleted rows cron job**: Nova now includes a `cron_job_archive_deleted_rows` manifest enabled by default, with configurable `max_rows` (set to 1000), `before` (30 days ago), `all_cells: true`, and `purge_deleted_rows: true` settings.

- **use_rootwrap_daemon**: Enabled by default (`use_rootwrap_daemon = true`) in the base Nova Helm overrides under `conf.nova.DEFAULT`.

#### Bug Fixes

- Fixed the Nova virt driver ConfigDrive issue (bug-2148059) in the patched image for the Epoxy release.

### Skyline

#### Bug Fixes

- The Skyline HPA resource name has been corrected from `skyline-api-server` to `skyline`, matching the deployment name. Previously the HPA referenced a non-existent deployment name, causing the autoscaler to be non-functional.

### Tempest

#### Other Notes

- A new Tempest Helm chart and overrides file have been added at `base-helm-configs/tempest/tempest-helm-overrides.yaml`. The `bin/install-tempest.sh` script has been added for Tempest deployment. Tempest is configured with a test blacklist and runs smoke tests with 4 workers.

## Compute and Scheduling Git History

### Blazar

- Add member/reader rule to get blazar oshosts (#1610)

### Libvirt

- Update modprobe.d path in kustomization.yaml

### Nova

- Add member permissions for nova VM reset action (#1662)

- Chore: Configure novaDB removing deleted rows (#1600)

## Identity and Secrets

### Keystone

#### New Features

- **Shibboleth federation automation**: `bin/install-keystone.sh` now auto-manages the `keystone-shibd-etc` secret when Shibboleth federation is enabled. The installer renders the chart to detect the federation overlay, then idempotently syncs the secret from `${KEYSTONE_SHIBBOLETH_DIR}` (default `/etc/genestack/keystone-sp/shibboleth/`). Operators no longer need to run manual `kubectl create secret` commands.

- **Fernet credential permission fix**: A new kustomize patch (`base-kustomize/keystone/base/fix-fernet-credential-permissions.yaml`) has been added to fix Keystone fernet credential key ownership. The patch adds init and sidecar containers that copy keys from the secret-mounted read-only volumes into emptyDir volumes with proper `42424:42424` ownership and `400` permissions, preventing Keystone from seeing `root:root 0400` files that cause authentication failures.

#### Upgrade Notes

- After upgrading, re-run `install-keystone.sh` to pick up the automated Shibboleth secret sync. If federation is in use, simply editing files under `/etc/genestack/keystone-sp/shibboleth/` and re-running the installer will update the secret.

- The required Shibboleth files are: `shibboleth2.xml`, `sp-cert.pem`, `sp-key.pem`, `idp-metadata.xml`. The installer will abort with a clear error if any are missing.

- The behavior can be bypassed by setting `SKIP_SHIBBOLETH_SECRET=1` or by passing `--dry-run` through to helm. Point the installer at a non-default shibboleth source directory via `KEYSTONE_SHIBBOLETH_DIR`.

#### Bug Fixes

- Fixed fernet key ownership race during sync by ensuring proper file permissions (`400` for keys, `700` for directories, owned by `42424:42424`) via init containers. The `monitoring-common.sh` script also now skips postgres-monitoring secret setup when the `postgres-system` namespace does not exist.

#### Security Notes

- The fernet credential permission fix prevents a race condition where keystone could read `root:root 0400` files from the kubelet secret volume mount, causing authentication failures.

## Identity and Secrets Git History

### Keystone

- Fix: stop keystone fernet warnings on secret mounts (#1628)

- Fix: Configure shibboleth memcache hosts (#1620)

### Barbican

- Chore: Remove superflous .conf.cache overrides (#1635)

## Storage, Images, and Data Protection

### Gnocchi

#### Upgrade Notes

- Gnocchi's incoming-measure store now defaults to Redis via the in-cluster `redis-sentinel` service instead of Ceph. The `redis-sentinel` cluster deployed by the redis-operator is therefore a prerequisite for the next `install-gnocchi.sh` run. Pending incoming bundles still queued in the Ceph incoming pool at the moment of the switchover are orphaned. No aggregated time-series data is affected.

- The Gnocchi `low` archive policy's `back_window` was raised from 0 to 1 (one 5-minute granularity, ~5 minutes of permissible lateness) to absorb intra-batch timestamp reordering.

- Gnocchi API `max_limit` set to 10000, `operation_timeout` set to 20, and `metricd.workers` increased from 2 to 4 with `processing_replicas: 4`.

#### Other Notes

- Together with the Swift HTTP request-class metrics, these changes let event-driven Swift telemetry keep up with production-shape workloads without metricd backlog growth on the `gnocchi.metrics` Ceph pool.

### Freezer

#### Bug Fixes

- Fixed the freezer scheduler installation: the static vendor data inject job for freezer agent/scheduler deployment into VMs has been added. This job runs after Freezer deployment and automatically appends the freezer cloud-init script to the Nova vendor_data ConfigMap, enabling automatic freezer agent installation on all new VMs.

### Cinder

#### Known Issues

- No explicit unresolved known issues were identified. However, the OpenStack Epoxy (2025.1) release for Cinder introduces stricter validation that may surface failures that were previously ignored. Operators should validate upload/import behavior with real image sets due to stricter format checks introduced upstream.

## Storage, Images, and Data Protection Git History

### Freezer

- OSPC-2214:Added changes to deploy freezer agent/scheduler into VM (#1652)

- Fix: resolve merge conflict markers in openstack-freezer.md (#1500)

### Cinder

- Fix: Disable send_actions in volume usage audit job (#1588)

- Fix Epoxy Cinder installs on Talos (#1583)

- Fix!: cinder-volume playbook/role virtualenv upper-contraints (#1574)

### Trove

- OSPC-1756 MySQL 8.4 - Debian Image (#1640)

### Manila

- feat: add manila_enablement_techpreview ansible role (#1515)

## Orchestration

### Heat

#### Bug Fixes

- Fixed outdated Heat, Masakari, and Manila container images that were still referencing the 2024.1 image stream. All helper images now use `2025.1-latest`.

### Skyline

#### Bug Fixes

- Fixed the Skyline deployment name mismatch: HPA and deployment now both reference `skyline` instead of the previously mismatched `skyline-api-server`.

## Orchestration Git History

### Skyline

- Chore: add node selectors (#1541)

- Chore: create new maintenance plan for skyline upgrade (#1532)

## Tech Preview Components

### Trove (Database as a Service)

#### Prelude

Trove has been added as a tech preview component for OpenStack Database as a Service.

#### New Features

- **Management network**: Trove configures a dedicated management overlay network (geneve) for guest VM connectivity to RabbitMQ and Keystone, separate from tenant networks.

- **Management bridge DaemonSet**: A per-chassis `trove-mgmt-bridge` DaemonSet runs haproxy to proxy RabbitMQ (5672) and Keystone (5000) traffic to guest VMs on the management overlay network, using the Octavia health-manager pattern for OVN port plumbing.

- **Debian guest image elements**: Custom DIB elements (`debian-guest`, `debian-docker`) have been added for building Trove guest images based on Debian, including Docker CE installation and NTP configuration.

- **Ansible enablement role**: The `trove_enablement_techpreview` Ansible role handles the full lifecycle: K8s secrets, service image build, gateway/kustomize, Helm config, and datastore setup.

#### Upgrade Notes

- Trove installation is now deferred to the end of the lab build process. The `install-trove.sh` is no longer called during `setup-openstack.sh`; instead, it runs after network and management components are configured via `deployTrove()` in the hyperconverged lab scripts.

- The management network ID, security group ID, and keypair name must be resolved at deploy time and injected into the Trove Helm overrides via placeholders (`<management_networks>`, `<management_security_groups>`, `<keypair_name>`).

#### Other Notes

- Trove Ceilometer integration has been added (Trove's RabbitMQ notifications are now monitored by Ceilometer).

- Documentation for Trove is available at `docs/openstack-trove.md`.

### Manila (Shared File Systems)

#### Prelude

Manila has been added as a tech preview component with a complete Ansible enablement role for end-to-end deployment.

#### New Features

- **End-to-end enablement**: The `manila_enablement_techpreview` Ansible role handles secret management, service image building, gateway configuration, Helm config, and share type setup.

- **Ubuntu 24.04 service image**: Manila service images are built using `manila-image-elements` on Ubuntu 24.04 (noble), with `qemu-guest-agent` pre-installed for guest VM management.

- **Test tenant scripts**: Helper scripts (`manage-test-tenants.sh`, `manage-test-tenant-shares.sh`, `manila-full-teardown-and-test-tenants.sh`) have been added for end-to-end Manila testing including NFS share creation, VM boot, and mount verification.

#### Other Notes

- Documentation for Manila is available at `docs/openstack-manila.md`.

### Freezer

#### Other Notes

- Freezer provides comprehensive backup and restore capabilities for OpenStack environments, supporting multiple backup types: QCOW2 image based VM backup, RAW image based VM backup, client local filesystem backup, client local LVM filesystem backup, MySQL DB backup, Mongo DB backup, and Cinder volume backup.

- The static vendor data inject job automatically appends the freezer cloud-init script to the Nova `static-vendor-data` ConfigMap, enabling automatic freezer agent installation on every new VM at first boot. Documentation is available at `docs/openstack-freezer-vendordata.md`.

## Magnum

#### Other Notes

- Documentation has been added for CAPI-based Magnum cluster setup, including kubeconfig injection for CAPI-enabled Magnum deployments. See `docs/openstack-magnum.md` for the full workflow.

## Maintenance Runbooks

#### Other Notes

- Cert-manager upgrade maintenance runbook added: `maintenances/maintenance-cert-manager-1.15.3-to-1.19.5.md` — covers the v1.15.3 to v1.19.5 upgrade path with staged hops, Helm adoption, CA rotation policy changes, and post-upgrade validation.

- Longhorn upgrade maintenance runbooks updated with detailed commands and validation steps for the 1.8.0 -> 1.11.1 upgrade path.

- Kubernetes kubespray upgrade plan has been updated for the v2.31.0 / k8s v1.35.4 bump.

## Tooling and CI

### GitHub Actions

#### New Features

- **Pinned Helm chart versions in CI**: All Helm CI workflows now use the `get-chart-version` composite action to extract pinned chart versions from `helm-chart-versions.yaml`, ensuring CI templates use the same chart versions as deployments. This affects all 30+ Helm chart CI workflows.

- A new `.github/actions/get-chart-version/action.yaml` composite action has been created. It installs `yq` and extracts the chart version from `helm-chart-versions.yaml` as a reusable action.

#### Other Notes

- The `helm-chart-versions.yaml` file has been updated:
  - `cert-manager`: `v1.19.2` -> `v1.19.5`
  - `ironic`: `2024.2.121+13651f45-628a320c` -> `2025.1.4+ed289c1cd`
  - `topolvm`: added at version `16.1.1`

### Ansible and Python Dependencies

#### Upgrade Notes

- `requirements.txt` has been updated:
  - `ansible`: `10.7.0` -> `11.13.0`
  - `cryptography`: `43.0.1` -> `46.0.7`
  - `jmespath`: `1.0.1` -> `1.1.0`
  - `netaddr`: `0.9.0` -> `1.3.0`

### Bootstrap

#### Upgrade Notes

- `bootstrap.sh` now calls `ensureCmctl` in addition to `ensureYq` and `ensureHelm` to install cert-manager's CLI tool during bootstrap.

### Python Version

#### Other Notes

- Support for air-gapped and internal artifactory environments has been added. Override variables for tool downloads include:
  - `GITHUB_MIRROR_URL` — overrides GitHub download URLs for yq, cmctl
  - `YQ_DOWNLOAD_BASE_URL` / `YQ_DOWNLOAD_URL` — overrides yq download location
  - `HELM_DOWNLOAD_BASE_URL` / `HELM_DOWNLOAD_URL` — overrides helm download location
  - `CMCTL_VERSION` / `CMCTL_DOWNLOAD_BASE_URL` / `CMCTL_DOWNLOAD_URL` — overrides cmctl version and download location

## Deprecations

- The AIO (all-in-one) deployment mode has been removed. Use the hyperconverged lab scripts instead.

- The legacy `host-setup.yml` Helm and yq installation tasks have been removed in favor of the shared `scripts/lib/functions.sh` install functions.

- The `redis-operator-replication` kustomize directory has been renamed to `redis-operator`.

- The `metallb.universe.tf` annotation prefix from 2026.1 remains accepted in MetalLB `0.15.2` for backward compatibility, but operators should migrate to the `metallb.io` prefix.

## Known Issues

- The Designate service cleaner uses a temporary master branch container image (`kernelpanic53/rackerlabs-designate:2026-master`) as a fix for the non-functional service cleaner.

- Large image handling in Ironic may still experience resource pressure (CPU/memory) during download and checksum operations in constrained environments. Validation in staging is recommended.

- Stricter validation in Ironic may surface failures that were previously ignored in networking, inspection, and deployment workflows.

- The `manifests.podmonitor` option for libvirt exporter metrics only has effect in environments with the Prometheus Operator CRDs installed, and useful metrics require the `libvirt_exporter` sidecar to be enabled.

- Trove and Manila are tech preview components — use in pre-production environments only.

## Critical Issues

- cert-manager `GHSA-gx3x-vq4p-mhhv` / `CVE-2026-25618` has been addressed by upgrading to v1.19.5.

- The cert-manager CA certificate (`public-endpoint-ca-cert`) has had `rotationPolicy: Never` explicitly set (in both base kustomize and the release notes) to prevent unintended CA key rotation under the v1.18+ default behavior change.

- The Neutron OVN world-writable file fix prevents potential privilege escalation through stevedore cache files in OVN agent containers.

- The Skyline HPA/deployment name mismatch (where HPA targeted `skyline-api-server` but the deployment was `skyline`) has been corrected — existing deployments should verify their HPA is functioning.

## Upgrade Notes Summary

1. Upgrade Kubernetes from v1.33.5 to v1.35.4 with kubespray v2.31.0
2. Upgrade cert-manager from v1.15.3 to v1.19.5 via staged hops (see maintenance runbook)
3. Upgrade all OpenStack service images from 2024.1 to 2025.1 (Epoxy)
4. Upgrade Ironic chart from 2024.2 to 2025.1
5. Split Redis installation: operator and replication are now separate installs/scripts
6. Memcached memory limits increased (cache: 4096->6144, pod: 6144Mi->8192Mi)
7. Gnocchi incoming-measure store switched from Ceph to Redis (requires redis-sentinel)
8. Re-run `install-keystone.sh` to pick up automated Shibboleth federation secret sync
9. Remove the legacy Helm/yq installation block from `host-setup.yml` if using custom playbooks
10. Plan for a destructive observability stack teardown if upgrading from a pre-2026.1 deployment
11. Update `requirements.txt` dependencies (Ansible 10.7->11.13, cryptography 43->46)
12. Add `topolvm: 16.1.1` to `helm-chart-versions.yaml` if not present
