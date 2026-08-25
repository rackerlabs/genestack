# Genestack release-2026.2.0.1

Fix release on top of `release-2026.2.0`.

## Highlights

- Fixed Cinder volume deployment so rerunning `deploy-cinder-volume.yaml` no longer wipes and rebuilds the virtualenv path that contains the symlinked `/opt/cinder/etc/cinder` configuration. This preserves existing backend configuration when storage nodes host multiple backend types.
- Improved `check_octavia_ovn` resilience by retrying read-only OpenStack and OVN discovery commands before marking a load balancer check as failed. Failover actions remain non-retried so state is only updated after an explicit successful failover attempt.
- Added Kube-OVN TC flower maintenance tooling for HW offload disable workflows:
  - `scripts/tc-offload-audit.sh` provides a read-only per-node fleet audit of HW offload state, live TC datapath flows, ingress qdiscs, and chain-0/total flower filter counts.
  - `ansible/playbooks/clear-stale-tc-flower.yaml` safely removes stranded chain-0 flower filters after OVS reports zero live TC flows, with dry-run mode enabled by default and fleet coverage checks.
- Cleaned up unsupported HPA overrides for non-stateless OpenStack workloads and corrected Neutron API uWSGI configuration.

## Included PRs

- #1737: Manual revert Ansible `deploy-cinder-volume.yml` and role
- #1740: Add TC flower audit script and cleanup playbook for HW-offload disable
- #1741: Retry read-only commands in `check_octavia_ovn`
- #1742: Remove unneeded HPA override files and configure Neutron uWSGI
