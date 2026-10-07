# Release 2026.3.1

Curated `release-2026.3.1` reno note fragments are listed first. Supplemental commit-derived items are listed separately afterward.

[Product Matrix](product-matrix-2026.3.1.md)

## Components

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
- [Other Git History](#other-git-history)

## Storage, Images, and Data Protection

### Cinder

#### Bug Fixes

- Fixed an issue in `ansible/roles/cinder_volumes` where `cinder-backup.service` and `cinder-volume-usage-audit.service` did not load the LVM worker configuration override file (`/etc/cinder/lvm-cinder.conf`). As a result, `cinder-backup` inherited the default `host = cinder-volume-worker` setting from base `cinder.conf` rather than using the storage node's hostname, causing the per-node `cinder-backup` services to appear as `down` in `openstack volume service list`.

- The host-based `cinder-volume` deployment (`ansible/roles/cinder_volumes`, run by `deploy-cinder-volume.yaml`) has been rewritten to mirror the modular configuration structure used by in-cluster Cinder pods in OpenStack-Helm (2026.1.x / Gazpacho).

  Instead of copying and mutating `cinder.conf.stage`, the role now installs the pristine base `cinder.conf` directly from the `cinder-etc` Secret and creates the modular snippet directory `/etc/cinder/cinder.conf.d/`, populating it with the Keystone credentials and service account configurations (`cinder_service_user.conf`, `cinder_nova.conf`, and `cinder_keystone_authtoken.conf`) from the `cinder-ks-etc` Secret.

  Backend workers and LVM now declare their specific `host` and `enabled_backends` overrides in isolated configuration files (e.g. `/etc/cinder/<worker>-cinder.conf` and `/etc/cinder/lvm-cinder.conf`), and systemd unit files load both the base configuration and the modular directory via `--config-dir /etc/cinder/cinder.conf.d`. This resolves failures where volumes created from images went into error due to missing Glance service user credentials, and ensures multi-backend storage nodes coexist safely without configuration collisions.

## Other Release Notes

### Miscellaneous

#### New Features

- Adds `ops-tools/default_password_detector` to scan Kubernetes Secrets referenced by `bin/services/*.yaml` and report values that still match the default credential values from the Helm chart version pinned in `helm-chart-versions.yaml`.

- The detector is read-only, does not print secret values, and exits with a distinct status when chart-default credentials are found so install scripts can emit loud non-blocking warnings for brownfield clusters.

- Adds `ops-tools/secret_schema_validator` to compare the service secret descriptors in `bin/services/*.yaml` with sensitive Helm chart values from the chart versions pinned in `helm-chart-versions.yaml`.

- The validator can be run after updating chart versions to identify missing service secret schema entries before the corresponding `bin/install-*.sh` script is used in a deployment.

- Service install scripts now manage Kubernetes secrets from the per-service descriptors in `bin/services/*.yaml`. The shared installer helper creates missing service-owned secrets, validates required secret keys, and reuses existing secret values instead of requiring a separate cluster-wide secret bootstrap step on brownfield deployments.

- Added shared secret helper primitives for idempotent secret checks, secret key validation, file-backed secret sync, and temporary file cleanup. Secret material rendered through temporary files is tracked by the installer and removed on both successful and failed exits.

- `bin/install-barbican.sh` now preserves brownfield `barbican-simple-crypto-kek` handling by adopting an existing deployed KEK from `barbican-etc` before any new KEK generation is considered. The installer also emits a prominent non-blocking warning when the well-known default Barbican KEK is detected.

- Manila and Trove techpreview enablement now use the shared install-script secret helpers for chart-derived service passwords. Their enablement roles no longer generate or rotate database, RabbitMQ, or service-user passwords outside the per-service secret schema.

#### Upgrade Notes

- Operators adding or reinstalling individual services no longer need a separate cluster-wide secret bootstrap command. Re-running an individual `bin/install-*.sh` script creates only missing keys and leaves existing secrets unchanged.

#### Security Notes

- Install scripts now warn when chart default or known default passwords are detected in existing Kubernetes secrets. These warnings are non-blocking so older clusters can continue to deploy, but they are intended to be visible enough for operators to plan secret rotation.

## Platform Foundations Git History

### Kube-ovn HW_OFFLOAD Saga

- Improved stale TC flower filter auditing and cleanup after OVS hardware offload is disabled, including non-zero chains and shared block filters that could silently blackhole tunneled traffic. (#1843)

- Updated the backup script to use a NodePort instead of the cluster IP. (#1820) (#1821)

### Memcached

- Updated the memcached chart to the 2026.1 series. (#1798) (#1800)

## Observability and Telemetry Git History

### Ceilometer

- Updated the OpenStack client image tag to the 2026.1 latest image. (#1803) (#1810)

### CloudKitty

- Updated CloudKitty versioning and restored missing files and documentation fixes. (#1818) (#1819)

## Kubernetes and Container Platform Git History

### Magnum

- Fixed Magnum 2026.1 API startup and PasteDeploy configuration. (#1808) (#1809)

## Networking and Load Balancing Git History

### Neutron / OVN

- Updated the `octavia-ovn-agent` sidecar to the latest 2026.1 image. (#1783) (#1784)

### Envoy Gateway

- Added an Envoy Gateway traffic policy so Nova synchronous volume attach requests can complete without hitting the default route timeout. (#1804)

## Compute and Scheduling Git History

### Libvirt

- Updated the Libvirt 2026.1 chart integration after the chart moved `libvirt-exporter` handling into additional containers. (#1799)

## Identity and Secrets Git History

### Keystone

- Updated Keystone trust list/create policy rules. (#1788) (#1792)

## Storage, Images, and Data Protection Git History

### Cinder

- Fixed the Cinder branch used when building virtual environments in the Cinder deployment playbook. (#1778)

## Other Git History

### Miscellaneous

- Updated installer secret jsonpath key access and added scaffolding documentation. (#1844) (#1845)

- Corrected the release tag used by the 2026.3 release notes. (#1825) (#1826)

- Updated the `release-2026.3.0` notes carried on the release branch. (#1823) (#1824)
