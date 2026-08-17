# Release 2026.2.0

This release note set covers the exact git diff from `release-2026.1.0` to `release-2026.2.0`.
Curated reno note fragments are listed first. Supplemental commit-derived items are listed separately afterward.

[Product Matrix](product-matrix-2026.2.0.md)

## Components

- [Platform Foundations](#platform-foundations)

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

- The cert-manager installation path is now chart-based and uses the upstream OCI-distributed cert-manager Helm chart source instead of the legacy repository-based chart reference. This aligns Genestack with the current cert-manager chart distribution model and keeps chart, CRD, and image updates on the Helm-managed installation path.

- Bootstrap now installs `cmctl` through the shared Genestack support functions so cert-manager API readiness checks can be run consistently from Genestack utility hosts. Cert-manager backup, reporting, solver inspection, and post-upgrade gate helper scripts have also been added under `scripts/cert-manager-support/`.

#### Upgrade Notes

- The validated Genestack cert-manager upgrade path is a successive minor-version upgrade from `v1.15.3` to `v1.19.5` using staged maintenance hops, for example `v1.15.3` -> `v1.16.x` -> `v1.17.x` -> `v1.18.x` -> `v1.19.5`. Operators should follow one-minor-version hops and review the upstream upgrade notes for each target minor version before proceeding. This is especially important for the `v1.15` to `v1.16` hop, where Helm schema validation can reject existing values with typos or unrecognized fields, and the `v1.17` to `v1.18` hop, where cert-manager changes the default `Certificate.spec.privateKey.rotationPolicy` from `Never` to `Always`.

- Existing deployments should install `cmctl` before running the cert-manager maintenance and validation workflow. New bootstrap installs install `cmctl` automatically. Existing hosts can install it from the Genestack support functions:

  .. code-block:: shell

  cd /opt/genestack
   source scripts/lib/functions.sh
   ensureCmctl

- Operators should back up cert-manager custom resources and TLS secrets before upgrading and run the included post-upgrade gate after each staged hop or after the final upgrade. The gate checks `cmctl` API readiness, Helm release state and version, and cert-manager workload rollout status. Environments with custom ACME issuers or non-default solver configuration should also validate certificate issuance through their configured challenge mechanism during the maintenance window.

- Review any local `Certificate` resources that rely on inherited private-key rotation behavior. In cert-manager `v1.18` and later, certificates without an explicit `spec.privateKey.rotationPolicy` inherit `Always`. CA certificates and other trust anchors should have an intentional policy set before upgrade so that key rotation is controlled rather than accidental.

#### Security Notes

- cert-manager has been updated to `v1.19.5`. This keeps Genestack on the intended `v1.19` minor branch while picking up the supported patch level, including the `v1.19.3` fix for `GHSA-gx3x-vq4p-mhhv` / `CVE-2026-25518` and later vulnerability-related patch updates. Base Genestack does not use DNS01 by default, but environments with custom DNS01 ACME solvers should treat this patch level as security-relevant.

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

- Chore: Adding observability stack maintenance doc and m… (#1523)

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

- Feature: support airgap and internal [internal URL redacted] sources (#1562)

## Compute and Scheduling Git History

### Blazar

- Add member/reader rule to get blazar oshosts (#1610)

### Libvirt

- Update modprobe.d path in kustomization.yaml

### Nova

- Add member permissions for nova VM reset action (#1662)

- Chore: Configure novaDB removing deleted rows (#1600)

## Identity and Secrets Git History

### Keystone

- Fix: stop keystone fernet warnings on secret mounts (#1628)

- Fix: Configure shibboleth memcache hosts (#1620)

### Barbican

- Chore: Remove superflous .conf.cache overrides (#1635)

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

## Orchestration Git History

### Skyline

- Chore: add node selectors (#1541)

- Chore: create new maintenance plan for skyline upgrade (#1532)

## Other Git History

### Miscellaneous

- Fix: Customer communication templates and lint (#1637)

- Chore: Updating loki default log retention (#1639)

- Fix: Updating os-metrics exporter servicemonitor scrape config (#1630)

- Chore: updated postgres log settings to avoid them filling disk (#1608)

- update tasks to include options to provision lb with floating ip and to create cluster vms directly on the ext net for better performance (#1606)

- Adds tempest helm overrides (#1603)

- Docs: OSPC-1912: Adding doc for bringing postgres operator under helm control (#1576)

- Fix: Replace the malformed rax-noble key (#1590)

- Docs: rework release note generation (#1569)

- Docs: generate release 2026.1.0 notes (#1565)

- Updated docs for customer comms (#1524)

- Feature: move static-vendor-data to a systemd unit file and shell script (#1514)

- Fix: handle mc in RGW helper (#1501)
