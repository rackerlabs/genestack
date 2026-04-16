# Openstack Vendordata

To read more about Openstack Vendordata see [upstream docs](https://docs.openstack.org/nova/latest/admin/vendordata.html)

## Overview

It is a feature that provides way to pass vendor-specific data to the instances at boot-time. It can be accessed 
with one of the following ways:

* [Metadata Service](https://docs.openstack.org/nova/latest/admin/metadata-service.html)
* [Config Drives](https://docs.openstack.org/nova/latest/admin/config-drive.html)

Also, Vendordata sources can be specified with two ways:

* [StaticJSON](https://docs.openstack.org/nova/latest/admin/vendordata.html#staticjson)
* [DynamicJSON](https://docs.openstack.org/nova/latest/admin/vendordata.html#dynamicjson)

*StaticJSON* collects data from a JSON file that exits locally and is suitable when data remains same for all instances. 
On the other hand *DynamicJSON* can collect data from external REST service and works well when that data does change for 
instances.

## Vendordata in genestack

Genestack use *Metadata Service* to access Vendordata. It has StaticJSON enabled in nova.conf as default provider:

```yaml
api:
  vendordata_providers: ['StaticJSON']
  vendordata_jsonfile_path: /etc/nova/vendor_data.json
```

The tracked plumbing for this lives in
`/opt/genestack/base-kustomize/nova/base/static-vendordata-configmap.yaml`.
In deployed environments this is typically overridden from
`/etc/genestack/kustomize/nova/base/static-vendordata-configmap.yaml` and then
consumed by the Nova metadata service at `/etc/nova/vendor_data.json`.

For DynamicJSON you need to enable it amongst providers and have to specify dynamic target URL(s) in nova.conf as follows:

```yaml
api:
  vendordata_providers: ['StaticJSON', 'DynamicJSON']
  vendordata_jsonfile_path: /etc/nova/vendor_data.json
  vendordata_dynamic_targets: ['target/url1', 'target/url2']
```

A POST request call will be made to these dynamic targets and you can expect the request body contains instance's context 
e.g. *instance-id, image-id, hostname etc.* These targets should return a valid JSON in response.

## Cloud-init and Vendordata

Cloud-init instructions can be passed-in as string against key - `cloud-init` within Vendordata JSON as follows:

```json
{
  "cloud-init": "#cloud-config\nruncmd:\n..."
}
```

### Precedence and merge behavior

When an instance uses the OpenStack datasource, cloud-init processes OpenStack
vendordata before user-data. If both documents are `#cloud-config`, overlapping
keys such as `packages`, `bootcmd`, and `runcmd` are user-overridable and are a
poor place to encode required provider bootstrap.

Because of this, Genestack vendordata overrides should treat provider bootstrap
as a separate cloud-init part whenever it must coexist with arbitrary user
cloud-config. The recommended pattern is:

* Keep `vendor_data.json` as the Nova `StaticJSON` payload.
* Set the `cloud-init` value to a standalone cloud-init part such as a shell
  script or boothook.
* Use that part to write any provider-owned files and start provider-owned
  services.
* Leave user-facing cloud-config keys such as `packages`, `bootcmd`, and
  `runcmd` available for tenant customization.

For example, the vendordata payload can contain a shell script instead of a
cloud-config document:

```json
{
  "cloud-init": "## template: jinja\n#!/bin/bash\nset -euxo pipefail\n\nif [ \"{{ v1.distro }}\" != \"ubuntu\" ]; then\n  exit 0\nfi\n\ncat >/usr/local/sbin/provider-bootstrap.sh <<'EOF'\n#!/bin/bash\nset -euxo pipefail\n# provider bootstrap here\nEOF\nchmod 0755 /usr/local/sbin/provider-bootstrap.sh\n/usr/local/sbin/provider-bootstrap.sh\n"
}
```

This avoids the common case where a user-supplied `#cloud-config` replaces the
provider's `runcmd` or `packages` content.

Provider-owned services still need explicit ordering. In practice, the shell
payload should write systemd units that wait for cloud-init to finish before
running provider bootstrap logic, otherwise package installs or service actions
from user-data can still contend with provider bootstrap on first boot.

For long-running or network-sensitive bootstrap steps, prefer provider-owned
helper scripts with explicit retries and install checks. For example:

* restore any required provider repo files such as explicit Rackspace apt
  sources
* wait for cloud-init completion and package manager quiescence before running
  provider bootstrap
* check for existing agent installs with explicit scripts rather than a single
  hard-coded unit path
* fetch remote bootstrap assets with bounded retries and clear failure logging

See [cloud-init docs](https://cloudinit.readthedocs.io/en/latest/reference/datasources/openstack.html) for more details.
