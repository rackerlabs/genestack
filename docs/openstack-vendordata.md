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

You can override the default configmap `/opt/genestack/base-kustomize/nova/base/static-vendordata-configmap` to pass 
static vendor-data against `vendor_data.json` key, which is mounted at `/etc/nova/vendor_data.json` in metadata service 
resources.

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

See [cloud-init docs](https://cloudinit.readthedocs.io/en/latest/reference/datasources/openstack.html) for more details.
