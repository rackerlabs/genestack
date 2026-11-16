# Genestack release-2026.3.2

Maintenance release built on top of `release-2026.3.1`.

Use tag: `release-2026.3.2`

## Highlights

* Moved the Genestack observability stack into the standalone `genestack-observability` repository. New bootstrap and installation entry points preserve a supported path for deploying and upgrading monitoring services.
* Replaced Nova/libvirt `quota:vif_*` flavor bandwidth shaping with the Rackspace-designed Neutron `flavor_qos` plugin and the `flavor_qos:policy_id` extra spec.
* Added a dry-run-first flavor QoS cutover tool that creates the `lite`, `plus`, `pro`, and `elite` egress policies, migrates 80 regional flavors and cached instance flavors, updates existing compute ports, and records guarded rollback state.
* Added managed, loopback-only MariaDB port-forwarding for the flavor QoS migration workflow, along with additional lifecycle, conflict, and transaction hardening.
* Added Trove fixes for production image builds, MySQL backup image version selection, and flavors containing ephemeral disk or swap allocations.
* Expanded the host-based Cinder deployment with `cinder-rxt`, virtualenv configuration, modular configuration drop-ins, internal-tenant image caching, lock-path handling, and rootwrap integration.
* Aligned MariaDB idle-connection timeouts with OpenStack service database pool recycling to prevent server-side aborted pooled connections.
* Corrected Skyline's Prometheus endpoint, changed the metrics exporter guidance to use a dedicated `os-metrics` user, fixed CAPI management-cluster authentication variables, and made lab tenant egress SNAT default to disabled.

## Upgrade note

Existing deployments using Nova/libvirt `quota:vif_*` flavor properties require a one-time migration to Neutron flavor QoS. Review the dry run, quiesce instance lifecycle operations, back up every affected Nova cell, and include every cell database during the cutover. The migration removes the legacy properties, installs `flavor_qos:policy_id`, updates cached instance flavors and existing compute ports, and creates egress-only Neutron policies. Legacy inbound flavor limits are removed without replacement.

See `ops-tools/flavor_qos_migration/README.md` for the cutover procedure and `ops-tools/flavor_qos_migration/VALIDATION.md` for post-migration lifecycle validation.

## Included PRs

* #1875: Use the dedicated `os-metrics` user for the metrics exporter
* #1880: Move observability components to the standalone repository and retain supported installers
* #1882: Add missing observability paths to `.gitignore`
* #1884: Add Trove production image, backup image, ephemeral disk, and swap fixes
* #1886: Correct the Skyline Prometheus endpoint
* #1887: Configure `cinder-rxt` and the host-based Cinder virtualenv deployment
* #1888: Align MariaDB and OpenStack service database timeouts
* #1898: Default lab tenant egress SNAT to disabled
* #1901: Add the flavor QoS cutover migration tool
* #1909: Finalize the 2026.3.2 RC with managed MariaDB port-forwarding, CAPI authentication fixes, and flavor migration hardening

## Included commits

* `fb7ba60628447a788b0f7244abcf2ead0b925d55`: docs: Suggest os-metrics user instead of admin for the metrics exporter (#1875)
* `84f910617084619a3c1c6fa1c48c7474e71292a8`: Release 2026.3.2 (#1880)
* `ef9e1f14ce15f194a9ad3f99c94ee1c7cec6e5e6`: fix: Updating missing observability gitignore entries (#1881) (#1882)
* `9fd494d4ec886236b4db8bd5fabd914239ff2b66`: Cherry picked Trove changes needed for LA (#1884)
* `d16047e6f94a0b67f92ff8899e9e45323706b716`: fix: set Skyline prometheus_endpoint to Prometheus in monitoring namespace (#1886)
* `fee98015879ad8f655020e34a11b5906d542d977`: feat(cinder_volumes): configure cinder-rxt and virtualenv deployment (#1887)
* `870b4742fcb9cb35bd3a20fd8707f6ddbf483a59`: fix(database): align database timeouts with service timeouts (#1858) (#1888)
* `076f994562a394e37950b41a95eea6c36c7db96a`: Fix lab_tenant_egress_snat_enabled to default to false (#1895) (#1898)
* `cf3599e1a5d882768223a7b017b5034cde321ae7`: feat: add flavor QoS cutover migration tool (#1900) (#1901)
* `ff0aac576556c2cfd0d3d304492237795d15cac9`: Release 2026.3.2 rc cp (#1909)
