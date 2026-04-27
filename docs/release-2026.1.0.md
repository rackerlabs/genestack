# Release 2026.1.0

This release note set is organized by component to make upgrade planning and validation easier.

[Product Matrix](product-matrix-2026.1.0.md)

## Components

- [Platform Foundations](#platform-foundations)
- [Observability and Telemetry](#observability-and-telemetry)
- [Kubernetes and Container Platform](#kubernetes-and-container-platform)
- [Networking and Load Balancing](#networking-and-load-balancing)
- [Compute and Scheduling](#compute-and-scheduling)
- [Identity and Secrets](#identity-and-secrets)
- [Storage, Images, and Data Protection](#storage-images-and-data-protection)
- [Orchestration](#orchestration)

## Platform Foundations

### Cert-Manager

#### New Features

- Allow other kubernetes deployment models including Talos k8s stack to include a managed cert-manager helm chart. Decouple the cert-manager installation from the base kubespray ansible roles and allow the official upstream charts to provide chart and CRD updates including patched image rollouts. This includes envoy gateway-api support and custom DNS server forwarders.

### Proxy Environment Handling

#### Bug Fixes

- A new override `force_proxy_setting` is introduced to control when proxy environment variables are added into the shell and systemd environment. In some circumstances, adding system-wide HTTP proxy environment variables can cause issues with dbus, rendering systemd inoperable and stopping all systemd operations including reboot. This can happen if the proxy server does not allow reverse connections or blocks requests to localhost when `NO_PROXY` is improperly configured.

### MariaDB Operator

#### Prelude

MariaDB Operator Helm charts have been upgraded from 0.38.1 to 26.3.0 following the recommended progressive upgrade path via 25.8.4 and 25.10.4.

Upgrade path:
    0.38.1 → 25.8.4 → 25.10.4 → 26.3.0

The version 25.8.4 and 25.10.4 is the latest patch release in the 25.8.x and 25.10.x series and includes all prior fixes along with additional stability improvements.

This upgrade introduces improvements to replication failover behaviour, backup and restore capabilities, operator stability, and compatibility with newer Kubernetes versions.

The 25.x release line establishes PhysicalBackup and improved replication handling, while 26.3.0 extends this with Point-in-Time Recovery (PITR), enhanced backup integrations, and Helm chart structural changes.

These improvements apply to both Galera and replication clusters.

#### New Features

- Physical backups introduced in the 25.8 release series via the PhysicalBackup CR.

  Supported mechanisms:
  * MariaDB-native backups using mariadb-backup
  * Kubernetes VolumeSnapshots for storage-level backup and restore

  Benefits:
  * Faster backup and restore operations
  * Reduced recovery time objectives (RTO)
  * Support for cluster bootstrapping via spec.bootstrapFrom

- Replication cluster improvements across the 25.x series:
  * More stable and predictable failover handling
  * Improved replica lifecycle management
  * Enhanced reconciliation reducing drift and recovery time

- Backup and restore improvements in the 25.10 series:
  * Improved backup job generation and scheduling
  * More reliable restore workflows
  * Enhanced object storage compatibility (e.g. S3, SSE-C)

  Replication clusters can now configure backup targets to run on replicas
instead of the primary using:
  target: Replica
  target: PreferReplica

- New capabilities introduced in 26.3.0:

  * Point-in-Time Recovery (PITR) support
    - Enables restoring databases to a specific timestamp
    - Improves recovery precision beyond full backup restores

  * PhysicalBackup enhancements:
    - Azure Blob Storage support
    - On-demand PhysicalBackup execution

  These features significantly improve disaster recovery flexibility and
  multi-cloud support.

- Introduced the new `mariadb-cluster` Helm chart for managing MariaDB clusters and related resources in a single Helm release. This provides an alternative deployment method to Kustomize-based installations.

#### Known Issues

- Replication auto-failover depends on Kubernetes detecting primary pod failure. In node shutdown or network partition scenarios, failover timing is influenced by Kubernetes node health detection and eviction behaviour.

- VolumeSnapshot-based backups depend on CSI driver capabilities and may vary across environments in terms of consistency guarantees.

- In 26.3.0, restore behaviour using bootstrapFrom.targetRecoveryTime has changed: the operator now selects the closest backup **not after** the requested timestamp.

  This may result in different restore points compared to previous versions and should be validated in recovery procedures.

#### Upgrade Notes

- Upgrade path followed:

  0.38.1 → 25.8.4 → 25.10.4 → 26.3.0

  Sequential upgrades are required due to CRD evolution and changes in replication and backup behaviour across versions

- Replication configuration change (25.x):

  syncBinlog changed from boolean to integer

  Old:
    syncBinlog: true

  New:
    syncBinlog: 1

  This change is handled by updated CRDs and typically requires no manual action unless explicitly overridden in custom configurations

- Helm values change (26.3.0):

  Image configuration fields have transitioned from single string values
  to structured repository + tag format

  Old:
    config:
      mariadbImageName: repo/image

  New:
    config:
      mariadbImage:
        repository: repo/image
        tag: <version>

  Custom Helm values must be updated accordingly prior to upgrade.

- CI workflow change (helm-mariadb-operator.yaml):

  The Helm chart version is now pinned using the x-chart-version field
  defined in the overrides file rather than always pulling the latest
  chart from the Helm repository.

  A new x-chart-version field has been added to the top of
  base-helm-configs/mariadb-operator/mariadb-operator-helm-overrides.yaml:

  x-chart-version: "26.3.0"

  The GitHub Actions workflow extracts this value at runtime and passes
  it as --version to helm template. This ensures the CI pipeline uses
  a chart version compatible with the overrides file structure.

  To update the chart version, modify the x-chart-version field in the
  overrides file. Both CI and deployment will stay in sync.

- Pre-upgrade recommendations:
  * Validate existing backups and restore procedures
  * Review Helm values for image configuration compatibility
  * Ensure CSI drivers support VolumeSnapshots (if used)
  * Confirm Kubernetes version compatibility

- Post-upgrade validation:
  * Verify cluster health and replication status
  * Validate backup job execution
  * Perform test restore (including PITR where applicable)
  * Review operator logs for reconciliation errors

#### Deprecations

- Boolean-based replication configuration parameters have been removed. Integer values are now required.

- Legacy MaxScale components bundled within the operator have been removed. MaxScale should be deployed and managed independently if required.

#### Critical Issues

- Helm values format changes in 26.3.0 may cause upgrade failures or incorrect image configuration if not updated prior to deployment.

- Restore behaviour change for targetRecoveryTime may impact recovery outcomes. Validation of restore workflows is strongly recommended.

- Backup configuration errors, particularly with PhysicalBackup, may impact recovery capabilities if not verified post-upgrade.

#### Bug Fixes

- Fixes introduced between 25.8.1 and 25.8.4 include:
  * Galera failover improvements
  * PhysicalBackup VolumeSnapshot consistency improvements
  * Reduced Grant reconciliation time
  * VolumeSnapshot locking optimizations
  * Restore volume mutability improvements
  * PhysicalBackup storage mount subPath fix
  * Grant finalizer fixes for users with custom names
  * appProtocol added to MariaDB service ports
  * panic fix in GetAutomaticFailoverDelay
  * support updates for Go 1.25 and Kubernetes 1.34

- Improvements in the 25.10 series include:
  * Improved replication failover and replica recovery handling
  * Improved backup job generation and restore workflows
  * Improved S3 backup handling and support for SSE-C encryption
  * Improved Helm chart argument handling
  * Removal of legacy MaxScale components from the operator
  * Kubernetes 1.35 support

- Improvements in 26.3.0 include:
  * Introduction of Point-in-Time Recovery (PITR)
  * Enhanced PhysicalBackup capabilities and storage integrations
  * Improved recovery logic for deterministic restore behaviour
  * General operator stability and reconciliation improvements
  * Continued dependency and Kubernetes compatibility updates

### Memcached

#### Prelude

Genestack will use openstack helm chart (https://github.com/openstack/openstack-helm/tree/master/memcached) instead of bitnami helm chart (https://github.com/bitnami/charts/tree/main/bitnami/memcached) for memcached from this release onwards. Currently genestack uses memcached version 1.6.39 in bitnami helm chart. However openstack-helm chart provides 1.6.32 version for memcached. So it will be a minor version downgrade from 1.6.39 to 1.6.32. However it will not impact anything on Openstack as openstack doesn't define any specific version of memcached to use in its documentation. Verified release notes in both 1.6.32 (https://github.com/memcached/memcached/wiki/ReleaseNotes1632) and 1.6.39 (https://github.com/memcached/memcached/wiki/ReleaseNotes1639) version, there are changes related to proxy and tls which is not used by the memcached used by openstack.

#### New Features

- The env vars MEMCACHED_THREADS and MEMCACHED_MAX_ITEM_SIZE were used in bitnami chart and openstack-helm chart don't provide that. So, kustomize post renderer will be used to add those extra variables and include them during installation.

#### Upgrade Notes

- Service name of memcached is same "[internal host redacted]" as previuos bitnami chart in openstack-helm memcached chart as it is used by all openstack services. Hence, need to remove existing memcached installed by bitnami in genestack before installing new memcached. Then install memcached of openstack-helm using the usual installation script.

#### Deprecations

- Bitnami chart had persistence enabled for memcached. However openstack-helm chart for memcached don't have persistence enabled.

#### Other Notes

- Genestack no longer relies on bitami for memcached and will use openstack-helm memcached instead.

### RabbitMQ

#### Prelude

Genestack aligns RabbitMQ for the 2026.1 Epoxy release by pinning the managed RabbitMQ image explicitly to the 4.1 series for predictable upgrades.

#### New Features

- The base RabbitmqCluster manifest now pins `spec.image` to `rabbitmq:4.1.4-management` so upgraded and fresh environments converge on the same RabbitMQ server version.

#### Upgrade Notes

- OpenStack Epoxy supports RabbitMQ 4.0 and 4.1, and Kolla-Ansible recommends RabbitMQ 4.1 before or during Epoxy upgrades. Genestack now targets RabbitMQ 4.1.4 for this release.

- Upgrading the RabbitMQ Cluster Operator can trigger a rolling update of the managed RabbitMQ StatefulSet. If rollout timing must be controlled, pause reconciliation on the `RabbitmqCluster`, upgrade the operators, re-apply the cluster manifest, and then resume reconciliation.

#### Deprecations

- Genestack no longer relies on the operator default RabbitMQ image for the Epoxy release path. The RabbitMQ server image is now pinned explicitly to avoid unintended version drift and preserve idempotent upgrades.

#### Other Notes

- Validation in lab confirmed the RabbitMQ cluster upgraded successfully to 4.1.4 and passed basic health checks including cluster status, local alarm checks, StatefulSet readiness, PVC binding, and operator log review.

### Redis

#### Prelude

Redis Operator v0.24.0 adds IPv6 support for Redis Cluster client behavior, expands Helm chart configurability, improves metrics exposure, and hardens scaling, persistence, webhook, and cert-manager related workflows.

#### New Features

- Added support for exposing Redis standalone using the service type defined in `kubernetesConfig`.

- Added IPv6 support for Redis Cluster client commands and mocks.

- Added support for customizable annotations across Redis standalone, RedisCluster, Sentinel, and RedisReplication chart resources.

- Added Redis Exporter metrics service support for cluster, replication, sentinel, and standalone deployments.

- Added Sentinel support to the `redis-replication` chart.

- Updated Redis Helm charts to support additional already-implemented properties.

#### Upgrade Notes

- The mutating webhook configuration name now includes the Helm release name prefix. This is a breaking change for environments that depend on the old webhook naming convention.

- Cert-manager based deployments should verify certificate material naming, because the operator now expects `ca.crt` instead of `ca.key` for the affected startup path.

#### Bug Fixes

- Fixed creation of empty PVCs when storage configuration contains only `volumeMount` entries.

- Fixed chart logic for `redisConfig` when using `externalConfig` and `maxMemoryPercentOfLimit`.

- Fixed missing additional annotations on the replication headless service.

- Fixed default leader and follower replica counts so they align with `clusterSize`.

- Fixed ClusterRole aggregation into the admin role.

- Fixed cert-manager startup failures by using `ca.crt` instead of `ca.key`.

- Fixed PVC resize handling to skip shrink attempts.

- Fixed initContainer behavior to respect `persistenceEnabled`.

- Fixed a race condition involving the global `serviceType` variable.

- Fixed RBAC namespace resource configuration.

- Fixed RedisCluster scaling behavior to be resilient during failover and while slots are open.

- Fixed ACL SAVE behavior when ACL data is loaded from PVC.

- Fixed scale-out behavior by waiting for node convergence and blocking rebalance or add-node actions while cluster slots remain open.

- Fixed webhook certificate secret lookup failures.

- Fixed a typo in dashboard datasource configuration.

- Fixed `REDIS_MAX_MEMORY` handling when `maxMemoryPercentOfLimit` is enabled.

#### Other Notes

- Updated documentation examples for `redisSecret` indentation and `nodeConfVolume` usage.

- Refreshed architecture documentation and fixed minor documentation typos.

- Updated several CI and linting dependencies, including `actions/stale`, `actions/setup-python`, and `hadolint/hadolint-action`.

### Container Images

#### Upgrade Notes

- Updated `scripts/genestack.rc` to default `CONTAINER_DISTRO_VERSION` to `noble` for Ubuntu 24.04 while keeping `OPENSTACK_RELEASE` at `2026.1`. This changes the sourced bootstrap environment from `ubuntu:jammy` to `ubuntu:noble`.

- `bootstrap.sh` does not change behavior as part of this update beyond reporting the new distro value in its status output.

### Maintenance Runbooks

#### Other Notes

- Added operational maintenance runbooks under `maintenances/` for Kubernetes, Kubespray, and staged Longhorn upgrades, along with a reusable component maintenance template. These runbooks are kept outside the published docs tree and use a plain-text, copy-paste-safe format intended for operator use.

## Observability and Telemetry

### Observability Stack

#### Prelude

Genestack now utilizes Opentelemetry as a metrics, logging and tracing ecosystem. These changes touches the entirety of the monitoring and observability stack. The goal was to consolidate the related monitoring and observability tooling in to a more manageable and clean directory and namespacing structure. This means that services/applications like Loki, Grafana, Prometheus(and its related tooling) have all been placed within the monitoring directory structure as well as migrated from various namespaces to a single 'monitoring' namespace. That means that these changes won't directly work against current deployments. In order to properly structure things, a destructive tear down of the components is required. Loki, Prometheus(and any exporters), Grafana(and its database) needs to be completely uninstalled, including the PVC's. Metrics, and local logging will be lost during the migration process. Once all the components are removed a fresh install will bring everything back up functioning under the 'monitoring' namespace. Follow the related docs for more information.

#### New Features

- - Utilizes Opentelemetry as the primary service for metrics, logging and traces collection and exportation. - Removes Fluentbit which is relplaced with an Opentelemetry receiver. - Adds Tempo, a tracing backend that can be used within Grafana. - Updates Loki with better tunings and log handling configurations. - Removes and replaces several standalone Prometheus exporters with Opentelemetry receivers. MariaDB, Rabbit, Memcached, Postgres and Blackbox exporters have been removed and replaced. - Migrates observability code to a monitoring directory and namespace.

#### Critical Issues

- The upgrage to Opentelemetry and the refactored Observability stack will cause data loss for metrics and logging. Be prepared to store data in a external storage system or make a backup of the PVC if needed.

  In order to properly structure things, a destructive tear down of the components is required. Loki, Prometheus(and any exporters), Grafana(and its database) needs to be completely uninstalled, including the PVC's. Metrics, and local logging will be lost during the migration process. Once all the components are removed a fresh install will bring everything back up functioning under the 'monitoring' namespace. Follow the related docs for more information.

### Ceilometer

#### Prelude

Genestack Ceilometer has been reviewed and aligned for the Epoxy (`2025.1`) upgrade path, with updated operator guidance around telemetry definition changes, deprecated settings, release-specific behavior, and validated dependency handling for Gnocchi-backed deployments.

#### New Features

- Ceilometer `2025.1` adds broader telemetry coverage, including compute pollster publication of `disk.ephemeral.size` and `disk.root.size`.

- Ceilometer now exposes the `power.state` metric from `virDomainState`.

- Metadata coverage is expanded in `2025.1`, including `storage_policy` for Swift container telemetry and `volume_type_id` for volume notifications and Gnocchi resources.

- Ceilometer adds `[polling] ignore_disabled_projects`, which can reduce polling overhead in environments with disabled projects.

#### Known Issues

- The Epoxy highlights page does not include a dedicated Ceilometer section. Cross-project context still matters: Watcher Epoxy highlights note removal of the obsolete Ceilometer API datasource, which may affect operators with older integration assumptions around Ceilometer APIs.

- Ceilometer validation in Genestack depends on healthy Gnocchi API endpoints, PostgreSQL indexer storage, and Ceph metric storage. If any of those dependencies are absent, Ceilometer pods will remain in their init dependency wait state.

#### Upgrade Notes

- If your deployment overrides Ceilometer telemetry definitions, refresh local `meters.yaml` and `gnocchi_resources.yaml` content for `2025.1` before upgrade.

- Dynamic pollster URL handling changed in `2025.1`: relative `url_path` values are now appended to endpoint URLs. Review any custom dynamic pollsters that relied on prior replacement behavior.

- Upstream support was removed for Open Contrail, VMware vSphere, and Python 3.8. Ceilometer `2025.1` now requires Python 3.9 or newer.

- The following meters were removed upstream and should be removed from local expectations or integrations if still referenced: `cpu_l3_cache_usage`, `memory_bandwidth_local`, `memory_bandwidth_total`.

- Genestack now enables the Ceilometer `db-sync` job in the community baseline. This matches the active chart dependency graph used by the `central`, `compute`, and `notification` workloads and is required for a clean startup sequence with Gnocchi-backed telemetry storage.

#### Deprecations

- `[DEFAULT] hypervisor_inspector` is deprecated because libvirt is now the only supported hypervisor inspector backend.

- `[polling] tenant_name_discovery` is deprecated in favor of `[polling] identity_name_discovery`.

#### Bug Fixes

- Ceilometer `24.0.1` includes a libvirt inspector exception-handling fix for `interfaceStats` (`Bug #2113768`), reducing failure noise during telemetry collection.

### CloudKitty

#### Deprecations

- The cloudkitty chart will now use the online OSH helm repository. This change will allow the cloudkitty chart to be updated more frequently and will allow the cloudkitty chart to be used with the OpenStack-Helm project. Upgrading to this chart may require changes to the deployment configuration. Simple updates can be made by running the following command:

  .. code-block:: shell

  helm -n openstack uninstall cloudkitty
  kubectl -n openstack delete -f /etc/genestack/kustomize/cloudkitty/base/cloudkitty-rabbitmq-queue.yaml
  /opt/genestack/bin/install-cloudkitty.sh

  This operation should have no operational impact on running VMs but should be performed during a maintenance window.

## Kubernetes and Container Platform

### Kube-OVN

#### Prelude

Genestack 2026.1 upgrades Kube-OVN from v1.13.14 to v1.15.4 using v1.14.15 as an intermediate step. Operators must restore Neutron-managed ACLs after upgrading to v1.14.15 before proceeding to v1.15.4.

#### New Features

- Base Genestack now enables Kube-OVN garbage collection with `GC_INTERVAL: 360`.

#### Upgrade Notes

- Upgrade Kube-OVN in two stages:

  1. Record the current Neutron-managed ACL count before beginning the
   upgrade:

  kubectl ko nbctl list acl | grep neutron:security_group_rule_id > \
     /tmp/neutron-security_group_rule_id.txt
   wc -l /tmp/neutron-security_group_rule_id.txt

  2. Upgrade from Kube-OVN v1.13.14 to v1.14.15.

  Update `kube-ovn-helm-overrides.yaml` and
   `helm-chart-versions.yaml` to reference v1.14.15 as needed for
   the first-stage upgrade.

  3. Confirm that Neutron-managed ACLs were removed:

  kubectl ko nbctl list acl | grep neutron:security_group_rule_id | wc -l

  4. Restore Neutron-managed ACLs by resynchronizing OVN from Neutron:

  kubectl -n openstack exec -c neutron-server \
     $(kubectl -n openstack get pod \
       -l application=neutron,component=server -o name | shuf -n 1) \
     -- /var/lib/openstack/bin/neutron-ovn-db-sync-util \
     --config-file /etc/neutron/neutron.conf \
     --config-file /etc/neutron/plugins/ml2/ml2_conf.ini \
     --ovn-neutron_sync_mode add

  5. Verify that the ACL count has returned to the expected value, then
   continue the upgrade to Kube-OVN v1.15.4.

- Environments that currently disable Kube-OVN garbage collection with `GC_INTERVAL: 0` should set a non-zero value when upgrading to v1.15.4.

  Base Genestack now sets `GC_INTERVAL: 360`. Environments that do not override this value will inherit garbage collection behavior from the base configuration.

- The legacy `global.images.kubeovn.vpcRepository` override is no longer used with Kube-OVN v1.15.x.

  Operators who previously customized the VPC NAT gateway image using `global.images.kubeovn.vpcRepository` should migrate to:

  - `global.images.natgateway.repository` - `global.images.natgateway.tag`

  Environments that do not use Kube-OVN VPC NAT gateway functionality are unaffected.

#### Deprecations

- The legacy `global.images.kubeovn.vpcRepository` override path is obsolete for Kube-OVN v1.15.x. See the upgrade section for the replacement `global.images.natgateway.*` keys.

#### Critical Issues

- In Genestack's shared-OVN deployment, where OpenStack and Kubernetes use the same OVN Northbound database, upgrading Kube-OVN to v1.14.15 removes Neutron-managed OVN ACL associations.

  When this occurs, OpenStack security groups stop enforcing policy until the OVN Northbound database is resynchronized from Neutron.

  Operators must restore Neutron-managed ACLs after upgrading to v1.14.15 and before continuing to v1.15.4.

### Longhorn

#### Other Notes

- Added staged Longhorn upgrade guidance for moving Genestack storage from Longhorn 1.8.0 to 1.11.1 using the supported maintenance hops 1.8.0 -> 1.9.1 -> 1.10.2 -> 1.11.1. The release adds operator runbooks for each hop under `maintenances/` and documents the required Longhorn override settings in `/etc/genestack/helm-configs/longhorn/longhorn.yaml` so both user-deployed and system-managed components stay pinned to `longhorn.io/storage-node=enabled` nodes via `defaultSettings.systemManagedComponentsNodeSelector`. It also adds the `longhorn_storage_nodes` Ansible inventory group so operators can label every node intended to host Longhorn managers, drivers, instance-managers, and volume replicas with `longhorn.io/storage-node=enabled`.

  The guidance also covers the required CRD stored-version migration and verification step before the 1.9.1 -> 1.10.2 upgrade. For post-upgrade validation, it documents the expected Longhorn behavior where older instance-manager pods may remain while attached workloads continue using them, clarifies that this cleanup is optional rather than a required upgrade gate, and adds the helper script `/opt/genestack/scripts/longhorn-old-instance-managers.sh` to report PVCs, attached pods, Longhorn volumes, and instance-manager images. The helper script supports `--search` for narrowing output by attached pod name while preserving headers, and the runbooks include workload-specific restart guidance for operators who choose to accelerate cleanup during a maintenance window.

## Networking and Load Balancing

### Designate

#### New Features

- Added Designate is the DNS-as-a-Service (DNSaaS) component of Genestack. It provides API-driven management of DNS zones and records, so tenants and services can automatically create and update DNS entries as infrastructure changes.

#### Known Issues

- The designate service cleaner is not functional at the moment as of Feb 2026, possibly fixed in 2026.2. Added custom image in base helm overrides file to fix.

### Neutron / OVN

#### Prelude

Update Neutron to Epoxy (2025.1) release with enhanced OVN backend support and firewall_v2 enabled.

#### New Features

- Enabled firewall_v2 service plugin and extension driver for ML2/OVN backend.

- Updated Neutron container images to genestack-images/neutron:2025.1-latest.

- Updated the Neutron helm chart version to 2025.1.17+95bf0bf6e.

#### Upgrade Notes

- Firewall_v2 is now enabled by default. Existing firewall policies will be migrated automatically.

- The Neutron API now requires the `start-time=%t` variable in uWSGI configuration.

- Neutron resource tag limit of 50 tags per resource is now enforced. Resources with more than 50 tags will need to be modified to reduce tag count before upgrades.

- Neutron OVN `ovn_emit_need_to_frag` option is now enabled by default. This may impact performance on kernels older than 5.2. Consider setting to `False` if using older kernels.

- The Neutron `[DEFAULT] interface_driver` option now defaults to `openvswitch` and is not required when using OVN mechanism driver.

- Neutron OVN setting `localnet_learn_fdb` is now enabled to avoid flodding on provider networks once port security is disabled. See https://launchpad.net/bugs/2012069

#### Other Notes

- The Neutron Address Group support added to OVN mechanism driver.

- Neutron DNS records can now be configured as local to OVN using `[ovn]dns_records_ovn_owned` option.

- Neutron HA routers can now use conntrackd for connection state synchronization across router instances.

- Neutron QoS floating IP rules now take precedence over router rules when both are present.

### Octavia

#### Prelude

Octavia Epoxy (2025.1) adds support for SR-IOV member ports, VIP security groups, and Taskflow jobboard enhancements.

#### New Features

- Added support for SR-IOV virtual functions (VF) on Amphora member ports.

- Added the `vip_sg_ids` parameter to the load balancer create API, allowing operators to set user-defined Neutron security groups on the VIP port.

- Added `vip_sg_ids` support to the Amphora driver. When set, Octavia applies the specified security groups to the VIP port and manages only the required VRRP and HAProxy peer rules. This does not work with SR-IOV ports because Neutron security groups are not supported there.

- Added support for the Taskflow Etcd jobboard backend.

- Added the `[task_flow] jobboard_redis_backend_db` option to allow use of a non-default Redis database for the jobboard backend.

#### Upgrade Notes

- Amphora images must be updated to use the SR-IOV member port feature.

- During upgrade, default RBAC rules switch from Octavia Advanced RBAC to Keystone default roles. As a result, `load_balancer_*` roles no longer have access to the load balancer API unless the `octavia-advanced-rbac-policy.yaml` override is applied.

- UDP load balancers require a failover after the control plane is updated in order to correct the UDP rebalance issue.

- `diskimage-create.sh` now builds Ubuntu Noble (24.04) Amphora images by default.

#### Critical Issues

- The default RBAC model changes during upgrade from Octavia Advanced RBAC to Keystone default roles. Existing `load_balancer_*` roles will lose API access unless the advanced RBAC override policy is retained.

#### Security Notes

- The RBAC default change to Keystone roles is less restrictive than Octavia Advanced RBAC and removes some prior role scoping behavior, including global observer and quota-specific roles.

#### Bug Fixes

- Removed orphaned `amphora_health` records on revert to avoid false-positive failover threshold reactions.

- Fixed a potential `AttributeError` during listener update when a security group rule has no protocol defined.

- Fixed SINGLE topology UDP behavior by sending a gratuitous ARP when a UDP pool is added, improving VIP reachability after failover or IP reuse.

- Fixed verification of certificates signed by a private CA when using Neutron endpoints.

- Fixed error handling in `PlugVIPAmphora` revert when `db_lb` is not defined and subnet lookup raises `NotFound`.

- Fixed Amphora configuration updates so the health sender also receives the updated controller IP list.

- Fixed delayed UDP listener rebalance behavior where failed members could remain in flows for up to five minutes.

- Reduced the HAProxy SSL cache size for HTTPS termination listeners to help prevent OOM conditions during reload.

- Fixed L7Rule matching for `FILE_TYPE` with `EQUAL_TO` comparison.

- Fixed missing `port_id` in the `additional_vips` response field.

- Fixed a race condition during cascade delete of load balancers with multiple listeners that could trigger concurrent VIP port security group updates.

- Ignored the serialization load balancer class in `GetAmphoraNetworkConfigs` tasks to avoid storing full graphs in jobboard details for very large load balancers.

- Fixed an infinite database connection retry loop in the Octavia health worker.

- Drivers that fail to initialize are now properly removed from the enabled driver list instead of remaining configured and causing API initialization issues.

- Fixed Octavia API startup so provider driver load failures are handled gracefully and failing drivers are removed from the active enabled list.

#### Other Notes

- Added an `octavia-wsgi` script for backward compatibility because pbr's `wsgi_scripts` no longer functions with newer setuptools versions.

### MetalLB

#### Upgrade Notes

- Genestack `release-2026.1` deploys MetalLB `0.15.2` from the Helm chart. Sites upgrading from older Genestack releases may move directly from MetalLB `0.13.9` through `0.13.12` and skip the `0.14.x` series.

- Sites that already manage MetalLB with Helm should upgrade the existing chart release. Older environments that originally installed MetalLB through kubespray or another non-Helm path may have existing MetalLB resources that conflict with a Helm-managed deployment; remove the conflicting MetalLB resources before installing the chart-managed release.

- Do not replace `Service` annotations with the `metallb.io` prefix until after MetalLB has been upgraded. Perform the MetalLB upgrade first, then update the annotation prefix on Services and related manifests.

- After upgrading MetalLB, review all `Service` objects and any site-specific overrides or custom manifests for annotations using the `metallb.universe.tf` prefix and replace them with `metallb.io` equivalents. In typical Genestack deployments this most often affects externally exposed services such as MariaDB, RabbitMQ, Grafana, and envoyproxy-gateway.

- After updating manifests or overrides to use the `metallb.io` annotation prefix, redeploy any components or operators that manage `LoadBalancer` Services. Otherwise they may continue to recreate deprecated `metallb.universe.tf` annotation keys on managed Services.

#### Deprecations

- MetalLB deprecated the `metallb.universe.tf` annotation prefix in `0.14.9` in favor of `metallb.io`. For example, replace `metallb.universe.tf/address-pool` with `metallb.io/address-pool`.

- The deprecated prefix remains accepted in MetalLB `0.15.2` for backward compatibility, which allows the MetalLB upgrade to complete before Services are cleaned up. Operators should still remove the old keys after upgrading because future MetalLB releases may remove that compatibility.

### Envoy Gateway

#### Upgrade Notes

- Genestack `release-2026.1` deploys Envoy Gateway `v1.7.0` from the Helm chart. Sites upgrading from older Genestack releases may move directly from Envoy Gateway `v1.5.3` to `v1.7.0`.

- Upgrade Gateway API and Envoy Gateway CRDs before upgrading the Envoy Gateway Helm release. Sites using the Gateway API `experimental` channel should keep that channel during the CRD upgrade unless they have explicitly validated a later migration back to `standard`.

- Sites using `BackendTLSPolicy` should consider an incremental upgrade path instead of a direct jump to `v1.7.0`. A safer path is Envoy Gateway `v1.5.3` to `v1.5.8` to `v1.7.0`, followed by updating any `BackendTLSPolicy` resources from `gateway.networking.k8s.io/v1alpha3` to `v1`.

- After upgrading to Envoy Gateway `v1.7.0`, review `Gateway`, `HTTPRoute`, `GRPCRoute`, and policy resources for stricter validation behavior. Invalid route filters that may have been tolerated by older versions can now be rejected. In particular, Envoy Gateway `v1.7.0` may return direct `500` responses for `HTTPRoute` and `GRPCRoute` resources that use invalid filters.

- After upgrading Envoy Gateway, validate user-facing routes and any observability integrations. Envoy Gateway `v1.7.0` changes default metric tagging behavior and may require updates to dashboards, alerts, or recording rules that depend on previous metric names or label layouts.

#### Deprecations

- Envoy Gateway `v1.7.0` deprecates the OpenTelemetry access log `resources` field in favor of `resourceAttributes`. Sites using custom OpenTelemetry access log configuration should update manifests and overrides accordingly.

- Envoy Gateway `v1.7.0` changes the default `stats_tags` handling to improve Prometheus metrics output. Existing dashboards and alerting content may continue to work in some environments, but operators should review and update any metric queries that depend on the older label structure.

## Compute and Scheduling

### Blazar

#### Prelude

Blazar has been upgraded to OpenStack 2025.1 (Epoxy) release. This upgrade brings important security fixes, policy enhancements with new RBAC roles, and improved WSGI deployment capabilities. The Epoxy release focuses on strengthening OpenStack's position as a VMware alternative while enhancing security and operational capabilities.

#### New Features

- **New WSGI Module**: A new module `blazar.wsgi` has been added to provide a consistent location for WSGI application objects. This simplifies deployment with modern WSGI servers like gunicorn and uWSGI by allowing module path references (e.g., `blazar.wsgi.api:application`) instead of file paths.

- **Enhanced RBAC Policies**: Blazar now implements scope-based policies with new default roles (admin, member, and reader) provided by Keystone. All policies now support `scope_type` capabilities with project-level scoping, providing more granular access control while maintaining backward compatibility with legacy admin roles.

- **Instance Reservation Updates**: Fixed the ability to update the number of instances in an instance reservation while the lease is active, improving operational flexibility.

#### Upgrade Notes

- **WSGI Script Removal**: The `blazar-api-wsgi` script has been removed. Deployment configurations must be updated to reference the Python module path `blazar.wsgi.api:application` for WSGI servers that support module paths (gunicorn, uWSGI), or implement a custom `.wsgi` script for servers like mod_wsgi.

  Example uWSGI configuration change:

  .. code-block:: ini

  # Old configuration
  [uwsgi]
  wsgi-file = /bin/blazar-api-wsgi

  # New configuration
  [uwsgi]
  module = blazar.wsgi.api:application

- **Policy Migration**: While old policy rules remain supported for backward compatibility, operators should plan to migrate to the new scope-aware policies. The legacy `admin_or_owner` rule is deprecated in favor of new role-based rules like `project_member_api`, `project_reader_api`, `project_member_or_admin`, and `project_reader_or_admin`.

- **Image Updates**: Blazar container images have been updated to version `2025.1-latest`. Ensure your helm overrides reference the correct image tags as shown in `base-helm-configs/blazar/blazar-helm-overrides.yaml`.

#### Deprecations

- The blazar chart will now use the online OSH helm repository. This change will allow the blazar chart to be updated more frequently and will allow the blazar chart to be used with the OpenStack-Helm project. Upgrading to this chart may require changes to the deployment configuration. Simple updates can be made by running the following command:

  .. code-block:: shell

  helm -n openstack uninstall blazar
  kubectl -n openstack delete -f /etc/genestack/kustomize/blazar/base/blazar-rabbitmq-queue.yaml
  /opt/genestack/bin/install-blazar.sh

  This operation should have no operational impact on running workloads but should be performed during a maintenance window.

- **WSGI Script Deprecated and Removed**: The `blazar-api-wsgi` script has been removed in Epoxy (15.0.0). Use the module path `blazar.wsgi.api:application` instead.

- **Legacy Policy Rules**: The following policy rules are deprecated and will be silently ignored in future releases:

  - `admin_or_owner` - Use `project_member_api` or `project_reader_api` - Legacy `rule:admin_or_owner` references - Use new role-based rules

  JSON-formatted policy files have been deprecated since Blazar 7.0.0 (Wallaby). Use the `oslopolicy-convert-json-to-yaml` tool to migrate to YAML format.

#### Security Notes

- **Critical Lease Security Fix**: Resolved a security vulnerability (LP#2120655) where any user could update or delete a lease from any project if they had the lease ID. With default policy configuration, regular users cannot see lease IDs from other projects. However, operators running the Resource Availability Calendar with overridden policies may have been vulnerable without this fix.

#### Bug Fixes

- Fixed host randomization feature functionality (LP#2099927).

- Fixed an issue preventing updates to the instance count in active instance reservations (LP#2138386).

- Resolved security vulnerability allowing unauthorized lease modifications across projects (LP#2120655).

#### Other Notes

- **Genestack Configuration**: The current Genestack configuration already uses the `2025.1-latest` image tags and includes proper RabbitMQ quorum queue configuration with notification routing to Ceilometer for billing integration.

- **Python Version**: OpenStack Epoxy requires Python 3.9 as the minimum supported version. Python 3.8 support has been removed across OpenStack projects.

### Libvirt

#### Prelude

Libvirt upgrade from Caracal (2024.1) to Epoxy (2025.1). Helm chart changes between 2024.2.94+912f85d38 and 2025.1.4+ed289c1cd.

Genestack now documents and supports enabling libvirt exporter metrics as a per-cluster override instead of changing the base libvirt Helm defaults. This keeps the base deployment minimal while allowing environments with Prometheus Operator to opt into libvirt metrics collection.

#### New Features

- Added support for configurable libvirt hooks via chart values: `conf.hooks.enabled` and `conf.hooks.scripts`. Scripts are mounted into `/etc/libvirt/hooks` in the libvirt container.

- Added configurable exporter arguments under `pod.sidecars.libvirt_exporter.args` so alternative exporter images can be used when default `--libvirt.nova` arguments are not desired.

- Added optional PodMonitor support with `manifests.podmonitor` to expose libvirt-exporter metrics to Prometheus Operator environments.

- Operators can enable the libvirt exporter sidecar and PodMonitor through a cluster-specific libvirt Helm override by setting `pod.sidecars.libvirt_exporter.enabled: true` and `manifests.podmonitor: true`.

- The recommended per-cluster override can also retain `conf.init_modules.enabled: true` where nested virtualization support is required on compute hosts.

- Genestack now enables the libvirt chart's `conf.init_modules` workflow by default in the base libvirt Helm overrides. This writes host modprobe configuration for `kvm_intel` or `kvm_amd` and enables nested virtualization on compute nodes that support it, allowing guest workloads to use nested KVM when Nova/libvirt CPU settings also expose virtualization extensions to the instance.

#### Known Issues

- `manifests.podmonitor` only has effect in clusters with the Prometheus Operator CRDs installed, and useful metrics require `pod.sidecars.libvirt_exporter.enabled: true`. Validate scrape target discovery after enabling either setting.

- `manifests.podmonitor` only has effect in environments with Prometheus Operator CRDs installed, and useful metrics require the `libvirt_exporter` sidecar to be enabled at the same time.

#### Upgrade Notes

- The libvirt exporter sidecar values schema changed from boolean to object. Update overrides from: `pod.sidecars.libvirt_exporter: true` to: `pod.sidecars.libvirt_exporter.enabled: true` and optionally set `pod.sidecars.libvirt_exporter.args`.

- New configurable probe values exist for libvirt-exporter under `pod.probes.libvirt.libvirt_exporter.{readiness,liveness}`. Existing environments with strict startup timing may need probe tuning.

- Ceph helper image default changed from `ceph-config-helper:ubuntu_jammy_19.2.2-1-20250414` to `ceph-config-helper:ubuntu_jammy_19.2.3-1-20250805`. Re-validate Ceph keyring placement and compute startup behavior where Ceph-backed instances are used.

- For Caracal (2024.1) to Epoxy (2025.1), validate Nova/libvirt-driver service-level changes in parallel with chart updates, including: - minimum supported libvirt/QEMU levels in Epoxy; - migration settings and TLS behavior under `[libvirt]`; - cgroup v2 compatibility on compute hosts.

- Override `images.tags.libvirt` to the latest digest tag OR override `images.pull_policy` to `Always` to force upgrade of libvirt daemonset.

#### Deprecations

- Nova/libvirt-driver deprecates legacy incoming migration configuration paths in favor of secure incoming migration settings. Review migration config placement and TLS assumptions during Caracal to Epoxy if using non-defaults.

#### Bug Fixes

- The libvirt chart adds explicit readiness and liveness probe handling for the `libvirt-exporter` sidecar, improving sidecar health reporting behavior relative to prior defaults.

#### Other Notes

- Genestack base libvirt Helm overrides remain unchanged; this metrics enablement is intended to be applied in cluster-specific override files.

### Nova

#### Prelude

Nova upgrade from to Epoxy (2025.1). Helm chart changes between 2024.2.555+13651f45-628a320c and 2025.1.19+ed289c1cd.

#### New Features

- Added chart support for Nova serial console proxy with new serialproxy deployment, service, ingress, endpoint, TLS secret, and manifest toggles.

- Added support for projected config sources mounted into `/etc/nova/nova.conf.d` using `pod.etcSources.*` to simplify out-of-band config overrides.

- Added optional Keystone service-account snippet secret (`secret_ks_etc`) for injecting credential sections into `nova.conf.d`.

- Added runtime class and priority class hooks in pod templates for improved scheduling and workload isolation customization.

- Genestack now enables `use_rootwrap_daemon = true` in the base Nova Helm overrides under `conf.nova.DEFAULT`. This aligns Nova compute configuration with the recommended OpenStack 2025.1 guidance for compute nodes and reduces rootwrap overhead for privileged operations.

#### Known Issues

- Validate `new/nova/templates/service-serialproxy.yaml` selector behavior before production use of serial console; the service selector tuple appears to use `noa` instead of `nova` and may fail to match pods if unpatched.

- Secret handling by install-nova.sh fixed in: PR #1429 <https://github.com/rackerlabs/genestack/pull/1429>__

#### Upgrade Notes

- Default compute API endpoint path changed from `/v2.1/%(tenant_id)s` to `/v2.1/`. Validate endpoint URL rewrite rules, service catalog entries, and client assumptions.

- New `endpoints.volumev3` defaults were introduced and Nova cinder auth settings are now more explicit (including `auth_type` default). Validate cinder endpoint path/catalog assumptions during upgrade.

- Nova service processes now consistently load `--config-dir /etc/nova/nova.conf.d` in addition to the main config file. Ensure any custom overrides are reconciled with the new snippet-loading behavior.

- Check quota unified limits for resource classes without registered limits when migrating from legacy quotas to unified limits quotas. `unified_limits_resource_strategy` default is `require`

- Default identity usernames for service integrations now use `nova_*` naming (for neutron, placement, cinder, ironic) and add a dedicated `service` identity. Legacy keystone users may no longer be needed.

- The new Nova helm chart iterates through endpoints.identity.auth for user configuration. endpoints.identity.auth may require modification/removal.

- Environments overriding `conf.nova.DEFAULT.use_rootwrap_daemon` should reconcile those settings with the new base default. Validate that `nova-rootwrap-daemon` and the related sudoers/rootwrap configuration are present in the deployed Nova compute image before rollout.

### Placement

#### Prelude

Placement upgraded to OpenStack 2025.1 (Epoxy) release.

#### New Features

- Added `placement.wsgi` module for simplified WSGI server deployment.

- Added new configuration options: `[placement]max_allocation_candidates`, `[placement]allocation_candidates_generation_strategy`, and `[workarounds]optimize_for_wide_provider_trees` to improve allocation candidate generation performance, particularly in deployments with wide provider trees.

#### Upgrade Notes

- Helm chart updated to `2025.1.2+0cd784591`.

- Consider configuring `max_allocation_candidates` and `allocation_candidates_generation_strategy` for wide provider trees.

#### Bug Fixes

- Fixed excessive memory consumption when generating allocation candidates in deployments with wide provider trees.

### Ironic

#### Prelude

Ironic has been upgraded from OpenStack 2025.1 (Epoxy). This release introduces major improvements in deployment workflows, image handling, and Redfish interoperability, along with important security hardening around image sources. The Epoxy cycle continues the transition toward container-native provisioning and improved standards compliance, while tightening validation and access controls across the service.

#### New Features

- **Container Image Deployment (OCI Support)**: Ironic now supports deploying images directly from OCI/container registries. This enables operators to manage bare metal images using standard container tooling and workflows, improving consistency across infrastructure and application pipelines.

- **bootc Deploy Interface**: A new `bootc` deploy interface has been introduced to support bootable container images. This enables direct provisioning of container-native operating systems onto bare metal, aligning with modern immutable infrastructure practices.

- **Zstandard Image Support**: Deployment workflows now automatically detect and handle Zstandard (`.zst`) compressed images, reducing storage and transfer overhead without requiring manual decompression steps.

- **Rootless Container Console Support**: Added support for systemd-managed, rootless Podman containers to provide VNC console services. This improves security by removing the need for privileged containers in console access.

- **Enhanced Hardware Inspection Rules**: Inspection rule processing now supports additional comparison operators (`le`, `ge`, `ne`), enabling more expressive and flexible hardware introspection and classification.

- **Service State Improvements**: Nodes can now be unprovisioned while in `service wait` state, improving operational flexibility for long-running service workflows such as cleaning or firmware updates.

- **Improved Glance Integration**: Image access via Keystone authentication tokens is now enabled by default, improving security and consistency when retrieving images from Glance.

- **Redfish Interoperability Enhancements**: Expanded support for vendor implementations with improved handling of boot device configuration, boot modes, and power state synchronization.

#### Known Issues

- **Large Image Handling Sensitivity**: Although improved, deployments using very large images may still experience resource pressure (CPU/memory) during download and checksum operations. Validation in staging environments is recommended.

- **Stricter Validation May Surface Failures**: Improvements in error handling (network binding, inspection, and deployment validation) may expose issues that were previously ignored or silently handled.

- **Mixed Redfish Environments**: While compatibility has improved, hardware inconsistencies across vendors may still require validation due to stricter boot parameter enforcement.

- **Upstream Helm Chart Issues**: The upstream Helm chart for the Epoxy release has several issues. Some fixes are present in the master branch but have not been backported to earlier releases. A patched version that includes all fixes can be downloaded from the artifact repository at `[internal URL redacted]`.

- **Nova ConfigDrive Fix**: The Nova virt driver ConfigDrive issue `bug-2148059` has been fixed in the patched image for the Epoxy release. The updated image can be downloaded from the artifact repository at `[internal URL redacted]`.

#### Upgrade Notes

- **Default Image Auth Behavior Changed**: The configuration option `[DEFAULT]allow_image_access_via_auth_token` now defaults to `True`. Operators must ensure Glance images are accessible via appropriate visibility (public/community) or adjust policies to avoid deployment failures.

- **file:// Image Access Restrictions (Security Hardening)**: Access to local image files via `file://` URLs is now restricted using the `[conductor]file_url_allowed_paths` allowlist.

  Operators upgrading from 2024.2 must explicitly configure allowed paths if they rely on local image sources, otherwise deployments will fail.

  Example configuration:

  .. code-block:: ini

  [conductor]
  file_url_allowed_paths = /var/lib/ironic/images,/opt/local_images

- **Redfish Boot Behavior Changes**: Some Redfish drivers now require more complete boot parameter payloads. Existing automation or custom tooling interacting with Redfish should be validated against hardware.

- **Stronger Validation and Error Handling**: Networking, inspection, and deployment workflows now enforce stricter validation. Automation relying on previously lenient behavior may require updates.

- **Performance Tuning Changes**: Image download behavior has changed (streaming checksum, larger chunk sizes). Operators should validate performance characteristics, especially in constrained environments.

#### Deprecations

- **Unrestricted file:// Image Usage Deprecated**: Direct use of `file://` image URLs without explicit allowlisting is deprecated and will be further restricted in future releases.

- **Legacy Redfish Boot Handling**: Minimal or implicit boot parameter usage is being phased out. Operators should transition to fully specified boot configurations for consistent cross-vendor behavior.

- **ironic-inspector Deprecation (Maintenance Mode)**: The `ironic-inspector` project has entered maintenance mode and will only receive bug fixes and minor updates going forward. Its functionality is being gradually integrated directly into the Ironic service.

  A preview of the integrated inspection capabilities was introduced during the Caracal release cycle, with full deprecation of `ironic-inspector` expected in subsequent releases.

- **Reference**: [ironic-inspector](https://docs.openstack.org/releasenotes/ironic-inspector/en_GB/2023.2.html)

#### Security Notes

- **OSSA-2025-001 – Local File Exposure via file:// URLs**: Fixed a vulnerability where improper validation of `file://` image paths could allow access to arbitrary local files readable by the ironic-conductor.

  This issue is mitigated by introducing the `[conductor]file_url_allowed_paths` configuration option.

- **Path Restriction Hardening**: Additional safeguards have been introduced to prevent access to sensitive filesystem locations. Future releases will further restrict access to paths such as `/dev`, `/proc`, and `/sys`.

- **Reference**: [security-issues](https://docs.openstack.org/releasenotes/ironic/2025.1.html?utm_source=#security-issues)

#### Bug Fixes

- **Authentication Performance Improvements**: Optimized HTTP Basic authentication using bcrypt caching, significantly reducing API and conductor overhead under load.

- **Redfish Stability Fixes**: Resolved race conditions and improved power state reconciliation with BMCs, reducing deployment and cleaning failures.

- **Firmware Update Reliability**: Fixed issues where firmware updates could become stuck in `service` workflows.

- **Swift Data Handling Fixes**: Corrected storage format inconsistencies for inventory and plugin data stored in Swift.

- **Image Download Optimization**: Improved efficiency through streaming checksum calculation and larger chunk sizes, reducing deployment time.

- **Inspection and Runbook Validation Fixes**: Addressed validation gaps in inspection hooks and runbook execution.

- **General Redfish Compatibility Fixes**: Multiple fixes across vendors to improve interoperability and reduce provisioning errors.

- **Reference**: [bug-fixes](https://docs.openstack.org/releasenotes/ironic/2025.1.html?utm_source=#bug-fixes)

#### Other Notes

- **Operational Recommendation**: Due to security changes and stricter validation, a full pre-upgrade validation is strongly recommended, including: - Image accessibility (Glance/file://) - Redfish hardware compatibility - Inspection rule behavior - Network binding workflows

- **Upgrade Strategy**: Perform rolling upgrades of conductors where possible and validate node state transitions (especially cleaning and deployment) before upgrading all regions.

- **Ecosystem Alignment**: This release aligns Ironic more closely with container-native infrastructure trends and improved OpenStack RBAC and security models introduced across Epoxy.

### Masakari

#### Deprecations

- The masakari chart will now use the online OSH helm repository. This change will allow the masakari chart to be updated more frequently and will allow the masakari chart to be used with the OpenStack-Helm project. Upgrading to this chart may require changes to the deployment configuration. Simple updates can be made by running the following command:

  .. code-block:: shell

  helm -n openstack uninstall masakari
  kubectl -n openstack delete -f /etc/genestack/kustomize/masakari/base/masakari-rabbitmq-queue.yaml
  /opt/genestack/bin/install-masakari.sh

  This operation should have no operational impact on running workloads but should be performed during a maintenance window.

## Identity and Secrets

### Keystone

#### Prelude

Keystone upgrade to Epoxy (2025.1) completed. Helm chart updated from 2024.2 to 2025.1.5+ed289c1cd with image updates to the 2025.1 stream. Helper container images migrated from heat to openstack-client.

#### New Features

- Add LDAP/AD Integration into Keystone config via genestack overrides file

- Keystone images updated to 2025.1-latest stream (ghcr.io/rackerlabs/genestack-images/keystone:2025.1-latest).

- Helper container images (bootstrap, db_drop, db_init, ks_user, keystone_credential_cleanup) migrated from legacy heat:2024.1-latest to purpose-built openstack-client:latest image.

- Upstream Keystone 2025.1 adds pagination support for user, group, project, and domain listing via `limit` and `marker` query parameters.

- New `keystone.wsgi` module provides a consistent WSGI application location for simplified deployment with uWSGI or gunicorn.

#### Upgrade Notes

- Helm chart version advanced from 2024.2 series to 2025.1.5+ed289c1cd.

- Dependency on passlib library has been dropped upstream in favor of using bcrypt and cryptography directly. Passwords hashed with passlib are still supported but edge cases may require password rotation.

- Python 3.8 support was dropped upstream. Minimum supported version is now Python 3.9.

- The templated catalog driver and `[catalog] template_file` option have been removed upstream.

#### Deprecations

- Removed deprecated `heartbeat_in_pthread` override from Keystone chart values to align with oslo.messaging deprecation guidance.

- Upstream deprecation: `[DEFAULT] max_param_size` option is deprecated (was used for identity v2 API removed in 13.0.0).

- Upstream warning: sha512_crypt password hashing support will be removed in the next release (post-Epoxy). Users with sha512_crypt hashed passwords should rotate their passwords before upgrading past 2025.1.

#### Security Notes

- Upstream fix: Tokens for users disabled in read-only backends (LDAP) are now properly invalidated. Previously, tokens continued to be accepted after user disablement due to missing backend notifications. See LP#2122615 for details.

#### Other Notes

- Legacy heat helper images replaced with openstack-client to reduce image sprawl and align with Genestack container strategy.

### Barbican

#### Prelude

Barbican Epoxy enablement and validation has been completed for Genestack using the OpenStack 2025.1 stream (Barbican 20.x). Deployment behavior, database connectivity requirements, and post-deploy secret workflows were verified in a hyperconverged lab environment.

#### New Features

- Barbican API deployment for the 2025.1 image stream was validated in the hyperconverged lab and confirmed operational for service endpoint access.

- Basic Barbican secret lifecycle validation was completed successfully, including secret store, metadata retrieval, payload retrieval, and delete.

#### Known Issues

- Barbican client operations fail when Keystone key-manager endpoints point to non-resolvable hostnames. Endpoint host/scheme values must match reachable in-cluster service DNS and network paths.

#### Upgrade Notes

- Barbican DB sync requires a resolvable MariaDB service hostname (for example `[database service host]`) and valid DB credentials to complete migration.

- During Epoxy validation, DB credential handling was confirmed through Kubernetes secret injection via install workflow (`endpoints.oslo_db.auth.*.password`) rather than static plaintext values.

- Upstream Barbican 2025.1 release impacts were reviewed; runtime baseline changes include removal of Python 3.8 support (minimum supported is 3.9).

#### Deprecations

- Hardcoded plaintext database connection strings in Barbican Helm overrides are deprecated for Genestack deployment workflows and should be replaced with secret-driven credential injection.

- Removed deprecated `heartbeat_in_pthread` override from Barbican chart values to align with upstream deprecation guidance.

- Upstream deprecation of `[p11_crypto_plugin] hmac_keywrap_mechanism` (renamed to `hmac_mechanism`) was reviewed; this is currently not applicable in this environment because HMAC/PKCS#11 flow is not enabled.

#### Security Notes

- Secret-based DB credential handling was reinforced by using Kubernetes secrets at deploy time instead of committing DB passwords in override YAML.

#### Bug Fixes

- Fixed `barbican-db-sync` failures caused by invalid or unresolved database endpoint/connection configuration during Epoxy deployment.

- Fixed endpoint usage path for Barbican client operations so secret API calls succeed without discovery/connection errors in the validated lab setup.

#### Other Notes

- No additional critical release-specific risks were identified for this Barbican Epoxy validation scope.

## Storage, Images, and Data Protection

### Freezer

#### Prelude

For more information about Freezer and upstream release notes, see: Freezer release notes at https://opendev.org/openstack/freezer/src/branch/master/releasenotes/notes and Freezer API release notes at https://opendev.org/openstack/freezer-api/src/branch/master/releasenotes/notes

#### New Features

- Freezer provides comprehensive backup and restore capabilities for OpenStack environments, supporting multiple backup types:

  Backup capabilities:

  - QCOW2 image based VM backup - RAW image based VM backup - Client local filesystem backup - Client local LVM filesystem backup - MySQL DB backup - Mongo DB backup - Cinder volume backup

  Restore capabilities:

  - QCOW2 image based VM restore - RAW image based VM restore - Client local filesystem restore - Client local LVM filesystem restore - MySQL DB restore - Mongo DB restore - Cinder volume restore

- Added Freezer backup retention policy automation script that helps manage Swift object lifecycle and container cleanup. The script provides automated expiration management for Freezer backup containers stored in Swift.

  Key features include:

  - Set X-Delete-At headers on all objects in specified containers - Flexible retention periods (seconds, minutes, hours, days, months) - Automatic monitoring and deletion of empty containers - Progress tracking with configurable check intervals - Timeout protection to prevent indefinite execution - Dry-run mode for testing - Support for multiple containers in a single operation

  The script is located at `scripts/freezer_retention/swift_retention_policy.py` and includes comprehensive documentation in the accompanying README.

  Example usage:

  .. code-block:: shell

  # Set 7-day retention and auto-cleanup
  ./swift_retention_policy.py -c freezer-bkp-lvm -d 7 --cleanup

  # Multiple containers with custom monitoring
  ./swift_retention_policy.py -c freezer-daily -c freezer-weekly \
    -H 1 --cleanup --check-interval 30

### Cinder

#### Prelude

Genestack Cinder has been updated for Epoxy (`2025.1`) with a focus on safer day-2 operations, cleaner defaults, and repeatable installs.

#### New Features

- The playbooks `deploy-cinder-volumes-reference.yaml` and `deploy-cinder-netapp-volumes-reference.yaml` are consolidated into the `cinder_volumes` role. Most of the existing override are retained and consistently prefixed by `cinder_` and are listed as example inside the `inventory.yaml.example`.

  `cinder_backend_name` Enables a named or list of cinder backends on the local `cinder-volume` service.

  `cinder_worker_name` Defines the service name of the of the local `cinder-volume` service.

- Cinder chart and image baselines were updated for the `2025.1` release track.

- Cinder helper jobs now use the `openstack-client` image family instead of the legacy helper pattern, aligning Cinder with current Genestack tooling.

- Community defaults keep Cinder disabled by default (`openstack-components`) so users can opt in intentionally.

- Upstream Cinder `26.0.0` adds the `cinder.wsgi` module for cleaner WSGI app loading (for example `cinder.wsgi.api:application`), which simplifies deployment patterns.

- Upstream Cinder/Ceph adds a backup retention option to keep only the last `n` snapshots per volume backup, reducing source-side Ceph snapshot growth.

- Epoxy highlights call out Cinder Brick multipath setup/management improvements and broad driver updates across common backends.

#### Upgrade Notes

- The playbooks `deploy-cinder-volumes-reference.yaml` and `deploy-cinder-netapp-volumes-reference.yaml` are consolidated into the `cinder_volumes` role. Most of the existing override are retained and consistently prefixed by `cinder_` and are listed as example inside the `inventory.yaml.example`

- If you use Fujitsu backends with password authentication, set `fujitsu_passwordless = False`. In 2025.1 the default is `True`.

- Existing environments that use `keystone_authtoken.auth_uri` should plan to migrate to `www_authenticate_uri`.

- Breaking change: generated global `endpoints.identity.auth` overrides are no longer applied from hyperconverged common endpoint generation. If your environment depended on that global block (for example custom service auth region/user domain/project domain values), move those settings into service-specific helm overrides before upgrade.

#### Deprecations

- The playbooks `deploy-cinder-volumes-reference.yaml` and `deploy-cinder-netapp-volumes-reference.yaml` are consolidated into the `cinder_volumes` role.

  The override `custom_multipath` is deprecated and replaced with `storage_network_multipath` to simplify the configuration.

- Remove deprecated iSER options from local overrides if still present: `num_iser_scan_tries`, `iser_target_prefix`, `iser_ip_address`, `iser_port`, `iser_helper`.

- Pure Storage `queue_depth` is deprecated and is expected to be removed in `2026.1`.

#### Bug Fixes

- Cinder install/reinstall flows were validated in hyperconverged lab runs, including a successful immediate rerun (`install-cinder.sh`) for idempotency.

- Cinder API and scheduler runtime validation showed healthy replicas and no fatal runtime errors in sampled logs.

- Upstream Cinder bug fixes directly relevant to operators include:
- `Bug #2105961`: NVMe-oF connector validation now checks `nqn` correctly.
- `Bug #2111461`: `cinder-manage` purge path fixed for FK constraint cases.
- `Bug #1907295`: attachment update failures now return `409` instead of
  generic `500` in invalid state paths.
- `Bug #2082587`: backup restore TypeError fix.

- Upstream Ceph/RBD-related Cinder fixes include:
- RBD `Bug #2115985`: manage-volume fix for `multiattach` and
  `replication_enabled` type properties.
- NFS snapshot regression fix (`Bug #2074377`) and attached-volume snapshot
  metadata fix (`Bug #1989514`) included in the Epoxy cycle.

#### Other Notes

- Known warnings seen during validation were limited to expected deprecation signals (for example `auth_uri`) and did not block deployment.

### Glance

#### Prelude

Glance Epoxy (2025.1) focuses on safer image handling, predictable multi-store download behavior, and stability fixes for policy initialization and RBD-backed deployments. The release introduces stricter upload/import validation while retaining operator controls for compatibility tuning.

#### New Features

- Added image content inspection during upload/import to validate declared `disk_format` against uploaded data.

- Added configuration controls: `[image_format]/require_image_format_match` and `[image_format]/gpt_safety_checks_nonfatal`.

- Updated `GET images` behavior to sort image locations by configured store weight, affecting which backend location is preferred for download.

- Extended stores detail API output for RBD backends to include `fsid`.

#### Known Issues

- No explicit unresolved known issues were identified in the reviewed Epoxy Glance note fragments; operators should still validate upload/import behavior with real image sets due to stricter format checks.

#### Upgrade Notes

- Support for running Glance services on Windows operating systems has been removed.

- Upload/import now checks content against `disk_format` by default; operators should review current image pipelines and user workflows for format mismatch failures and tune related image_format options as needed.

#### Deprecations

- No new deprecations were explicitly called out in the reviewed Epoxy Glance fragments.

#### Bug Fixes

- LP #2081009: Fixed `oslo_config.cfg.NotInitializedError` when switching the default `policy_file` in oslo.policy.

- LP #2086675: Fixed suspected performance regression for RBD backends linked to image location sorting behavior.

### Trove

#### New Features

- Added Openstack Trove support. Migrated Trove to use the official upstream OpenStack-Helm chart now that it has been merged and is available in the upstream repository.

## Orchestration

### Heat

#### Prelude

The Heat chart configuration has been updated for the OpenStack-Helm 2025.2 line. This change aligns Genestack Heat overrides with chart removals and current image defaults.

#### Upgrade Notes

- The Heat CloudWatch API path is no longer supported by the chart. CloudWatch manifests and related values have been removed from Heat overrides.

- Keystone user bootstrap behavior changed in upstream Heat chart logic: `job-ks-user` now creates both `heat` and `heat_trustee` users. Legacy `heat-trustee-ks-user` job dependencies have been removed from Genestack Heat overrides.

- Heat and OpenStack client image overrides now use Genestack GHCR images:

  - `ghcr.io/rackerlabs/genestack-images/openstack-client:2025.1-latest` - `ghcr.io/rackerlabs/genestack-images/heat:2025.1-latest`

- Heat API and CFN liveness probe patches were updated to use port `1717` to match stats-based probe behavior enabled by the current Heat chart.

#### Deprecations

- CloudWatch-specific Heat override keys are no longer supported and should not be used in custom overlays.

### Skyline

#### Prelude

Skyline has been migrated from a kustomize-based deployment to the upstream OpenStack Helm chart. This change brings Skyline in line with other OpenStack services in Genestack and provides better integration with the Helm ecosystem.

#### Upgrade Notes

- Converting to the New Helm Installation Process

  Skyline deployment has been migrated from kustomize to the upstream OpenStack Helm chart. To convert to the new installation process:

  Step 1: Uninstall the existing kustomize-based Skyline deployment

  .. code-block:: shell

  kubectl --namespace openstack delete -k base-kustomize/skyline/base

- Preparing for the new Skyline Helm installation

  The new secret must be created with the key `db-password` containing the password for the Skyline database user. This password should match the one generated by `create-secrets.sh`.

  Example manifest for the new secret, this file should be used to create the required secrets and then deleted after the Helm installation is complete.

  .. code-block:: yaml

  ---
  apiVersion: v1
  kind: Secret
  metadata:
    name: skyline-db-password
    namespace: openstack
  type: Opaque
  data:
    password: "$DB_PASSWORD"
  ---
  apiVersion: v1
  kind: Secret
  metadata:
    name: skyline-admin
    namespace: openstack
  type: Opaque
  data:
    password: "$ADMIN_PASSWORD"

  .. code-block:: shell

  kubectl apply -f skyline-secrets.yaml

  Add the skyline chart version to the `helm-chart-versions.yaml` file at `/etc/genestack/helm-chart-versions.yaml`:

  .. code-block:: yaml

  ---
  charts:
    skyline: 2025.2.9+c665eedfa

  Make the skyline helm overrides directory

  .. code-block:: shell

  mkdir -p /etc/genestack/helm-configs/skyline
  echo '---' > /etc/genestack/helm-configs/skyline/skyline-helm-overrides.yaml

  within the skyline helm overrides directory, create a minimal override file that should contain the region information. for the cloud.

  .. code-block:: yaml

  conf:
    skyline:
      openstack:
        default_region: RegionOne

  See the federation documentation for more details on how to configure the helm overrides when using WebSSO.

  - [internal URL redacted]

  Make the skyline kustomize overrides directory and symlinks

  .. code-block:: shell

  mkdir -p /etc/genestack/kustomize/skyline
  ln -s /opt/genestack/base-kustomize/skyline/base /etc/genestack/kustomize/skyline/base
  ln -s /opt/genestack/base-kustomize/skyline/aio /etc/genestack/kustomize/skyline/aio

- Running the new Skyline Helm installation

  1. Check existing secrets:

  .. code-block:: shell

  kubectl --namespace openstack get secret skyline-db-password -o yaml
     kubectl --namespace openstack get secret skyline-admin -o yaml

  2. If secrets exist and are valid: Simply proceed with the Helm installation
   using `/opt/genestack/bin/install-skyline.sh`

  3. Verify database connectivity: After installation, check that Skyline can
   connect to the database:

  .. code-block:: shell

  kubectl --namespace openstack logs -l application=skyline | grep -i "database\|connection"

  4. Verify the deployment

  .. code-block:: shell

  kubectl --namespace openstack get pods -l application=skyline
     kubectl --namespace openstack get svc skyline-api

  5. Update the gateway configuration to point to the new skyline API service if necessary.

  The the old service name was `skyline-apiserver`, new service is be named `skyline-api`.
   Update the gateway configuration to point to this new service.

  The HTTPRoute for the skyline API can be patched using the `custom-skyline-gateway-route.yaml` file.

  .. code-block:: shell

  kubectl apply -f /etc/genestack/gateway-api/routes/custom-skyline-gateway-route.yaml
