# Release 2026.2.0.1

This fix release is based on `release-2026.2.0` and includes targeted operational fixes for Cinder volume deployment, Octavia OVN health checks, Kube-OVN TC flower cleanup, and OpenStack HPA/uWSGI configuration.

## Cinder Volume Deployment

### Bug Fixes

- Reverted the Cinder volume role behavior that stopped Cinder services and removed the existing Cinder virtualenv before reinstalling. The virtualenv path contains the symlinked `/opt/cinder/etc/cinder` configuration, so wiping it could remove backend configuration from `/etc/cinder` and leave only the backend type override.

- Rerunning `deploy-cinder-volume.yaml` on storage nodes with multiple backend types now preserves existing Cinder configuration instead of wiping configuration for other backends.

## Networking and Load Balancing

### Octavia

#### Bug Fixes

- `check_octavia_ovn` now retries read-only discovery commands before marking a load balancer check as failed. Retried commands include `openstack loadbalancer list`, `openstack loadbalancer show`, and `kubectl ko sbctl` port-binding lookups.

- The retry behavior is configurable with `RETRIES` and `RETRY_DELAY`, and failed attempts include stderr in the journal for troubleshooting. `openstack loadbalancer failover` remains a single-attempt action so failover state is only updated after an explicit successful failover.

### Kube-OVN

#### New Features

- Added `scripts/tc-offload-audit.sh`, a read-only fleet audit for Kube-OVN HW offload disable workflows. The audit reports each `ovs-ovn` node's Kube-OVN `HW_OFFLOAD` environment value, OVS `other_config:hw-offload` setting, live OVS TC datapath flow count, ingress qdisc count, TC flower filter counts, role labels, and per-node verdict.

- Added `ansible/playbooks/clear-stale-tc-flower.yaml`, a dry-run-by-default cleanup playbook for stranded chain-0 TC flower filters. The playbook only cleans a node after OVS reports zero live TC datapath flows, deletes chain-0 flower filters from shared ingress blocks and per-device ingress qdiscs, and performs a fleet coverage check so nodes are not silently missed.

#### Upgrade Notes

- Operators disabling Kube-OVN HW offload should run the TC flower audit before and after the maintenance. Nodes with `ORPHANED-LIVE`, `UNREACHABLE`, or `REVIEW` verdicts require attention before OpenStack service upgrade work continues.

- Run `clear-stale-tc-flower.yaml` first in dry-run mode, then with `-e tc_cleanup_dry_run=false` only after the HW offload flip has completed and OVS reports zero live TC datapath flows on the target nodes.

### Neutron / OVN

#### Bug Fixes

- Corrected the Neutron API uWSGI configuration so the Neutron API has an explicit `neutron_api_uwsgi` application configuration with the intended process and thread settings.

## Compute and OpenStack Service Scaling

### HPA Cleanup

#### Bug Fixes

- Removed obsolete HPA manifests for OpenStack scheduler, metadata, and console proxy style workloads that should not be autoscaled by these overrides. Supported stateless API HPA resources remain in place.

- Removed stale HPA references from the affected Kustomize bases so deleted override files are no longer included during manifest rendering.

## Included Pull Requests

- #1737: Manual revert Ansible `deploy-cinder-volume.yml` and role
- #1740: Add TC flower audit script and cleanup playbook for HW-offload disable
- #1741: Retry read-only commands in `check_octavia_ovn`
- #1742: Remove unneeded HPA override files and configure Neutron uWSGI
