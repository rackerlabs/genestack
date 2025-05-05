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

??? abstract "Example keystone `mapping.json` file"

    ``` json
    --8<-- "etc/keystone/mapping.json"
    ```

The example mapping **JSON** file can be found within the genestack repository at `/opt/genestack/etc/keystone/mapping.json`.

!!! tip "Creating the `creator` role"

    The creator role does not exist by default, but is included in the example
    mapping. One must create the creator role in order to prevent authentication
    errors if using the mapping "as is".

    ``` shell
    openstack --os-cloud default role create creator
    ```

## Now register the mapping within Keystone

``` shell
openstack --os-cloud default mapping create --rules /tmp/mapping.json --schema-version 2.0 rackspace_mapping
```

## Create the federation protocol

``` shell
openstack --os-cloud default federation protocol create rackspace --mapping rackspace_mapping --identity-provider rackspace
```

## Rackspace Configuration Options

The `[rackspace]` section can also be used in your `keystone.conf` to allow you to configure how to anchor on
roles.

| key | value | default |
| --- | ----- | ------- |
| `role_attribute` | A string option used as an anchor to discover roles attributed to a given user | **os_flex** |
| `role_attribute_enforcement` | When set `true` will limit a users project to only the discovered GUID for the defined `role_attribute` | **false** |
