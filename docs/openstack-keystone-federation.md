# Setup the Keystone Federation Plugin

## Create the domain

``` shell
openstack --os-cloud default domain create rackspace_cloud_domain
```

## Create the identity provider

``` shell
openstack --os-cloud default identity provider create --remote-id rackspace --domain rackspace_cloud_domain rackspace
```

### Create the mapping for our identity provider

You're also welcome to generate your own mapping to suit your needs; however, if you want to use the example mapping (which is suitable for production) you can.

``` json
--8<-- "etc/keystone/mapping.json"
```

!!! tip

    The example mapping **JSON** file can be found within the genestack repository at `etc/keystone/mapping.json`.

Now register the mapping within Keystone.

``` shell
openstack --os-cloud default mapping create --rules /tmp/mapping.json rackspace_mapping
```

## Create the federation protocol

``` shell
openstack --os-cloud default federation protocol create rackspace --mapping rackspace_mapping --identity-provider rackspace
```
