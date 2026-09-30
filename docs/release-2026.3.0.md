# Release 2026.3.0

This release note set covers the exact git diff from `release-2026.2.0.2` to `release-2026.3.0`.
Curated reno note fragments are listed first. Supplemental commit-derived items are listed separately afterward.

[Product Matrix](product-matrix-2026.3.0.md)

## Components

- [Platform Foundations](#platform-foundations)
- [Observability and Telemetry](#observability-and-telemetry)
- [Kubernetes and Container Platform](#kubernetes-and-container-platform)
- [Networking and Load Balancing](#networking-and-load-balancing)
- [Compute and Scheduling](#compute-and-scheduling)
- [Identity and Secrets](#identity-and-secrets)
- [Storage, Images, and Data Protection](#storage-images-and-data-protection)
- [Other Release Notes](#other-release-notes)

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

### Redis

#### Prelude

Octavia now uses Redis Sentinel endpoints.

#### New Features

- Added a "Redis Overview" Grafana dashboard (`etc/grafana-dashboards/redis_metrics.json`) for the Redis replication cluster. It surfaces up status, memory usage, connected clients, commands per second, keyspace hit ratio, total keys, evictions, connected replicas, and uptime.

- Redis replication metrics are now collected by the native OpenTelemetry `redis` receiver instead of a redis_exporter sidecar. A new `receiver_creator/redis` block in `base-helm-configs/opentelemetry-kube-stack/opentelemetry-kube-stack-helm-overrides.yaml` discovers the `redis-replication-<n>` pods on port 6379 through the `k8s_observer` extension and scrapes the Redis `INFO` command directly, matching how memcached, MariaDB and RabbitMQ are already collected.

- Added a `tcpcheck` receiver covering the Redis and Sentinel members. It emits `tcpcheck_status_ratio` and supplies the up/down signal that the `redis` receiver does not provide, replacing the redis_exporter `redis_up` gauge.

- Added a "Redis Sentinel" Grafana dashboard (`etc/grafana-dashboards/redis_sentinel_metrics.json`). It surfaces Sentinel up status, masters monitored, TILT state and TILT event rate, Sentinel script queue depth, connected clients, and uptime.

- Redis Sentinel metrics are now collected by the native OpenTelemetry `redis` receiver instead of a redis_exporter sidecar. A new `receiver_creator/redis_sentinel` block in `base-helm-configs/opentelemetry-kube-stack/opentelemetry-kube-stack-helm-overrides.yaml` discovers the `redis-sentinel-sentinel-<n>` pods on port 26379 through the `k8s_observer` extension and enables the receiver's optional `redis.sentinel.*` metrics.

#### Known Issues

- The OpenTelemetry `redis` receiver only parses the Sentinel `INFO` output and does not issue the `SENTINEL masters` command, so the per-master series that redis_exporter provides have no receiver equivalent: `redis_sentinel_master_status`, `redis_sentinel_master_ok_sentinels`, `redis_sentinel_master_ok_slaves`, `redis_sentinel_master_slaves` and `redis_sentinel_known_sentinels`. The dashboard reports the Sentinel-level signals the receiver does provide instead. Operators who need the per-master quorum and failover detail can still enable the redis_exporter alongside the receiver with a user override under `/etc/genestack/helm-configs/redis-sentinel/`; note that some metric names overlap between the two sources with different labels, so scope such queries by label. See `docs/infrastructure-redis.md`.

#### Upgrade Notes

- The `k8s_observer` extension is now scoped to both the `openstack` and `redis-systems` namespaces so the collector can discover the Redis pods.

- The redis_exporter sidecar and its `ServiceMonitor` stay disabled by default and are no longer required for the "Redis Overview" dashboard.

- Alerts or dashboards written against redis_exporter metric names need updating, because the OpenTelemetry receiver uses the OpenTelemetry semantic names: `redis_connected_clients` becomes `redis_clients_connected`, `redis_connected_slaves` becomes `redis_slaves_connected`, `redis_uptime_in_seconds` becomes `redis_uptime_seconds_total`, `redis_evicted_keys_total` becomes `redis_keys_evicted_total`, `redis_memory_max_bytes` becomes `redis_maxmemory_bytes`, `redis_instance_info{role="master"}` becomes `redis_role{role="primary"}`, and `redis_up` becomes `tcpcheck_status_ratio`. `redis_memory_used_bytes`, `redis_db_keys`, `redis_commands_processed_total`, `redis_keyspace_hits_total` and `redis_keyspace_misses_total` are unchanged. See `docs/infrastructure-redis.md`.

- The redis_exporter sidecar and its `ServiceMonitor` stay disabled by default and are no longer required for the "Redis Sentinel" dashboard.

#### Other Notes

- Octavia has been configured to use individual Redis Sentinel endpoints rather than the master replication service endpoint. This allows the redis client to better handle Redis communications while avoiding potential service endpoint outages.

## Observability and Telemetry

### Observability Stack

#### New Features

- Enabled the OpenTelemetry `httpcheck` receiver in the deployment collector metrics pipeline. The receiver probes each OpenStack service API and emits `httpcheck_*` metrics (keyed by the `http_url` label) recording whether the endpoint returns an HTTP response. The receiver targets default to the in-cluster service endpoints, which the collector can always reach; both internal and public API endpoints are supported, so operators can add or replace targets with their service-catalog public URLs (or keep both in the list) in `base-helm-configs/opentelemetry-kube-stack/opentelemetry-kube-stack-helm-overrides.yaml`.

- Added an "OpenStack API URLs" Grafana dashboard (`etc/grafana-dashboards/openstack_api_urls_metrics.json`) that surfaces per-URL response status, overall availability, HTTP check duration, and the latest HTTP status code returned by each OpenStack API, using the `httpcheck_*` metrics.

- Added Grafana dashboards for infrastructure services whose metrics already flow through the OpenTelemetry stack but previously had no visualization: cert-manager (certificate validity and expiry), MetalLB (address pool utilization and BGP/BFD session state), CoreDNS (query/response rates, latency, and cache efficiency), and the Kubernetes control plane (API server, scheduler, controller-manager workqueues, and etcd).

## Kubernetes and Container Platform

### Kube-OVN

#### Bug Fixes

- Neutron now reads Kube-OVN's effective `networking.ENABLE_SSL` Helm value. When enabled, the installer synchronizes the Kube-OVN client certificate, uses SSL for all northbound and southbound database connections, and mounts the certificate only into Neutron workloads that connect to OVN. Non-SSL deployments continue to use TCP without rendering OVN TLS mounts or certificate settings.

- Octavia now reads Kube-OVN's effective `networking.ENABLE_SSL` Helm value before configuring the OVN provider. When enabled, the installer synchronizes the Kube-OVN client certificate, uses SSL for the northbound and southbound database connections, and mounts the certificate into the Octavia API, worker, and OVN driver-agent containers. Non-SSL deployments continue to use TCP without rendering OVN TLS secrets, mounts, or certificate settings.

## Networking and Load Balancing

### Designate

#### New Features

- Extended Designate capability to Neutron. Allow Designate to create PTR and A records from VMs that have a network ports with dns_domain flag. This allows direct integration with Neutron to allow records create/update for network ports and floating IPs.

#### Bug Fixes

- fixed templates and overrides in designate to allow for BIND9 server config with rndc.key file.

### Neutron / OVN

#### New Features

- Added Neutron VPNaaS with OVN deployment documentation covering gateway node selection, Neutron RPC server enablement, deployment validation, and troubleshooting. The node-label reference now includes the dedicated `openstack-ovn-vpn-agent=enabled` label.

- Documents `ops-tools/check_octavia_ovn/install_check_octavia_ovn_systemd.sh` for Genestack 2026.3.0. The installer deploys the Octavia/OVN checker as a systemd-managed workflow and carries the explicit remediation confirmation required by the ops tools standard.

- Added release coverage for `ops-tools/check_octavia_ovn`, an operator tool that audits Amphora load balancer VIP port bindings in OVN and can fail over unhealthy load balancers when explicitly run in apply mode.

- Documents `ops-tools/check_octavia_ovn/check_octavia_ovn.sh` for Genestack 2026.3.0. The script audits Amphora VIP port bindings in OVN, runs dry by default, supports apply mode for load balancer failover, and now requires `--yes-im-really-sure` before performing state-changing remediation.

- Adds `ops-tools/ovn/ovn_compare_neutron_fips_with_ovn_nat.py` for Genestack 2026.3.0. The Python scanner compares assigned Neutron floating IPs with OVN `dnat_and_snat` NAT rows, reports missing or stale NAT state, and can remove stale OVN NAT rows with explicit fix confirmation.

- Adds a suspended Kubernetes CronJob manifest for read-only JSON floating IP/NAT comparison scans with one-week finished Job retention.

- Adds `ops-tools/ovn/ovn_compare_neutron_ports_with_ovn_ports.py` for Genestack 2026.3.0. The Python scanner compares Neutron ports, excluding floating IP ports, with OVN logical switch ports and can delete stale logical switch ports with explicit fix confirmation.

- Adds a suspended Kubernetes CronJob manifest for read-only JSON Neutron port/OVN port comparison scans with one-week finished Job retention.

- Adds `ops-tools/ovn/ovn_compare_neutron_routers_with_logical_routers.py` for Genestack 2026.3.0. The Python scanner compares Neutron routers and router ports with OVN logical routers and logical router ports, reporting missing state and optionally deleting stale OVN router resources.

- Adds a suspended Kubernetes CronJob manifest for read-only JSON Neutron router/OVN router comparison scans with one-week finished Job retention.

- Adds `ops-tools/ovn/ovn_compare_neutron_security_groups_with_acl.py` for Genestack 2026.3.0. The Python scanner compares Neutron security groups and rules with OVN port groups and ACLs, reporting missing state and optionally deleting stale OVN security resources.

- Adds a suspended Kubernetes CronJob manifest for read-only JSON Neutron security group/OVN ACL comparison scans with one-week finished Job retention.

- Adds `ops-tools/ovn/find_ovn_duplicate_ip.py` for Genestack 2026.3.0. The Python scanner finds duplicate Kube-OVN IP CRD addresses and reports whether each referenced pod still exists.

- Adds a suspended Kubernetes CronJob manifest for read-only JSON duplicate IP CRD scans with one-week finished Job retention.

- Adds `ops-tools/ovn/find_ovn_stale_ip_crd.py` for Genestack 2026.3.0. The Python scanner finds Kube-OVN IP CRDs whose referenced pods no longer exist and can delete stale CRDs only when run with `--fix --yes-im-really-sure`.

- Adds a suspended Kubernetes CronJob manifest for read-only JSON stale IP CRD scans with one-week finished Job retention.

- Adds the `ops-tools/ovn` tool directory for Genestack 2026.3.0 with Python rewrites of the legacy OVN/Neutron consistency shell scripts. The migrated tools provide read-only defaults, structured JSON output, command timeouts, explicit destructive-action confirmation, and focused unit tests.

- Adds suspended Kubernetes CronJob manifests for each OVN ops tool, running read-only JSON scans with one-week finished Job retention.

#### Upgrade Notes

- Environments enabling VPNaaS must apply `openstack-ovn-vpn-agent=enabled` only to OVN gateway chassis, configure the OVN VPN agent node selector to use that label, and enable the `neutron-rpc-server` deployment. The VPN agent must not use the broader `openstack-network-node` label because ordinary compute nodes can carry that label without being OVN gateway chassis.

#### Other Notes

- Documented the `check_octavia_ovn` systemd deployment, state file, timer behavior, dry-run mode, retry settings, and logging workflow as part of the ops tools shipped with Genestack 2026.3.0.

- Aligned apply mode with the ops tools remediation standard by requiring `--yes-im-really-sure` for failover/state changes and carrying that explicit confirmation in the packaged systemd unit.

### Octavia

#### New Features

- `bin/create-secrets.sh` now generates a per-cluster unique Octavia health manager heartbeat key and stores it in the `octavia-heartbeat-key` secret (namespace `openstack`, key `heartbeat_key`). `bin/install-octavia.sh` renders it into the chart via `conf.octavia.health_manager.heartbeat_key`, replacing the openstack-helm chart default (the static, well-known value `insecure`).

#### Upgrade Notes

- On a fresh install the key is generated automatically. On an existing cluster `create-secrets.sh` does not regenerate an already-present `/etc/genestack/kubesecrets.yaml`, so backfill manually:

  .. code-block:: shell

  KEY=$(openssl rand -base64 48)
  kubectl -n openstack create secret generic octavia-heartbeat-key \
    --from-literal=heartbeat_key="$KEY"
  /opt/genestack/bin/install-octavia.sh \
    --set "conf.octavia.health_manager.heartbeat_key=$KEY"

  This is a `helm upgrade` of Octavia; only the Octavia control-plane pods (api, worker, health-manager) roll.

  The heartbeat key authenticates the UDP heartbeats that *amphorae* send to the health manager. For OVN-driver deployments there are no amphorae, so changing the key has no data-plane impact on load balancers. For amphora-driver deployments a one-shot rekey would cause the health manager to drop every running amphora's heartbeat and trigger a fleet-wide mass failover; perform that only within a maintenance window with coordinated amphora rekeying.

## Compute and Scheduling

### Ironic

#### Prelude

Genestack `release-2026.1` deploys Ironic from the OpenStack 2026.1 series. Ironic 35.0 is a SLURP release and supports a direct upgrade from OpenStack 2025.1 (Ironic 29.0). This series adds trait-based networking, automatic deploy-interface selection, improved Redfish inspection and virtual-media support, and substantial API and deployment security hardening.

#### New Features

- Genestack now enables periodic collection of Ironic conductor and bare-metal hardware sensor data, including deployed and undeployed nodes. An `ironic-prometheus-exporter` sidecar in every conductor pod exposes the collected metrics on port 9608 through a dedicated Kubernetes Service. An optional OpenTelemetry receiver can discover ready exporter endpoints and forward their metrics to the configured monitoring backend; the standard monitoring configuration also checks availability of the public Ironic API.

- The new `autodetect` deploy interface selects `ramdisk`, `bootc`, or `direct` from image metadata and node configuration. Both `autodetect` and `bootc` are enabled by default, and `ramdisk` can now consume a single suitably annotated Glance image.

- Trait-based networking can dynamically select ports and portgroups for network attachment, including creating portgroups as needed. REST API microversion 1.111 adds `available_for_dynamic_portgroup` to ports and the read-only `dynamic_portgroup` field to portgroups.

- The experimental `ironic-networking` service provides switch configuration through `networking-generic-switch` for standalone Ironic deployments that do not use Neutron. OpenStack-integrated deployments also gain VXLAN support and support for multiple physical switches.

- Redfish virtual-media boot now supports NFS and CIFS/SMB in addition to HTTP. Ironic detects the transports advertised by the BMC, while operators remain responsible for providing a share reachable by the BMC.

- Redfish out-of-band inspection now collects storage-controller, drive, LLDP, port-speed, manufacturer, model, system UUID, and hardware-health information. The `health` node field is exposed from API microversion 1.109 and is updated during periodic power synchronization for drivers that implement health monitoring.

- Cleaning and servicing flows can skip IPA automatically when every step declares `requires_ramdisk=False`. Redfish BIOS configuration can poll `BootProgress` and verify settings without booting IPA, and Redfish firmware updates no longer require an in-band agent afterward.

- API microversion 1.110 permits aborting a deployment in `DEPLOYWAIT`. Deploy steps can declare whether they are abortable, matching clean and service steps.

- Operators can load custom WSGI middleware through the `ironic.api.middleware` entry-point namespace. Ironic 35.1 also adds middleware that rejects JSON bodies exceeding configurable size or nesting limits before parsing them.

#### Known Issues

- Changing a node's `owner` does not update its parent or child nodes. Operators must keep ownership consistent across related nodes; the upgrade check warns when a node and its parent have different owners.

- NIC firmware inventory can be absent for newly enrolled nodes when a BMC only exposes `NetworkAdapters` while the node is powered on. Validate inventory after powering on or running the applicable cleaning or service workflow.

#### Upgrade Notes

- Ironic now requires MySQL 8.0 or later, or MariaDB 10.3 or later, and converts all existing tables from `utf8mb3` to `utf8mb4` during `ironic-dbsync upgrade`. Each table is locked while it is rewritten. Plan control-plane downtime and test the migration against a copy of the production database to estimate its duration, especially for large deployments.

- Ironic Python Agent versions without in-band deploy-step support are no longer compatible. Update old IPA kernel and ramdisk images before the control-plane upgrade.

- Genestack sets `[api]ramdisk_heartbeat_timeout=3600`, increasing the maximum interval between Ironic Python Agent heartbeats from the upstream default of 300 seconds. Account for the longer failure-detection window in monitoring and automation; it accommodates long-running deployment and provisioning operations that would otherwise time out.

- The default `[DEFAULT]autodetect_deploy_interfaces` value is now `ramdisk,bootc,direct`. Where `autodetect` is used, a Glance image with ramdisk metadata can therefore select the `ramdisk` interface without an explicit local override. Pin the option if the previous selection behavior must be retained.

- Do not leave Redfish BIOS clean or service steps in progress during the upgrade. The internal state changes to the structured `redfish_bios_state` format. Ironic cleans up state from an operation started by the old code when the next BIOS step is invoked.

- The deprecated `inspector` inspect interface has been removed. Migrate nodes and configuration to the built-in `agent` inspection interface before upgrading.

- Shellinabox support has been removed, including the `ipmitool-shellinabox` console interface, the node web console that depended on it, and the iLO `console` interface. Unset an explicitly configured `console_interface` on affected iLO nodes and migrate console workflows to a supported provider.

- Existing ports receive `available_for_dynamic_portgroup=True` and existing portgroups receive `dynamic_portgroup=False` when the API 1.111 schema migration is applied. Review these defaults before enabling trait-based networking on existing inventory.

- Generic Redfish inspection no longer stores `sku` in `system_vendor`. Dell service tags are reported as `serial_number` by the `idrac-redfish` inspection interface. Update inspection rules or external consumers that depend on the old field.

- The `ilo` console and inspector removals, database migration, deploy interface defaults, and all security-related configuration changes should be validated in a staging environment before conductors are upgraded.

#### Deprecations

- The node `driver_info` value `pxe_template` is deprecated and is expected to be removed in Ironic 2027.2. Absolute-path template overrides are also disabled by default for security reasons; remove these overrides instead of enabling the compatibility option.

- The Fujitsu `irmc` hardware type, all iRMC-specific interfaces, and the `[irmc]` configuration options are deprecated. Operators should plan a migration to a supported hardware type.

- Using `ironic.api.wsgi:initialize_wsgi_app` to select a custom configuration file is deprecated. Use `IRONIC_CONFIG_DIR` and `IRONIC_CONFIG_FILE` instead.

- The unused `[drac]config_job_max_retries` and `[drac]bios_factory_reset_timeout` options are deprecated following the earlier removal of the iDRAC WSMAN interfaces.

#### Critical Issues

- The mandatory `utf8mb4` database conversion rewrites and locks every Ironic table. Do not treat this as an online migration: schedule downtime, verify the database server version and row-format support, take a tested backup, and measure the migration against production-like data first.

#### Security Notes

- Genestack now requires TLS for communication with Ironic Python Agent by setting `[agent]require_tls=True` and `[agent]verify_ca=True`. Callback URLs without `https://` are rejected. Auto-generated certificates used to validate ramdisk connections are stored in `[agent]certificates_path=/var/lib/ironic/certificates`. Ensure custom IPA images and site overrides support TLS and preserve access to this directory before upgrading.

- Ironic 35.1 includes fixes for ISO9660 path traversal (CVE-2026-48681), unvalidated `file://` image sources that could exhaust conductor workers (CVE-2026-44919), PXE template path overrides (CVE-2026-44917), and boot script injection through `kernel_append_params` (CVE-2026-46447). Strict kernel-parameter parsing is enabled by default and should not be disabled.

- The `ipmitool` vendor-passthru `send_raw` method is disabled by default. Ironic recommends Redfish where possible; do not re-enable raw IPMI access without a documented operational need and compensating access controls.

- IPA BIOS bootloader installation can be disabled with `enable_bios_bootloader_install=False` to reduce exposure addressed by CVE-2026-43003. The option remains `True` by default on this stable branch for compatibility, so security-sensitive deployments must opt out.

- API authorization now prevents cross-project parent-node relationships and reassignment of ports, portgroups, volume targets, and volume connectors across node owners. Portgroup shard queries also apply owner and lessee filtering.

- JSON body size and depth limits protect API workers from memory exhaustion and recursion crashes. Review `[api]max_json_body_size`, `[api]max_json_body_size_provision`, `[api]max_json_body_size_inspection`, and `[api]max_json_body_depth` if clients submit unusually large payloads.

- The noVNC security proxy now bounds server-supplied failure reasons to prevent a malicious BMC-side VNC server from exhausting proxy memory. Volume-target responses also mask password-like iSCSI properties independently of RBAC policy enforcement.

#### Bug Fixes

- Redfish firmware and BIOS updates receive more reliable task-state handling, stabilization checks, timeout controls, reboot behavior, and Dell iDRAC lifecycle-job detection. Power synchronization no longer interrupts an in-progress firmware update.

- Redfish boot and power handling is more tolerant of BMC differences, including full boot-parameter requests, transient power-on conflicts, changes attempted during POST, missing Storage APIs or Volumes links, and virtual-media slots without `InsertMedia` support.

- Inspection fixes cover MAC-address normalization, inspection-rule variable interpolation, `network.tags` evaluation, missing inventory fields, cleanup of inspection VIFs on failure, fast-track heartbeats, and graceful shutdown before virtual-media ejection.

- Image handling now validates URLs before checksum calculation, streams checksums while downloading large images, uses practical download chunk sizes, supports secure Glance hashes, and correctly copies cached images across filesystems or reuses an existing hard link.

- Networking fixes prevent orphaned Neutron ports for iPXE interfaces, preserve physical-network consistency between ports and portgroups, use service credentials for Neutron operations, and correctly unplug VIFs when Nova reschedules a bare-metal instance.

- API fixes cover field-level RBAC decisions when callers request a limited field set, masked volume-target update responses, portgroup shard filtering, read-only virtual-media queries under concurrent operations, and node deletion races that previously returned a misleading HTTP 409.

#### Other Notes

- Review the complete upstream Ironic 2026.1 series [release notes](https://docs.openstack.org/releasenotes/ironic/2026.1.html) before upgrading. The upstream page includes hardware- and driver-specific changes that may apply to site-specific BMCs, out-of-tree drivers, inspection rules, and firmware workflows beyond the Genestack highlights above.

## Identity and Secrets

### Barbican

#### Prelude

Barbican in Genestack now supports SoftHSM2-backed PKCS#11 (`p11_crypto`) as the primary crypto backend for encrypting all new secrets, while retaining `simple_crypto` as a secondary read-only backend to ensure existing legacy secrets remain accessible. Additionally, deployments with Barbican Gazpacho (2026.1 / OpenStack-Helm 2026.1.x) feature fully automated SoftHSM2 PIN generation. The `simple_crypto` master KEK, which Gazpacho no longer defaults, is managed through the `barbican-simple-crypto-kek` Kubernetes Secret; see the Barbican KEK notes in this release and the "Simple crypto master KEK" section of `docs/openstack-barbican.md`.

Barbican's simple_crypto master key-encryption-key (KEK) can now be managed through Kubernetes instead of Helm override files. Unless an override file sets the KEK, which always takes precedence, the KEK is read at deploy time from the `barbican-simple-crypto-kek` Kubernetes Secret and injected by `install-barbican.sh`; rotation is planned and staged with `scripts/rotate-barbican-kek.py` and executed by the OpenStack-Helm db-sync KEK rewrap. This applies to the OpenStack-Helm 2026.1.x barbican charts, the OpenStack Gazpacho stream; see `helm-chart-versions.yaml`. SoftHSM2-backed PKCS#11 (`p11_crypto`) is the primary crypto backend in this release, with `simple_crypto` retained to read existing secrets (see the Barbican PKCS#11 notes). The KEK requirements below apply regardless.

#### New Features

- **SoftHSM2 PKCS#11 Crypto Backend Support:** Integrated SoftHSM2 as a PKCS#11 HSM crypto plugin (`p11_crypto`). All new secrets created in Barbican are encrypted using SoftHSM2 PKCS#11, while existing secrets previously encrypted via `simple_crypto` remain readable via dual-plugin operation (`p11_crypto` + `simple_crypto`).

- **SoftHSM2 Token Persistence & Pod Configuration:** Added `barbican-softhsm-config` ConfigMap and `barbican-softhsm-tokens` PVC (`ReadWriteMany`) to `base-kustomize/barbican/base/kustomization.yaml`, ensuring SoftHSM2 configuration (`/etc/softhsm/softhsm2.conf`) and token storage (`/var/lib/softhsm/tokens`) persist across pod restarts and multi-replica deployments.

- **Cluster Bootstrap Secret Provisioning (bin/create-secrets.sh):**
Updated `bin/create-secrets.sh` to auto-generate and persist all required
Barbican credentials in Kubernetes Secrets at cluster bootstrap:
- `barbican_hsm_pin`: 32-character auto-generated PIN stored in the
  `barbican-hsm-credentials` Kubernetes Secret for SoftHSM2 PKCS#11 token login.
- `barbican_simple_crypto_kek`: 32 random bytes as urlsafe base64 (44
  characters), the Fernet master KEK, stored in the
  `barbican-simple-crypto-kek` Kubernetes Secret alongside
  an initially empty `old_keks` rotation history, for greenfield and fresh
  lab builds.

- **Updated Install Script (bin/install-barbican.sh):** `install-barbican.sh` handles SoftHSM2 configuration checks, creation of the `barbican-hsm-credentials` Secret on brownfield clusters, dynamic PIN injection from that Secret, post-install token/key initialization, and injection of the `simple_crypto` master KEK from the `barbican-simple-crypto-kek` Secret.

- **Default dual-plugin enablement:** `base-helm-configs/barbican/barbican-helm-overrides.yaml` now enables `p11_crypto` then `simple_crypto` (oslo MultiStrOpt), SoftHSM2 library path, token label, volume mounts, and `runAsUser`/`fsGroup` 42424. Regional overrides no longer need to turn p11 on; they only need to keep `simple_crypto` loaded until legacy secrets are converted.

- `create-secrets.sh` now generates a 44-character Fernet-format KEK from 32 random bytes (`generate_fernet_token`) and stores it in the `barbican-simple-crypto-kek` Kubernetes Secret, alongside an initially empty `old_keks` rotation-history data key. New greenfield regions therefore start on a unique, region-specific KEK instead of the publicly documented upstream default.

- `install-barbican.sh` injects the KEK from the `barbican-simple-crypto-kek` Secret via `--set-string` (validated as a 44-character Fernet key; malformed values abort the deploy) and the `old_keks` history via `--set-string` into `conf.simple_crypto_kek_rewrap.old_kek`, unless an override file sets `conf.barbican.simple_crypto_plugin.kek`.

- `install-barbican.sh` resolves the KEK situation before every deploy instead of letting a missing KEK surface as crashlooping `barbican-api` pods. A KEK set in an override file (`conf.barbican.simple_crypto_plugin.kek`) always takes precedence: it is deployed as is, nothing is injected and no Secret is written. Otherwise, when the `barbican-simple-crypto-kek` Secret exists, it is injected. When neither supplies a KEK, the script counts the simple_crypto project keys in `barbican.kek_data` (read-only, on the MariaDB primary): if any exist (an upgrade of a running Barbican whose KEK is managed nowhere) it refuses to deploy and points at `rotate-barbican-kek.py --adopt` to move the running KEK into the Secret; if none exist (first Barbican install on an existing cluster, or recovery from a first install that crashlooped) it generates a fresh KEK into the Secret, the same as `create-secrets.sh` does on greenfield. When the Secret holds a KEK that differs from the deployed one, the deploy proceeds (with a rotation warning) only if the deployed KEK is listed in the Secret's `old_keks`, which `rotate-barbican-kek.py --stage` always records, or when `barbican.kek_data` holds no simple_crypto project keys yet; otherwise it refuses, since the db-sync rewrap could not succeed. The upstream default is not treated as covered, so a fresh Secret applied to a running region cannot rotate its KEK by accident: rotations of a Secret-managed KEK happen only through `--stage`. A KEK from an override file gets no such check; on that path the chart's db-sync rewrap is the only safeguard, and it fails the deploy rather than losing data. The Secret in the cluster is authoritative for environments without a KEK override: a stale copy of it in `/etc/genestack/kubesecrets.yaml` that is re-applied later is caught by that same guard on the next deploy. `install-barbican.sh` never calls `rotate-barbican-kek.py`.

- Added `scripts/rotate-barbican-kek.py`: plans (dry-run, read-only), stages (`--stage`), or adopts (`--adopt`) KEK rotations, and verifies KEKs against the database (`--validate deployed|staged|<kek>`). Every staged rotation is first proven to cover the keys actually wrapping the `kek_data` rows, and a staged-but-undeployed rotation is protected from being overwritten.

#### Known Issues

- The OpenStack-Helm 2026.1.x barbican chart's `values.yaml` still contains a comment stating that barbican falls back to a well-known default when no kek is provided. That comment is stale: the Gazpacho barbican service removed the default (`kek` defaults to an empty list and plugin initialization raises `SimpleCrypto KEK is undefined`). Trust the service behavior, not the chart comment.

#### Upgrade Notes

- **Gazpacho KEK handling:** Gazpacho Barbican removes the upstream built-in default KEK for `simple_crypto`. A KEK set in an override file always takes precedence and is deployed as is. Otherwise `install-barbican.sh` injects the KEK from the `barbican-simple-crypto-kek` Secret on every deploy. On brownfield clusters that hold `simple_crypto` data but have no KEK configured anywhere, it refuses to deploy and points at `scripts/rotate-barbican-kek.py --adopt` to move the running KEK into the Secret; on clusters without Barbican data it generates one, so fresh deployments create Trove instances and encrypted Cinder volumes without manual steps. A deploy that would leave Barbican unable to start, or that would arm a db-sync rewrap of a Secret-managed KEK that cannot succeed, is refused with guidance instead. Rotation is handled by `scripts/rotate-barbican-kek.py`, which `install-barbican.sh` never calls; see the Barbican KEK notes in this release.

- **Gazpacho Barbican requires an explicit KEK.** The simple_crypto plugin no longer falls back to the built-in well-known default: if no kek is rendered into `barbican.conf`, barbican fails to start with `SimpleCrypto KEK is undefined`. Environments that already set a KEK in their Helm overrides need no changes: the override is deployed as is. Environments that never set one — previously running implicitly on the well-known default — must put that KEK under Secret management before the upgrade by running `scripts/rotate-barbican-kek.py --adopt`, which validates the currently deployed KEK against the database from inside the `barbican-api` pod and stores it in the `barbican-simple-crypto-kek` Secret (no rotation occurs). `install-barbican.sh` refuses to deploy an environment that holds Barbican data while neither supplies a KEK, rather than leaving `barbican-api` crashlooping. Adoption requires a running `barbican-api` pod for database validation: run it from a healthy state. If a Gazpacho deploy has already crashlooped without a KEK on an environment that holds Barbican data, `helm rollback` to the last good revision, adopt, and re-run `install-barbican.sh`; on an environment with no simple_crypto project keys yet (a first install), simply re-run it and a fresh KEK is generated. Do not create the Secret by hand and do not expect `create-secrets.sh` to configure Barbican on an existing environment: on an environment without a KEK override, a Secret whose value is not coordinated with the deployed KEK becomes the KEK on the next deploy, and `install-barbican.sh` will refuse to deploy it unless `old_keks` covers the deployed KEK.

- To rotate an existing environment off the upstream well-known default KEK: run `scripts/rotate-barbican-kek.py` (dry run), review, re-run with `--stage`, **back up the Barbican database**, then run `install-barbican.sh` — the db-sync job performs a one-way rewrap of all project KEKs. Afterward `rotate-barbican-kek.py --validate deployed` must pass and the db-sync logs must show zero rewrap failures. Note that Octavia certificates and Cinder volume encryption keys depend on Barbican secrets remaining decryptable.

- Environments that rotated their KEK on earlier releases can adopt Secret-based management without another rotation: `scripts/rotate-barbican-kek.py --adopt` stages the currently deployed KEK into the Secret. Then remove the KEK from your override files, since an override always takes precedence over the Secret, run `install-barbican.sh` once and confirm `--validate deployed` passes.

- Running `p11_crypto` as the primary backend does not re-encrypt existing secrets: rows stored under `simple_crypto` remain wrapped by the simple_crypto KEK indefinitely (dual-plugin operation decrypts them via their original backend), so the KEK requirements and rotation workflow above remain in force. The db-sync rewrap and the tool's validation only consider `simple_crypto` rows; `p11_crypto` data is never touched by a KEK rotation.

#### Security Notes

- **Dynamic Key & PIN Injection:** Neither the SoftHSM2 PIN nor the `simple_crypto` Master KEK is stored in version-controlled override files. All credentials are created and persisted in Kubernetes Secrets (`barbican-hsm-credentials`, `barbican-simple-crypto-kek`) and injected dynamically at deploy time.

- **Pod Security Context:** Enforced non-root execution (`runAsUser: 42424`) and group ownership (`fsGroup: 42424`) under `pod.securityContext` to ensure secure, correct filesystem permissions for SoftHSM2 token storage mounted inside pods.

- Deployments that never set a KEK have been running simple_crypto on Barbican's publicly documented default key, meaning stored secrets (including Octavia certificates and Cinder encryption keys) were protected by a key that is public knowledge. The rotation workflow above moves stored secrets off that default; it stays listed in `old_keks` as a decrypt-only entry, which exposes nothing new since the key is public already. No KEK value is stored in Genestack repositories; keys exist only in Kubernetes and in the rendered Barbican configuration.

## Storage, Images, and Data Protection

### Freezer

#### Prelude

Freezer backup and restore functionality was integrated into the Skyline dashboard for Genestack 2026.3.0. Users can enable per-instance backups at create time, create and schedule backup jobs, and restore backups across file system, Nova, Cinder, MySQL, and MongoDB modes. The full workflow was validated end-to-end in a development environment.

#### New Features

- Added a Backup & Restore section to the Skyline dashboard, exposing Freezer Jobs, Actions, Clients, and Backups. The section is shown only when the `freezer` endpoint is present in the service catalog.

- Added an Enable Backup option to the instance create workflow. When enabled, the freezer-agent and freezer-scheduler are installed automatically on first boot via cloud-init. The option is a first-class field on the create form, shown when Freezer is available.

- Added backup job creation supporting file system (`fs`), Nova VM snapshot, Cinder volume, MySQL, and MongoDB (LVM) modes, with one-time and recurring schedule options.

- Added restore support for all backup modes, including restoring a Nova snapshot to a new instance on a selected network and restoring Cinder volumes in place.

- Added Disable and Enable (resume) backup actions on the instance view to pause and resume a VM's scheduled jobs without reinstalling the agent.

- The Swift container field on job creation accepts a new container name and creates the container automatically at job submission time, removing the need to pre-create it under Object Storage.

- The generated agent bootstrap suppresses the benign eventlet deprecation warning from the freezer-scheduler and agent, keeping the scheduler log clean on newly created VMs.

#### Known Issues

- Federated and SSO users cannot use password authentication for the on-VM freezer-scheduler and will encounter 401 errors. A Keystone-local user must be used for the backup scheduler identity until a centralized scheduler is available.

- Freezer backup and restore via Skyline was validated against the `stable/2025.1-latest` freezer-api image.

#### Security Notes

- The backup scheduler credential supplied at instance create time is embedded in the instance cloud-init user-data via config-drive so the on-VM scheduler can authenticate to the Freezer API. It is not stored by Skyline and is not logged.

#### Other Notes

- Added Skyline user and operational documentation for Freezer backup and restore, including manual agent installation and troubleshooting guidance.

### Trove

#### Prelude

Limited Availability (LA) release of our managed Database-as-a-Service (DBaaS), powered by OpenStack Trove.

**Scope & Constraints:**
Because this service is in LA, the following constraints apply:
  - No SLA Guarantees: This service does not currently carry a Service Level Agreement (SLA).
  - Capacity Quotas: Each enrolled account is limited to a maximum of 40 GB of total storage
                     for all database instance volumes.

**How to Provide Feedback:** Your feedback is critical to helping us refine this service. Please submit any bugs, performance issues, or feature requests via the Rackspace ticketing system(s) or create a github issue.

#### New Features

- This release allows selected customers to provision, manage, and scale relational databases seamlessly through our cloud portal and API.

#### Known Issues

- Upgrade and Rebuild break backups and any operation dependent on backups, like restore and creating replicas

#### Other Notes

- Only MySQL 8.4 is supported. The MySQL 8.4 backup image was built using Trove 2025.2 instead of Trove 2026.1

## Other Release Notes

### Miscellaneous

#### New Features

- Added `ops-tools/find_orphan_instances`, a Python operator tool that audits Nova compute hosts for UUID-shaped directories under `/var/lib/nova/instances` that are absent from both the host-scoped Nova server list and active Nova database rows.

- The orphan instance directory auditor supports read-only text or JSON output by default, optional backup and deletion workflows, stable exit codes, command timeouts, per-host errors, and explicit `--yes-im-really-sure` confirmation for destructive cleanup.

- Adds a suspended Kubernetes CronJob manifest for read-only JSON orphan instance scans with one-week finished Job retention.

- Documents `ops-tools/find_orphan_instances/find_orphan_instances.py` for Genestack 2026.3.0. The Python scanner identifies Nova instance directories that are absent from active Nova state, emits text or JSON reports, and gates backup/deletion workflows behind explicit operator confirmation.

- Documents the suspended read-only CronJob manifest that runs the scanner in JSON mode and retains finished Jobs for one week.

- Added `ops-tools/find_orphan_qdisk`, a Python auditor for stale libvirt tap ingress qdiscs that can cause Nova/libvirt spawn failures with `tc qdisc add ... ingress` exclusivity errors.

- The qdisc auditor supports cluster, node, pod, and specific tap scans, text or JSON output, read-only operation by default, stable exit codes, and automated remediation guarded by `--fix --yes-im-really-sure`.

- Adds a suspended Kubernetes CronJob manifest for read-only JSON qdisc scans with one-week finished Job retention.

- Documents `ops-tools/find_orphan_qdisk/find_orphan_qdisk.py` for Genestack 2026.3.0. The Python scanner finds stale libvirt tap ingress qdiscs associated with Nova spawn failures, defaults to read-only output, and requires `--fix --yes-im-really-sure` before deleting ingress qdiscs.

- Documents the suspended read-only CronJob manifest that runs the scanner in JSON mode and retains finished Jobs for one week.

- Added `ops-tools/image_uuid_migrations`, a Python operator tool that generates and optionally applies MariaDB SQL for migrating Nova and Cinder image UUID references after Glance image replacement.

- The tool is dry-run by default, requires a CSV mapping file, supports explicit MariaDB connection options, handles one or more Nova databases, optionally updates Cinder `volume_glance_metadata` for bootable volumes, and requires `--yes-im-really-sure` with apply mode.

- CSV mappings are validated before SQL generation or apply, with a validation-only mode, connected dry-run update summaries, offline SQL rendering, and a generic example CSV shipped with the tool.

- Added release coverage for `ops-tools/rogue_pod_scanner`, a Python scanner that compares CRI pod sandboxes reported by `crictl` on a node with pods scheduled to that node in the Kubernetes API.

- Adds a suspended Kubernetes CronJob manifest for all-node read-only JSON rogue pod scans with one-week finished Job retention.

- Documents `ops-tools/rogue_pod_scanner/rogue_pod_scanner.py` for Genestack 2026.3.0. The Python scanner compares CRI pod sandboxes on nodes with Kubernetes API pod state, supports text or JSON output, and includes bounded SSH and command execution controls.

- Documents the suspended read-only CronJob manifest that runs the scanner in JSON mode and retains finished Jobs for one week.

- QonoS v2 is a modern, extensible scheduling platform for executing time-based actions against OpenStack services. It provides cron-scheduled operations including server snapshots (Nova), volume full and incremental backups (Cinder), with Keystone authentication, trust-based delegation, retention policies, and RabbitMQ notifications.

  Supported action types:

  - `server_snapshot` — Glance image snapshot of a Nova server - `volume_backup_full` — full Cinder volume backup - `volume_backup_incremental` — incremental Cinder backup

  Enable during `bin/setup-openstack.sh` or install with `/opt/genestack/bin/install-qonos.sh`. See `docs/openstack-qonos.md` for secrets, config overrides, Gateway exposure, Skyline integration, and validation.

#### Upgrade Notes

- Existing clusters do not pick up these changes automatically. Re-apply the rook-operator kustomize base, the rabbitmq-cluster overlay, and the openstack and mariadb-cluster kustomize bases, and re-run the grafana and longhorn install scripts, to roll the affected pods without mounted service account tokens.

- Removed the deprecated `heartbeat_in_pthread` override from the oslo.messaging RabbitMQ configuration for Blazar, Designate, Heat, Magnum, Masakari, Neutron, Nova, Octavia, Trove, and Zaqar.

  On oslo.messaging versions where the option is still available, deployments will use the upstream default value of `false`. The option has been removed entirely in oslo.messaging 18.0.0. Existing heartbeat interval, timeout, and reconnect settings remain unchanged.

#### Security Notes

- Reduced the attack surface by disabling service account token automounting for workloads that do not call the Kubernetes API. Each change was verified live (forced restarts, audit logs, and a proof-of-function job) before being made durable:

  - Rook-Ceph OSD, RGW, and default service accounts (mons, crash
  collectors, exporters) - `automountServiceAccountToken: false`
  set on the ServiceAccounts in
  `base-kustomize/rook-operator/base/common.yaml`.
- RabbitMQ server pods - `automountServiceAccountToken: false`
  set via the RabbitmqCluster pod template override in
  `base-kustomize/rabbitmq-cluster/base/rabbitmq-cluster.yaml`.
- The standalone Grafana pod - `automountServiceAccountToken: false`
  set in `base-helm-configs/grafana/grafana-helm-overrides.yaml`.
- The longhorn-ui pods - a kustomize patch in
  `base-kustomize/longhorn/base` sets
  `automountServiceAccountToken: false` on the
  `longhorn-ui-service-account` ServiceAccount (the longhorn chart
  does not template the field).
- The openstack namespace `default` ServiceAccount - set to
  `automountServiceAccountToken: false` in
  `base-kustomize/openstack/base/default-serviceaccount.yaml`. The
  only consumers (barbican-exporter, openstack-metrics-exporter)
  never call the API.
- The mariadb `backup` ServiceAccount - set to
  `automountServiceAccountToken: false` in
  `base-kustomize/mariadb-cluster/base/backup-serviceaccount.yaml`.
  The backup job containers dump the database over TCP and do not
  call the API; a backup job was run to completion with no token
  mounted to confirm.

  Important caveat: most OSM pods run a `kubernetes-entrypoint` init container that reads the service account token file at startup and hard-fails if the file is absent, even when the ServiceAccount has no RBAC bindings. Disabling token automounting for those ServiceAccounts (for example `memcached-memcached`, `libvirt`, and `neutron-netns-cleanup-cron`) was attempted and reverted because it crash-looped the pods. Those ServiceAccounts intentionally keep the token mounted.

#### Other Notes

- Documented rogue pod scanner usage for single-node and all-node scans, Kubernetes node address selection, JSON output, progress logs, and exit codes for Genestack 2026.3.0.

- Aligned the scanner with the ops tools CLI standard by adding `--format text|json` and bounded command execution with SSH and command timeout options while preserving `--json` as a compatibility alias.

## Platform Foundations Git History

### Cert-Manager

- Fix: release-notes for 2026.2 (#1673)

- Feature: upgrade to 2026.1 (#1669)

### Proxy Environment Handling

- OSPC-2276 Database instance going into ERROR state overnight (#1756)

- Fix: fully remove the unneeded hpa override files and properly configure neutron uwsgi app (#1742)

- OSPC-2244 Setup Swift AIO in hyperconverged lab (#1699)

- Enhance Envoy Gateway multi-gateway config mode (#1651)

### MariaDB Operator

- Fix backup script by changing from cluster IP to node port. (#1820) (#1821)

- Feature: deploy QonoS via Kustomize (#1760)

- Fix: schedule mariadb backup job in worker for grafana DB backup (#1714)

### Memcached

- Fix: update memcached and libvirt charts to 2026.1 (#1798) (#1800)

## Observability and Telemetry Git History

### Observability Stack

- Fix: Updating etcd otel scrape configs to pull etcd endpoints only (#1703)

### Ceilometer

- Fix: use the 2026.1 latest image tag (#1803) (#1810)

- Fix: drop OpenStack config options deprecated as of Gazpacho (#1763)

- Fix: remove extra ceilometer hpa bits that were missed (#1750)

- Fix: assign ResellerAdmin role (#1677)

### CloudKitty

- Fix: cloudkitty version upgrade and missing files and typos (#1818) (#1819)

## Kubernetes and Container Platform Git History

### Magnum

- Fix: 2026.1 API startup and PasteDeploy configuration (#1808) (#1809)

### Kube-OVN

- Fix: revert to br-overlay as this is a breaking change and not called out in release notes (#1687)

- Fix: explicitly disable hw offloading in kube-ovn (#1674)

- Fix: pre-populate OVN TLS cert with proper DNS SANs before Helm install (#1668)

### Kubernetes

- OSPC-2229 Deployment of Trove needs to be idempotent (#1744)

- Feature: hyperconverged lab script enhancements (#1722)

- Feature: hyperconverged lab hardening, dev-mode worktree support, Manila enablement, Octavia fixes (#1718)

- Fix: eliminate cinder volumes playbook races and generalize lab cinder config (#1717)

- Added Kubernetes PVC Disk Usage dashboard (#1672)

- OSPC-2080 Ansiblize and/or Kustomize the setup for Trove

## Networking and Load Balancing Git History

### Neutron / OVN

- Feature: update the octavia-ovn-agent sidecar to latest 2026.1 image (#1783) (#1784)

- Fix: retry read-only commands in check_octavia_ovn (#1741)

- Ovn hw offload fix (#1675)

- Feature: ops-tool check-octavia-ovn self-heal tool (#1462)

### Octavia

- Fix: OSPC-2314: activating genestack venv in port creation scripts (#1715)

- Fix: OSPC-2308: use root's venv for Octavia preconf to resolve missing openstack.cloud collection (#1713)

### Envoy Gateway

- Fix: add Envoy Gateway traffic policy for synchronous volume attach (#1804)

- Fix: Add Envoy Gateway traffic policies for Glance bulk image transfers (#1716)

## Compute and Scheduling Git History

### Libvirt

- Moar 2026 3 cp (#1799)

### Masakari

- Fix: Fix Masakari HPA (#1664)

- Fix: typos fixes to hpa and update masakari (#1692)

## Identity and Secrets Git History

### Keystone

- Fix: update trust list/create policy rules (#1788) (#1792)

- Chore: correct fernet sync token resources requests and limits (#1754)

- admin password rotation (#1711)

- Fix: avoid fernet key ownership race during sync (#1682)

### Barbican

- Fix: OSPC-2375: Added simple_crypto KEK resolution for greenfield deployments (#1774)

- Feature: OSPC-2375: Auto-extract and inject simple_crypto Master KEK for brownfield Gazpacho upgrades (#1771)

- Feature: OSPC-2370: Added SoftHSM2 ConfigMap mount and fix PKCS#11 p11_crypto_plugin configuration (#1765)

- Feature: OSPC-2338: Adding PKCS#11 HSM support in hyperconverged lab (#1749)

- Feature: OSPC-2303: injecting PKCS#11 HSM PIN at deploy time

- Feature: OSPC-2304: added barbican-hsm-credentials K8s Secret

- Feature: OSPC-2302: adding inert PKCS#11 p11_crypto_plugin config

## Storage, Images, and Data Protection Git History

### Freezer

- Adding the retention policy info for skyline-freezer (#1767)

- OSPC-2214: Removed the Static vendor data inject job for freezer (#1691)

### Cinder

- Fix: bumb cinder branch used when building venvs in the cinder-deploy playbook (#1778)

- FIX!: Manual revert Ansible deploy-cinder-volume.yml and role (#1737)

- Fix: cinder-volume playbook virtualenv (#1726)

- Fix: add Gazpacho volumes to Talos cinder-volume kustomize (#1681)

### Trove

- OSPC-2366 Database Instance taking too long to build to ACTIVE/HEALTHY state (#1775)

- OSPC-2381 Database instances do not build for 2026.1 (#1766)

- OSPC-2351 Increase coverage of automated tests (#1755)

- OSPC-2347 Trove DB access document is missing some steps (#1745)

- OSPC-2243 Changes needed to enable database log list (#1748)

- OSPC-2311 Creating replicas is not working after recent updates for backups (#1739)

- OSPC-2227 Automated Tests for Trove (#1733)

- OSPC-2222 Document steps for customer to access their database instance from an external source (#1719)

- OSPC-2294 Backup does not work if database instance connected to tenant network (#1707)

- OSPC-2272 Creating a database replica is not working (#1702)

- OSPC-2260 Need sane defaults for deployTrove parameters (#1679)

- Feature: Enable Backups and Backup Strategy in Trove (#1670)

- OSPC-2241 Create configuration group (#1666)

### Manila

- Fix: Manila: Various adjustments for Manila Generic Driver Ansilbe role (#1706)

## Orchestration Git History

### Skyline

- feature flag addition to skyline helm config (#1777)

- Fix: skyline deployment is called skyline (#1696)

## Other Git History

### Miscellaneous

- Fix: update from deprecated container images (#1773)

- Add multipath scanner for known errors (#1776)

- Fix: update grafana dashboard import script (#1700)

- Fix!: Stale TC Flower playbook fix for 'limit' (#1752)

- Feature: add TC flower audit script and cleanup playbook for hw-offload disable (#1740)

- Fix: more release note updates

- Fix: OSPC-2251: pinning openstacksdk and upgrade openstack.cloud to resolve version mismatch (#1712)

- Chore: Updating gitignore for additional ai rules (#1710)

- Revert "chore: ignore ai garbage (#1704)" (#1709)

- Chore: ignore ai garbage (#1704)
