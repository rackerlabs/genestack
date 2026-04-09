# Release 2026.1

This release note set is organized by component to make upgrade planning and validation easier.

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

Allow other kubernetes deployment models including Talos k8s stack to include a
managed cert-manager helm chart. Decouple the cert-manager installation from the
base kubespray ansible roles and allow the official upstream charts to provide
chart and CRD updates including patched image rollouts. This includes envoy
gateway-api support and custom DNS server forwarders.

### Proxy Environment Handling

#### Bug Fixes

A new override `force_proxy_setting` is introduced to control when proxy
environment variables are added into the shell and systemd environment.
In some circumstances, adding system-wide HTTP proxy environment variables
can cause issues with dbus, rendering systemd inoperable and stopping all
systemd operations including reboot. This can happen if the proxy server
does not allow reverse connections or blocks requests to localhost when `NO_PROXY`
is improperly configured.

### MariaDB Operator

#### Prelude

MariaDB Operator Helm charts have been upgraded from 0.38.1 to 26.3.0
following the recommended progressive upgrade path via 25.8.4 and 25.10.4.

Upgrade path:
    0.38.1 → 25.8.4 → 25.10.4 → 26.3.0

The version 25.8.4 and 25.10.4 is the latest patch release in the 25.8.x and
25.10.x series and includes all prior fixes along with additional stability
improvements.

This upgrade introduces improvements to replication failover behaviour,
backup and restore capabilities, operator stability, and compatibility
with newer Kubernetes versions.

The 25.x release line establishes PhysicalBackup and improved replication
handling, while 26.3.0 extends this with Point-in-Time Recovery (PITR),
enhanced backup integrations, and Helm chart structural changes.

These improvements apply to both Galera and replication clusters.

#### New Features

Physical backups introduced in the 25.8 release series via the PhysicalBackup CR.

Supported mechanisms:
  * MariaDB-native backups using mariadb-backup
  * Kubernetes VolumeSnapshots for storage-level backup and restore

Benefits:
  * Faster backup and restore operations
  * Reduced recovery time objectives (RTO)
  * Support for cluster bootstrapping via spec.bootstrapFrom

Replication cluster improvements across the 25.x series:
  * More stable and predictable failover handling
  * Improved replica lifecycle management
  * Enhanced reconciliation reducing drift and recovery time

Backup and restore improvements in the 25.10 series:
  * Improved backup job generation and scheduling
  * More reliable restore workflows
  * Enhanced object storage compatibility (e.g. S3, SSE-C)

Replication clusters can now configure backup targets to run on replicas
instead of the primary using:
  target: Replica
  target: PreferReplica

New capabilities introduced in 26.3.0:

  * Point-in-Time Recovery (PITR) support
    - Enables restoring databases to a specific timestamp
    - Improves recovery precision beyond full backup restores

  * PhysicalBackup enhancements:
    - Azure Blob Storage support
    - On-demand PhysicalBackup execution

  These features significantly improve disaster recovery flexibility and
  multi-cloud support.

Introduced the new `mariadb-cluster` Helm chart for managing MariaDB
clusters and related resources in a single Helm release. This provides
an alternative deployment method to Kustomize-based installations.

#### Known Issues

Replication auto-failover depends on Kubernetes detecting primary pod failure.
In node shutdown or network partition scenarios, failover timing is influenced
by Kubernetes node health detection and eviction behaviour.

VolumeSnapshot-based backups depend on CSI driver capabilities and may vary
across environments in terms of consistency guarantees.

In 26.3.0, restore behaviour using bootstrapFrom.targetRecoveryTime has changed:
the operator now selects the closest backup **not after** the requested timestamp.

This may result in different restore points compared to previous versions and
should be validated in recovery procedures.

#### Upgrade Notes

Upgrade path followed:

    0.38.1 → 25.8.4 → 25.10.4 → 26.3.0

Sequential upgrades are required due to CRD evolution and changes in
replication and backup behaviour across versions

Replication configuration change (25.x):

  syncBinlog changed from boolean to integer

  Old:
    syncBinlog: true

  New:
    syncBinlog: 1

This change is handled by updated CRDs and typically requires no manual
action unless explicitly overridden in custom configurations

Helm values change (26.3.0):

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

CI workflow change (helm-mariadb-operator.yaml):

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

Pre-upgrade recommendations:
  * Validate existing backups and restore procedures
  * Review Helm values for image configuration compatibility
  * Ensure CSI drivers support VolumeSnapshots (if used)
  * Confirm Kubernetes version compatibility

Post-upgrade validation:
  * Verify cluster health and replication status
  * Validate backup job execution
  * Perform test restore (including PITR where applicable)
  * Review operator logs for reconciliation errors

#### Deprecations

Boolean-based replication configuration parameters have been removed.
Integer values are now required.

Legacy MaxScale components bundled within the operator have been removed.
MaxScale should be deployed and managed independently if required.

#### Critical Issues

Helm values format changes in 26.3.0 may cause upgrade failures or incorrect
image configuration if not updated prior to deployment.

Restore behaviour change for targetRecoveryTime may impact recovery outcomes.
Validation of restore workflows is strongly recommended.

Backup configuration errors, particularly with PhysicalBackup, may impact
recovery capabilities if not verified post-upgrade.

#### Bug Fixes

Fixes introduced between 25.8.1 and 25.8.4 include:
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

