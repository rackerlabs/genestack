# Release 2026.3.2

This release note set covers the exact git diff from `release-2026.3.1` to `release-2026.3.2-rc`.
Curated reno note fragments are listed first. Supplemental commit-derived items are listed separately afterward.

[Product Matrix](product-matrix-2026.3.2.md)

## Components

- [Platform Foundations](#platform-foundations)
- [Observability and Telemetry](#observability-and-telemetry)
- [Networking and Load Balancing](#networking-and-load-balancing)

## Additional Changes From Git History

These items were derived from commit history in the same tag range when no curated reno note was present.

- [Observability and Telemetry Git History](#observability-and-telemetry-git-history)
- [Kubernetes and Container Platform Git History](#kubernetes-and-container-platform-git-history)
- [Storage, Images, and Data Protection Git History](#storage-images-and-data-protection-git-history)
- [Orchestration Git History](#orchestration-git-history)
- [Other Git History](#other-git-history)

## Platform Foundations

### MariaDB Operator

#### Bug Fixes

- Aligned the MariaDB server idle-connection timeouts with the OpenStack service DB pool recycle intervals so that pooled connections are closed gracefully by the client pool before the server aborts them. The Galera MariaDB overlay previously set `wait_timeout=360` while every service's oslo DB pool held connections idle up to `connection_recycle_time=600`, so the server dropped idle pooled connections mid-read and logged `Aborted connection ... Got timeout reading communication packets` warnings. The service `use_db_reconnect` retry path healed the connection, but the server-side abort remained logged.

- Raised `wait_timeout` and `interactive_timeout` in the Galera MariaDB overlay (`base-kustomize/mariadb-cluster/galera/kustomization.yaml`) from 360 to 3600 to match the replication base (`base-kustomize/mariadb-cluster/base/mariadb-replication.yaml`). The replication base was already at 3600.

- The service `connection_recycle_time` (600) is intentionally left unchanged in the `database:` / `api_database:` / `cell0_database:` sections of all 17 OpenStack service Helm override files under `base-helm-configs/<svc>/<svc>-helm-overrides.yaml` (barbican, blazar, ceilometer, cinder, designate, freezer, glance, heat, ironic, keystone, magnum, masakari, neutron, nova (3 sections), octavia, placement, trove). With the server ceiling now at 3600s, the pool's existing 600s recycle interval closes idle connections gracefully long before the server ever aborts them.

#### Other Notes

- **Operator note:** these values take effect on the next rollout of the MariaDB `mariadb-cluster` pods and the affected service deployments. Existing pooled connections will not be re-evaluated until the pods are restarted. **Invariant:** the service `connection_recycle_time` must remain lower than the MariaDB `wait_timeout` / `interactive_timeout` for the pool to handle idle-connection cleanup gracefully. The current 600 / 3600 pairing keeps a conservative recycle interval well under the server ceiling. `pool_timeout` (60s) is the wait-for-free-connection timeout, not the idle timeout, and was intentionally left unchanged. The Grafana MariaDB cluster (`base-kustomize/grafana/base/grafana-database.yaml`) was already at 3600 and was not modified.

- **Known issue (pre-existing, unrelated to this change):** `reno lint` fails on a UID collision among three release notes added together in PR #1758 (commit `a600950`): `ops-tools-check-octavia-ovn-installer-release-2026.3.0.yaml`, `ops-tools-check-octavia-ovn-release-2026.3.0.yaml`, and `ops-tools-check-octavia-ovn-script-release-2026.3.0.yaml`. Reno's UID is the first 16 characters of the filename stem (when that slice contains a dash), and all three share the prefix `ops-tools-check-`, so reno sees them as the same note added in the same commit. The collision is baked into git history and cannot be fixed by a forward rename. A separate issue should be filed to either rewrite the historical commit or delete-then-readd the three notes under distinct names.

## Observability and Telemetry

### Observability Stack

#### Prelude

Migrating all observability components to a stand-alone repository.

#### New Features

- Removes all observability related services and components in favor of a stand-alone `genestack-observability` repo.

  Adds two new installation scripts to help enable the observability stack in Genestack. `bootstrap-observability.sh` and `install-observability.sh` are the entry points into all things Genestack Observability.

#### Upgrade Notes

- To upgrade; follow the documentation at `docs/monitoring-getting-started.md`. The Genestack repo will have removed all observability and monitoring related components and you must run `bootstrap-observability.sh` or follow the manual instructions to setup the new `genestack-observability` repo within your deployment.

## Networking and Load Balancing

### Neutron / OVN

#### New Features

- Genestack 2026.3.2 moves flavor-based network bandwidth enforcement from Nova/libvirt `quota:vif_*` extra specs to the Rackspace-designed Neutron `flavor_qos` plugin. Flavors now reference a Neutron QoS policy through the `flavor_qos:policy_id` extra spec, allowing Neutron to apply the corresponding bandwidth policy to instance ports throughout their lifecycle.

- Added the dry-run-first `ops-tools/flavor_qos_migration` utility. It creates the four flavor QoS policies, migrates flavor extra specs and Nova cached flavor data, updates existing compute ports, and records guarded rollback state for the 80 mapped regional flavors.

#### Upgrade Notes

- Existing deployments must perform the one-time cutover documented in `ops-tools/flavor_qos_migration/README.md`. Review the dry-run report, quiesce instance lifecycle operations, back up every affected Nova cell, and supply every cell database when applying the migration. The cutover removes the legacy `quota:vif_*` properties, installs `flavor_qos:policy_id` on the mapped flavors and cached instance flavors, and assigns the matching Neutron QoS policy to existing compute ports. The new policies enforce egress bandwidth; legacy inbound properties are removed without replacement. Nova's kB/s values are converted to Neutron kbps, with policy limits normalized to the documented `lite`, `plus`, `pro`, and `elite` tiers. Validate create, rebuild, resize, cold-migrate, and live-migrate behavior afterward with `ops-tools/flavor_qos_migration/VALIDATION.md`.

#### Bug Fixes

- `ops-tools/flavor_qos_migration` preflight now distinguishes live lifecycle state from stale Nova migration history. A non-terminal row in a cell database's `migrations` table no longer blocks an instance whose `vm_state` is stable and whose `task_state` is null; the row is reported as a stale-data warning in the text and JSON reports. An instance in `resized` state awaiting resize confirm or revert is refused explicitly, and the cached-flavor update transaction rechecks `task_state` and `vm_state` so a lifecycle operation starting after preflight rolls the transaction back. Cached resize `old` and `new` flavor objects are preserved; only the current flavor's `extra_specs` policy entry is changed.

## Observability and Telemetry Git History

### Observability Stack

- Fix: Updating missing observability gitignore entries (#1881) (#1882)

## Kubernetes and Container Platform Git History

### Kubernetes

- Fix lab_tenant_egress_snat_enabled to default to false (#1895) (#1898)

## Storage, Images, and Data Protection Git History

### Cinder

- Feature: configure cinder-rxt and virtualenv deployment (#1887)

### Trove

- Cherry picked Trove changes needed for LA: (#1884)

## Orchestration Git History

### Skyline

- Fix: set Skyline prometheus_endpoint to Prometheus in monitoring namespace (#1886)

## Other Git History

### Miscellaneous

- Docs: Suggest os-metrics user instead of admin for the metrics exporter (#1875)