Improvements in the 25.10 series include:
  * Improved replication failover and replica recovery handling
  * Improved backup job generation and restore workflows
  * Improved S3 backup handling and support for SSE-C encryption
  * Improved Helm chart argument handling
  * Removal of legacy MaxScale components from the operator
  * Kubernetes 1.35 support

Improvements in 26.3.0 include:
  * Introduction of Point-in-Time Recovery (PITR)
  * Enhanced PhysicalBackup capabilities and storage integrations
  * Improved recovery logic for deterministic restore behaviour
  * General operator stability and reconciliation improvements
  * Continued dependency and Kubernetes compatibility updates

### Memcached

#### Prelude

Genestack will use openstack helm chart (https://github.com/openstack/openstack-helm/tree/master/memcached) instead of bitnami helm chart (https://github.com/bitnami/charts/tree/main/bitnami/memcached) for memcached from this release onwards. Currently genestack uses memcached version 1.6.39 in bitnami helm chart. However openstack-helm chart provides 1.6.32 version for memcached. So it will be a minor version downgrade from 1.6.39 to 1.6.32. However it will not impact anything on Openstack as openstack doesn't define any specific version of memcached to use in its documentation. Verified release notes in both 1.6.32 (https://github.com/memcached/memcached/wiki/ReleaseNotes1632) and 1.6.39 (https://github.com/memcached/memcached/wiki/ReleaseNotes1639) version, there are changes related to proxy and tls which is not used by the memcached used by openstack.

#### New Features

The env vars MEMCACHED_THREADS and MEMCACHED_MAX_ITEM_SIZE were used in
bitnami chart and openstack-helm chart don't provide that. So, kustomize
post renderer will be used to add those extra variables and include them
during installation.

#### Upgrade Notes

Service name of memcached is same "memcached.openstack.svc.cluster.local"
as previuos bitnami chart in openstack-helm memcached chart as it is used
by all openstack services. Hence, need to remove existing memcached
installed by bitnami in genestack before installing new memcached.
Then install memcached of openstack-helm using the usual installation
script.

#### Deprecations

Bitnami chart had persistence enabled for memcached. However openstack-helm
chart for memcached don't have persistence enabled.

#### Other Notes

Genestack no longer relies on bitami for memcached and will use
openstack-helm memcached instead.

### RabbitMQ

#### Prelude

Genestack aligns RabbitMQ for the 2026.1 Epoxy release by pinning the managed RabbitMQ image explicitly to the 4.1 series for predictable upgrades.

#### New Features

The base RabbitmqCluster manifest now pins `spec.image` to
`rabbitmq:4.1.4-management` so upgraded and fresh environments converge on
the same RabbitMQ server version.

#### Upgrade Notes

OpenStack Epoxy supports RabbitMQ 4.0 and 4.1, and Kolla-Ansible
recommends RabbitMQ 4.1 before or during Epoxy upgrades. Genestack now targets
RabbitMQ 4.1.4 for this release.

Upgrading the RabbitMQ Cluster Operator can trigger a rolling update of the
managed RabbitMQ StatefulSet. If rollout timing must be controlled, pause
reconciliation on the `RabbitmqCluster`, upgrade the operators, re-apply
the cluster manifest, and then resume reconciliation.

#### Deprecations

Genestack no longer relies on the operator default RabbitMQ image for the
Epoxy release path. The RabbitMQ server image is now pinned explicitly to
avoid unintended version drift and preserve idempotent upgrades.

#### Other Notes

Validation in lab confirmed the RabbitMQ cluster upgraded successfully to
4.1.4 and passed basic health checks including cluster status, local alarm
checks, StatefulSet readiness, PVC binding, and operator log review.

### Redis

#### Prelude

Redis Operator v0.24.0 adds IPv6 support for Redis Cluster client behavior,
expands Helm chart configurability, improves metrics exposure, and hardens
scaling, persistence, webhook, and cert-manager related workflows.

#### New Features

Added support for exposing Redis standalone using the service type defined
in `\1`.

Added IPv6 support for Redis Cluster client commands and mocks.

Added support for customizable annotations across Redis standalone,
RedisCluster, Sentinel, and RedisReplication chart resources.

Added Redis Exporter metrics service support for cluster, replication,
sentinel, and standalone deployments.

Added Sentinel support to the `\1` chart.

Updated Redis Helm charts to support additional already-implemented
properties.

#### Upgrade Notes

The mutating webhook configuration name now includes the Helm release name
prefix. This is a breaking change for environments that depend on the old
webhook naming convention.

Cert-manager based deployments should verify certificate material naming,
because the operator now expects `\1` instead of `\1` for the
affected startup path.

#### Bug Fixes

Fixed creation of empty PVCs when storage configuration contains only
`\1` entries.

Fixed chart logic for `\1` when using `\1` and
`\1`.

Fixed missing additional annotations on the replication headless service.

Fixed default leader and follower replica counts so they align with
`\1`.

Fixed ClusterRole aggregation into the admin role.

Fixed cert-manager startup failures by using `\1` instead of
`\1`.

Fixed PVC resize handling to skip shrink attempts.

Fixed initContainer behavior to respect `\1`.

Fixed a race condition involving the global `\1` variable.

Fixed RBAC namespace resource configuration.

Fixed RedisCluster scaling behavior to be resilient during failover and
while slots are open.

Fixed ACL SAVE behavior when ACL data is loaded from PVC.

Fixed scale-out behavior by waiting for node convergence and blocking
rebalance or add-node actions while cluster slots remain open.

Fixed webhook certificate secret lookup failures.

Fixed a typo in dashboard datasource configuration.

Fixed `\1` handling when
`\1` is enabled.

#### Other Notes

Updated documentation examples for `\1` indentation and
`\1` usage.

Refreshed architecture documentation and fixed minor documentation typos.

Updated several CI and linting dependencies, including
`\1`, `\1`, and
`\1`.

## Observability and Telemetry

### Observability Stack

#### Prelude

Genestack now utilizes Opentelemetry as a metrics, logging and tracing ecosystem. These changes touches the entirety of the monitoring and observability stack. The goal was to consolidate the related monitoring and observability tooling in to a more manageable and clean directory and namespacing structure.
This means that services/applications like Loki, Grafana, Prometheus(and its related tooling) have all been placed within the monitoring directory structure as well as migrated from various namespaces to a single 'monitoring' namespace. That means that these changes won't directly work against current deployments.
In order to properly structure things, a destructive tear down of the components is required. Loki, Prometheus(and any exporters), Grafana(and its database) needs to be completely uninstalled, including the PVC's. Metrics, and local logging will be lost during the migration process. Once all the components are removed a fresh install will bring everything back up functioning under the 'monitoring' namespace. Follow the related docs for more information.

#### New Features

- Utilizes Opentelemetry as the primary service for metrics, logging and
traces collection and exportation.
- Removes Fluentbit which is relplaced with an Opentelemetry receiver.
- Adds Tempo, a tracing backend that can be used within Grafana.
- Updates Loki with better tunings and log handling configurations.
- Removes and replaces several standalone Prometheus exporters with
Opentelemetry receivers. MariaDB, Rabbit, Memcached, Postgres and
Blackbox exporters have been removed and replaced.
- Migrates observability code to a monitoring directory and namespace.

#### Critical Issues

The upgrage to Opentelemetry and the refactored Observability stack
will cause data loss for metrics and logging. Be prepared to store data
in a external storage system or make a backup of the PVC if needed.

In order to properly structure things, a destructive tear down of the
components is required. Loki, Prometheus(and any exporters),
Grafana(and its database) needs to be completely uninstalled, including the
PVC's. Metrics, and local logging will be lost during the migration process.
Once all the components are removed a fresh install will bring everything
back up functioning under the 'monitoring' namespace.
Follow the related docs for more information.

### Ceilometer

#### Prelude

Genestack Ceilometer has been reviewed and aligned for the Epoxy (`2025.1`) upgrade path, with updated operator guidance around telemetry definition changes, deprecated settings, release-specific behavior, and validated dependency handling for Gnocchi-backed deployments.

#### New Features

Ceilometer `2025.1` adds broader telemetry coverage, including compute
pollster publication of `disk.ephemeral.size` and `disk.root.size`.

Ceilometer now exposes the `power.state` metric from `virDomainState`.

Metadata coverage is expanded in `2025.1`, including `storage_policy` for
Swift container telemetry and `volume_type_id` for volume notifications and
Gnocchi resources.

Ceilometer adds `[polling] ignore_disabled_projects`, which can reduce
polling overhead in environments with disabled projects.

#### Known Issues

The Epoxy highlights page does not include a dedicated Ceilometer section.
Cross-project context still matters: Watcher Epoxy highlights note removal
of the obsolete Ceilometer API datasource, which may affect operators with
older integration assumptions around Ceilometer APIs.

Ceilometer validation in Genestack depends on healthy Gnocchi API
endpoints, PostgreSQL indexer storage, and Ceph metric storage. If any of
those dependencies are absent, Ceilometer pods will remain in their init
dependency wait state.

#### Upgrade Notes

If your deployment overrides Ceilometer telemetry definitions, refresh
local `meters.yaml` and `gnocchi_resources.yaml` content for `2025.1`
before upgrade.

Dynamic pollster URL handling changed in `2025.1`: relative `url_path`
values are now appended to endpoint URLs. Review any custom dynamic
pollsters that relied on prior replacement behavior.

Upstream support was removed for Open Contrail, VMware vSphere, and
Python 3.8. Ceilometer `2025.1` now requires Python 3.9 or newer.

The following meters were removed upstream and should be removed from local
expectations or integrations if still referenced:
`cpu_l3_cache_usage`, `memory_bandwidth_local`,
`memory_bandwidth_total`.

Genestack now enables the Ceilometer `db-sync` job in the community
baseline. This matches the active chart dependency graph used by the
`central`, `compute`, and `notification` workloads and is required for a
clean startup sequence with Gnocchi-backed telemetry storage.

#### Deprecations

`[DEFAULT] hypervisor_inspector` is deprecated because libvirt is now the
only supported hypervisor inspector backend.

`[polling] tenant_name_discovery` is deprecated in favor of
`[polling] identity_name_discovery`.

#### Bug Fixes

Ceilometer `24.0.1` includes a libvirt inspector exception-handling fix for
`interfaceStats` (`Bug #2113768`), reducing failure noise during telemetry
collection.

## Kubernetes and Container Platform

### Magnum

#### New Features

Added comprehensive Cluster API (CAPI) support for Magnum, enabling modern
Kubernetes cluster lifecycle management with the following capabilities:

Management Cluster Installation:

- Kubespray-based management cluster deployment with HA configuration
- multi-node control plane with stacked etcd for high availability
- Kubernetes 1.32.0 support with containerd runtime
- Automated deployment via Ansible playbooks

Cluster API Components:

- CAPI core controller for cluster lifecycle operations
- OpenStack Provider (CAPO) for infrastructure provisioning
- Kubeadm bootstrap and control plane providers
- Cert-manager for TLS certificate management
- OpenStack Resource Controller (ORC) for declarative resource management
- Cluster API addon provider for extensions

Workload Cluster Provisioning:

- CAPI-based cluster templates with flexible configuration
- Support for multiple Kubernetes versions (example: v1.28.1, v1.32.0)
- Flatcar Container Linux and other Kubernetes-ready images
- Configurable node flavors for control plane and workers
- Automatic load balancer provisioning for control plane HA
- Floating IP support for external connectivity
- Calico network driver and Cinder volume driver integration

Cluster Management Operations:

- Dynamic cluster scaling (scale up/down worker nodes)
- Kubernetes version upgrades via CAPI
- Auto-healing for automatic node replacement on failure
- Auto-scaling with configurable min/max node counts
- Cluster deletion with automatic resource cleanup

Image Building:

- Kubernetes Image Builder integration for custom images
- QEMU-based image building with Packer
- Flatcar Container Linux with OpenStack OEM support
- Pre-installed Kubernetes components (kubeadm, kubelet, kubectl)
- Containerd runtime and CNI plugins
- Customizable Kubernetes versions in images

Monitoring and Verification:

- Comprehensive health checks for management cluster
- MariaDB Galera cluster status verification
- RabbitMQ cluster health monitoring
- Load balancer backend health verification
- DNS resolution testing
- Cluster API component status checks

#### Upgrade Notes

Magnum has been upgraded to version 2025.1.4 with native Cluster API driver
support. This is a breaking change that transitions from Heat-based cluster
provisioning to CAPI-based provisioning.

Key changes:

- Driver mechanism changed from Heat stacks to CAPI resources
- Faster cluster provisioning and better integration with CAPI ecosystem
- Native Kubernetes version upgrades through CAPI
- Enhanced security and compliance features
- Improved cluster lifecycle management

#### Deprecations

The magnum chart will now use the online OSH helm repository. This change
will allow the magnum chart to be updated more frequently and will allow
the magnum chart to be used with the OpenStack-Helm project. Upgrading to
this chart may require changes to the deployment configuration. Simple
updates can be made by running the following command:

```shell
helm -n openstack uninstall magnum
kubectl -n openstack delete -f /etc/genestack/kustomize/magnum/base/magnum-rabbitmq-queue.yaml
/opt/genestack/bin/install-magnum.sh

```
This operation should have no operational impact on running VMs but should be
performed during a maintenance window.

### Kube-OVN

#### Prelude

Genestack 2026.1 upgrades Kube-OVN from v1.13.14 to v1.15.4 using v1.14.15 as an intermediate step. Operators must restore Neutron-managed ACLs after upgrading to v1.14.15 before proceeding to v1.15.4.

#### New Features

Base Genestack now enables Kube-OVN garbage collection with
`\1`.

#### Upgrade Notes

Upgrade Kube-OVN in two stages:

1. Record the current Neutron-managed ACL count before beginning the
   upgrade:

   kubectl ko nbctl list acl | grep neutron:security_group_rule_id > \
     /tmp/neutron-security_group_rule_id.txt
   wc -l /tmp/neutron-security_group_rule_id.txt

2. Upgrade from Kube-OVN v1.13.14 to v1.14.15.

   Update `\1` and
   `\1` to reference v1.14.15 as needed for
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

Environments that currently disable Kube-OVN garbage collection with
`\1` should set a non-zero value when upgrading to
v1.15.4.

Base Genestack now sets `\1`. Environments that do
not override this value will inherit garbage collection behavior
from the base configuration.

The legacy `\1` override is no
longer used with Kube-OVN v1.15.x.

Operators who previously customized the VPC NAT gateway image using
`\1` should migrate to:

- `\1`
- `\1`

Environments that do not use Kube-OVN VPC NAT gateway functionality
are unaffected.

#### Deprecations

The legacy `\1` override path is
obsolete for Kube-OVN v1.15.x. See the upgrade section for the
replacement `\1` keys.

#### Critical Issues

In Genestack's shared-OVN deployment, where OpenStack and Kubernetes use the
same OVN Northbound database, upgrading Kube-OVN to v1.14.15 removes
Neutron-managed OVN ACL associations.

When this occurs, OpenStack security groups stop enforcing policy
until the OVN Northbound database is resynchronized from Neutron.

Operators must restore Neutron-managed ACLs after upgrading to
v1.14.15 and before continuing to v1.15.4.

## Networking and Load Balancing

### Designate

#### New Features

Added Designate is the DNS-as-a-Service (DNSaaS) component of Genestack.
It provides API-driven management of DNS zones and records, so tenants
and services can automatically create and update DNS entries as infrastructure changes.

#### Known Issues

The designate service cleaner is not functional at the moment as of Feb 2026, possibly fixed in 2026.2.
Added custom image in base helm overrides file to fix.

### Neutron / OVN

#### Upgrade Notes

Neutron OVN setting `localnet_learn_fdb` is now enabled to avoid flodding
on provider networks once port security is disabled.
See https://launchpad.net/bugs/2012069

### Octavia

#### Prelude

Octavia Epoxy (2025.1) adds support for SR-IOV member ports, VIP security
groups, and Taskflow jobboard enhancements.

#### New Features

Added support for SR-IOV virtual functions (VF) on Amphora member ports.

Added the `\1` parameter to the load balancer create API, allowing
operators to set user-defined Neutron security groups on the VIP port.

Added `\1` support to the Amphora driver. When set, Octavia applies
the specified security groups to the VIP port and manages only the required
VRRP and HAProxy peer rules. This does not work with SR-IOV ports because
Neutron security groups are not supported there.

Added support for the Taskflow Etcd jobboard backend.

Added the `\1` option to allow use of
a non-default Redis database for the jobboard backend.

#### Upgrade Notes

Amphora images must be updated to use the SR-IOV member port feature.

During upgrade, default RBAC rules switch from Octavia Advanced RBAC to
Keystone default roles. As a result, `\1` roles no longer
have access to the load balancer API unless the
`\1` override is applied.

UDP load balancers require a failover after the control plane is updated in
order to correct the UDP rebalance issue.

`\1` now builds Ubuntu Noble (24.04) Amphora images by
default.

#### Critical Issues

The default RBAC model changes during upgrade from Octavia Advanced RBAC to
Keystone default roles. Existing `\1` roles will lose API
access unless the advanced RBAC override policy is retained.

#### Security Notes

The RBAC default change to Keystone roles is less restrictive than Octavia
Advanced RBAC and removes some prior role scoping behavior, including global
observer and quota-specific roles.

#### Bug Fixes

Removed orphaned `\1` records on revert to avoid false-positive
failover threshold reactions.

Fixed a potential `\1` during listener update when a security
group rule has no protocol defined.

Fixed SINGLE topology UDP behavior by sending a gratuitous ARP when a UDP
pool is added, improving VIP reachability after failover or IP reuse.

Fixed verification of certificates signed by a private CA when using
Neutron endpoints.

Fixed error handling in `\1` revert when `\1` is not
defined and subnet lookup raises `\1`.

Fixed Amphora configuration updates so the health sender also receives the
updated controller IP list.

Fixed delayed UDP listener rebalance behavior where failed members could
remain in flows for up to five minutes.

Reduced the HAProxy SSL cache size for HTTPS termination listeners to help
prevent OOM conditions during reload.

Fixed L7Rule matching for `\1` with `\1` comparison.

Fixed missing `\1` in the `\1` response field.

Fixed a race condition during cascade delete of load balancers with multiple
listeners that could trigger concurrent VIP port security group updates.

Ignored the serialization load balancer class in
`\1` tasks to avoid storing full graphs in jobboard
details for very large load balancers.

Fixed an infinite database connection retry loop in the Octavia health
worker.

Drivers that fail to initialize are now properly removed from the enabled
driver list instead of remaining configured and causing API initialization
issues.

Fixed Octavia API startup so provider driver load failures are handled
gracefully and failing drivers are removed from the active enabled list.

#### Other Notes

Added an `\1` script for backward compatibility because pbr's
`\1` no longer functions with newer setuptools versions.

## Compute and Scheduling

### Blazar

#### Prelude

Blazar has been upgraded to OpenStack 2025.1 (Epoxy) release. This upgrade
brings important security fixes, policy enhancements with new RBAC roles,
and improved WSGI deployment capabilities. The Epoxy release focuses on
strengthening OpenStack's position as a VMware alternative while enhancing
security and operational capabilities.

#### New Features

**New WSGI Module**: A new module `\1` has been added to provide
a consistent location for WSGI application objects. This simplifies deployment
with modern WSGI servers like gunicorn and uWSGI by allowing module path
references (e.g., `\1`) instead of file paths.

**Enhanced RBAC Policies**: Blazar now implements scope-based policies with
new default roles (admin, member, and reader) provided by Keystone. All
policies now support `\1` capabilities with project-level scoping,
providing more granular access control while maintaining backward compatibility
with legacy admin roles.

**Instance Reservation Updates**: Fixed the ability to update the number of
instances in an instance reservation while the lease is active, improving
operational flexibility.

#### Upgrade Notes

**WSGI Script Removal**: The `\1` script has been removed.
Deployment configurations must be updated to reference the Python module
path `\1` for WSGI servers that support module
paths (gunicorn, uWSGI), or implement a custom `\1` script for
servers like mod_wsgi.

Example uWSGI configuration change:

```ini
# Old configuration
[uwsgi]
wsgi-file = /bin/blazar-api-wsgi

# New configuration
[uwsgi]
module = blazar.wsgi.api:application
```

**Policy Migration**: While old policy rules remain supported for backward
compatibility, operators should plan to migrate to the new scope-aware
policies. The legacy `\1` rule is deprecated in favor of
new role-based rules like `\1`, `\1`,
`\1`, and `\1`.

**Image Updates**: Blazar container images have been updated to version
`\1`. Ensure your helm overrides reference the correct image
tags as shown in `\1`.

#### Deprecations

**WSGI Script Deprecated and Removed**: The `\1` script
has been removed in Epoxy (15.0.0). Use the module path
`\1` instead.

**Legacy Policy Rules**: The following policy rules are deprecated and will
be silently ignored in future releases:

- `\1` - Use `\1` or `\1`
- Legacy `\1` references - Use new role-based rules

JSON-formatted policy files have been deprecated since Blazar 7.0.0 (Wallaby).
Use the `\1` tool to migrate to YAML format.

#### Security Notes

**Critical Lease Security Fix**: Resolved a security vulnerability (LP#2120655)
where any user could update or delete a lease from any project if they had
the lease ID. With default policy configuration, regular users cannot see
lease IDs from other projects. However, operators running the Resource
Availability Calendar with overridden policies may have been vulnerable
without this fix.

#### Bug Fixes

Fixed host randomization feature functionality (LP#2099927).

Fixed an issue preventing updates to the instance count in active instance
reservations (LP#2138386).

Resolved security vulnerability allowing unauthorized lease modifications
across projects (LP#2120655).

#### Other Notes

**Genestack Configuration**: The current Genestack configuration already
uses the `\1` image tags and includes proper RabbitMQ quorum
queue configuration with notification routing to Ceilometer for billing
integration.

**Python Version**: OpenStack Epoxy requires Python 3.9 as the minimum
supported version. Python 3.8 support has been removed across OpenStack
projects.

### Libvirt

#### Prelude

Libvirt upgrade from Caracal (2024.1) to Epoxy (2025.1). Helm chart changes
between 2024.2.94+912f85d38 and 2025.1.4+ed289c1cd.

#### New Features

Added support for configurable libvirt hooks via chart values:
`\1` and `\1`. Scripts are mounted into
`\1` in the libvirt container.

Added configurable exporter arguments under
`\1` so alternative exporter images can be
used when default `\1` arguments are not desired.

Added optional PodMonitor support with `\1` to expose
libvirt-exporter metrics to Prometheus Operator environments.

#### Known Issues

`\1` only has effect in clusters with the Prometheus
Operator CRDs installed, and useful metrics require
`\1`. Validate scrape target
discovery after enabling either setting.

#### Upgrade Notes

The libvirt exporter sidecar values schema changed from boolean to object.
Update overrides from:
`\1`
to:
`\1`
and optionally set `\1`.

New configurable probe values exist for libvirt-exporter under
`\1`. Existing
environments with strict startup timing may need probe tuning.

Ceph helper image default changed from
`\1` to
`\1`. Re-validate Ceph
keyring placement and compute startup behavior where Ceph-backed instances
are used.

For Caracal (2024.1) to Epoxy (2025.1), validate Nova/libvirt-driver
service-level changes in parallel with chart updates, including:
- minimum supported libvirt/QEMU levels in Epoxy;
- migration settings and TLS behavior under `\1`;
- cgroup v2 compatibility on compute hosts.

Override `\1` to the latest digest tag OR
override `\1` to `\1` to force upgrade
of libvirt daemonset.

#### Deprecations

Nova/libvirt-driver deprecates legacy incoming migration configuration
paths in favor of secure incoming migration settings. Review migration
config placement and TLS assumptions during Caracal to Epoxy if using
non-defaults.

#### Bug Fixes

The libvirt chart adds explicit readiness and liveness probe handling for
the `\1` sidecar, improving sidecar health reporting
behavior relative to prior defaults.

### Nova

#### Prelude

Nova upgrade from to Epoxy (2025.1). Helm chart changes between
2024.2.555+13651f45-628a320c and 2025.1.19+ed289c1cd.

#### New Features

Added chart support for Nova serial console proxy with new serialproxy
deployment, service, ingress, endpoint, TLS secret, and manifest toggles.

Added support for projected config sources mounted into
`\1` using `\1` to simplify
out-of-band config overrides.

Added optional Keystone service-account snippet secret (`\1`)
for injecting credential sections into `\1`.

Added runtime class and priority class hooks in pod templates for improved
scheduling and workload isolation customization.

#### Known Issues

Validate `\1` selector behavior
before production use of serial console; the service selector tuple appears
to use `\1` instead of `\1` and may fail to match pods if unpatched.

Secret handling by install-nova.sh fixed in:
[PR #1429](https://github.com/rackerlabs/genestack/pull/1429)

#### Upgrade Notes

Default compute API endpoint path changed from
`\1` to `\1`. Validate endpoint URL rewrite rules,
service catalog entries, and client assumptions.

New `\1` defaults were introduced and Nova cinder
auth settings are now more explicit (including `\1` default).
Validate cinder endpoint path/catalog assumptions during upgrade.

Nova service processes now consistently load ``--config-dir
/etc/nova/nova.conf.d`` in addition to the main config file. Ensure any
custom overrides are reconciled with the new snippet-loading behavior.

Check quota unified limits for resource classes without registered limits
when migrating from legacy quotas to unified limits quotas.
`\1` default is `\1`

Default identity usernames for service integrations now use
`\1` naming (for neutron, placement, cinder, ironic) and add a
dedicated `\1` identity. Legacy keystone users may
no longer be needed.

The new Nova helm chart iterates through endpoints.identity.auth
for user configuration. endpoints.identity.auth may require
modification/removal.

### Placement

#### Prelude

Placement upgraded to OpenStack 2025.1 (Epoxy) release.

#### New Features

Added `\1` module for simplified WSGI server deployment.

Added new configuration options:
`\1`,
`\1`, and
`\1` to improve
allocation candidate generation performance, particularly in
deployments with wide provider trees.

#### Upgrade Notes

Helm chart updated to `\1`.

Consider configuring `\1` and
`\1` for wide provider trees.

#### Bug Fixes

Fixed excessive memory consumption when generating allocation candidates
in deployments with wide provider trees.

## Identity and Secrets

### Keystone LDAP/AD

#### New Features

Add LDAP/AD Integration into Keystone config via genestack overrides file

### Keystone

#### Prelude

Keystone upgrade to Epoxy (2025.1) completed. Helm chart updated from 2024.2 to 2025.1.5+ed289c1cd with image updates to the 2025.1 stream. Helper container images migrated from heat to openstack-client.

#### New Features

Keystone images updated to 2025.1-latest stream
(ghcr.io/rackerlabs/genestack-images/keystone:2025.1-latest).

Helper container images (bootstrap, db_drop, db_init, ks_user,
keystone_credential_cleanup) migrated from legacy heat:2024.1-latest
to purpose-built openstack-client:latest image.

Upstream Keystone 2025.1 adds pagination support for user, group,
project, and domain listing via `limit` and `marker` query parameters.

New `keystone.wsgi` module provides a consistent WSGI application
location for simplified deployment with uWSGI or gunicorn.

#### Upgrade Notes

Helm chart version advanced from 2024.2 series to 2025.1.5+ed289c1cd.

Dependency on passlib library has been dropped upstream in favor of
using bcrypt and cryptography directly. Passwords hashed with passlib
are still supported but edge cases may require password rotation.

Python 3.8 support was dropped upstream. Minimum supported version
is now Python 3.9.

The templated catalog driver and `[catalog] template_file` option
have been removed upstream.

#### Deprecations

Removed deprecated `heartbeat_in_pthread` override from Keystone chart
values to align with oslo.messaging deprecation guidance.

Upstream deprecation: `[DEFAULT] max_param_size` option is deprecated
(was used for identity v2 API removed in 13.0.0).

Upstream warning: sha512_crypt password hashing support will be removed
in the next release (post-Epoxy). Users with sha512_crypt hashed
passwords should rotate their passwords before upgrading past 2025.1.

#### Security Notes

Upstream fix: Tokens for users disabled in read-only backends (LDAP)
are now properly invalidated. Previously, tokens continued to be
accepted after user disablement due to missing backend notifications.
See LP#2122615 for details.

#### Other Notes

Legacy heat helper images replaced with openstack-client to reduce
image sprawl and align with Genestack container strategy.

### Barbican

#### Prelude

Barbican Epoxy enablement and validation has been completed for Genestack using the OpenStack 2025.1 stream (Barbican 20.x). Deployment behavior, database connectivity requirements, and post-deploy secret workflows were verified in a hyperconverged lab environment.

#### New Features

Barbican API deployment for the 2025.1 image stream was validated in the
hyperconverged lab and confirmed operational for service endpoint access.

Basic Barbican secret lifecycle validation was completed successfully,
including secret store, metadata retrieval, payload retrieval, and delete.

#### Known Issues

Barbican client operations fail when Keystone key-manager endpoints point to
non-resolvable hostnames. Endpoint host/scheme values must match reachable
in-cluster service DNS and network paths.

#### Upgrade Notes

Barbican DB sync requires a resolvable MariaDB service hostname (for example
`mariadb-cluster-primary`) and valid DB credentials to complete migration.

During Epoxy validation, DB credential handling was confirmed through
Kubernetes secret injection via install workflow
(`endpoints.oslo_db.auth.*.password`) rather than static plaintext values.

Upstream Barbican 2025.1 release impacts were reviewed; runtime baseline
changes include removal of Python 3.8 support (minimum supported is 3.9).

#### Deprecations

Hardcoded plaintext database connection strings in Barbican Helm overrides
are deprecated for Genestack deployment workflows and should be replaced
with secret-driven credential injection.

Removed deprecated `heartbeat_in_pthread` override from Barbican chart
values to align with upstream deprecation guidance.

Upstream deprecation of `[p11_crypto_plugin] hmac_keywrap_mechanism`
(renamed to `hmac_mechanism`) was reviewed; this is currently not applicable
in this environment because HMAC/PKCS#11 flow is not enabled.

#### Security Notes

Secret-based DB credential handling was reinforced by using Kubernetes
secrets at deploy time instead of committing DB passwords in override YAML.

#### Bug Fixes

Fixed `barbican-db-sync` failures caused by invalid or unresolved database
endpoint/connection configuration during Epoxy deployment.

Fixed endpoint usage path for Barbican client operations so secret API calls
succeed without discovery/connection errors in the validated lab setup.

#### Other Notes

No additional critical release-specific risks were identified for this
Barbican Epoxy validation scope.

## Storage, Images, and Data Protection

### Freezer

#### Prelude

For more information about Freezer and upstream release notes, see: Freezer release notes at https://opendev.org/openstack/freezer/src/branch/master/releasenotes/notes and Freezer API release notes at https://opendev.org/openstack/freezer-api/src/branch/master/releasenotes/notes

#### New Features

Freezer provides comprehensive backup and restore capabilities for OpenStack
environments, supporting multiple backup types:

Backup capabilities:

- QCOW2 image based VM backup
- RAW image based VM backup
- Client local filesystem backup
- Client local LVM filesystem backup
- MySQL DB backup
- Mongo DB backup
- Cinder volume backup

Restore capabilities:

- QCOW2 image based VM restore
- RAW image based VM restore
- Client local filesystem restore
- Client local LVM filesystem restore
- MySQL DB restore
- Mongo DB restore
- Cinder volume restore

Added Freezer backup retention policy automation script that helps manage
Swift object lifecycle and container cleanup. The script provides automated
expiration management for Freezer backup containers stored in Swift.

Key features include:

- Set X-Delete-At headers on all objects in specified containers
- Flexible retention periods (seconds, minutes, hours, days, months)
- Automatic monitoring and deletion of empty containers
- Progress tracking with configurable check intervals
- Timeout protection to prevent indefinite execution
- Dry-run mode for testing
- Support for multiple containers in a single operation

The script is located at `\1`
and includes comprehensive documentation in the accompanying README.

Example usage:

```shell
# Set 7-day retention and auto-cleanup
./swift_retention_policy.py -c freezer-bkp-lvm -d 7 --cleanup

# Multiple containers with custom monitoring
./swift_retention_policy.py -c freezer-daily -c freezer-weekly \
  -H 1 --cleanup --check-interval 30
```

### Cinder

#### Prelude

Genestack Cinder has been updated for Epoxy (`2025.1`) with a focus on safer day-2 operations, cleaner defaults, and repeatable installs.

#### New Features

Cinder chart and image baselines were updated for the `2025.1` release
track.

Cinder helper jobs now use the `openstack-client` image family instead of
the legacy helper pattern, aligning Cinder with current Genestack tooling.

Community defaults keep Cinder disabled by default (`openstack-components`)
so users can opt in intentionally.

Upstream Cinder `26.0.0` adds the `cinder.wsgi` module for cleaner
WSGI app loading (for example `cinder.wsgi.api:application`), which
simplifies deployment patterns.

Upstream Cinder/Ceph adds a backup retention option to keep only the last
`n` snapshots per volume backup, reducing source-side Ceph snapshot growth.

Epoxy highlights call out Cinder Brick multipath setup/management
improvements and broad driver updates across common backends.

#### Upgrade Notes

If you use Fujitsu backends with password authentication, set
`fujitsu_passwordless = False`. In 2025.1 the default is `True`.

Existing environments that use `keystone_authtoken.auth_uri` should plan
to migrate to `www_authenticate_uri`.

Breaking change: generated global `endpoints.identity.auth` overrides are
no longer applied from hyperconverged common endpoint generation. If your
environment depended on that global block (for example custom service auth
region/user domain/project domain values), move those settings into
service-specific helm overrides before upgrade.

#### Deprecations

Remove deprecated iSER options from local overrides if still present:
`num_iser_scan_tries`, `iser_target_prefix`, `iser_ip_address`,
`iser_port`, `iser_helper`.

Pure Storage `queue_depth` is deprecated and is expected to be removed in
`2026.1`.

#### Bug Fixes

Cinder install/reinstall flows were validated in hyperconverged lab runs,
including a successful immediate rerun (`install-cinder.sh`) for
idempotency.

Cinder API and scheduler runtime validation showed healthy replicas and no
fatal runtime errors in sampled logs.

Upstream Cinder bug fixes directly relevant to operators include:
- `Bug #2105961`: NVMe-oF connector validation now checks `nqn` correctly.
- `Bug #2111461`: `cinder-manage` purge path fixed for FK constraint cases.
- `Bug #1907295`: attachment update failures now return `409` instead of
  generic `500` in invalid state paths.
- `Bug #2082587`: backup restore TypeError fix.

Upstream Ceph/RBD-related Cinder fixes include:
- RBD `Bug #2115985`: manage-volume fix for `multiattach` and
  `replication_enabled` type properties.
- NFS snapshot regression fix (`Bug #2074377`) and attached-volume snapshot
  metadata fix (`Bug #1989514`) included in the Epoxy cycle.

#### Other Notes

Known warnings seen during validation were limited to expected deprecation
signals (for example `auth_uri`) and did not block deployment.

### Glance

#### Prelude

Glance Epoxy (2025.1) focuses on safer image handling, predictable multi-store
download behavior, and stability fixes for policy initialization and RBD-backed
deployments. The release introduces stricter upload/import validation while
retaining operator controls for compatibility tuning.

#### New Features

Added image content inspection during upload/import to validate declared
`disk_format` against uploaded data.

Added configuration controls:
`[image_format]/require_image_format_match` and
`[image_format]/gpt_safety_checks_nonfatal`.

Updated `GET images` behavior to sort image locations by configured store
weight, affecting which backend location is preferred for download.

Extended stores detail API output for RBD backends to include `fsid`.

#### Known Issues

No explicit unresolved known issues were identified in the reviewed Epoxy
Glance note fragments; operators should still validate upload/import behavior
with real image sets due to stricter format checks.

#### Upgrade Notes

Support for running Glance services on Windows operating systems has been
removed.

Upload/import now checks content against `disk_format` by default; operators
should review current image pipelines and user workflows for format mismatch
failures and tune related image_format options as needed.

#### Deprecations

No new deprecations were explicitly called out in the reviewed Epoxy
Glance fragments.

#### Bug Fixes

LP #2081009: Fixed `oslo_config.cfg.NotInitializedError` when switching the
default `policy_file` in oslo.policy.

LP #2086675: Fixed suspected performance regression for RBD backends linked
to image location sorting behavior.

### Trove

#### New Features

Added Openstack Trove support.
Migrated Trove to use the official upstream OpenStack-Helm chart now that
it has been merged and is available in the upstream repository.

## Orchestration

### Heat

#### Prelude

The Heat chart configuration has been updated for the OpenStack-Helm 2025.2
line. This change aligns Genestack Heat overrides with chart removals and
current image defaults.

#### Upgrade Notes

The Heat CloudWatch API path is no longer supported by the chart.
CloudWatch manifests and related values have been removed from Heat
overrides.

Keystone user bootstrap behavior changed in upstream Heat chart logic:
`\1` now creates both `\1` and `\1` users.
Legacy `\1` job dependencies have been removed from
Genestack Heat overrides.

Heat and OpenStack client image overrides now use Genestack GHCR images:

- `\1`
- `\1`

Heat API and CFN liveness probe patches were updated to use port `\1`
to match stats-based probe behavior enabled by the current Heat chart.

#### Deprecations

CloudWatch-specific Heat override keys are no longer supported and should
not be used in custom overlays.
