# Openstack Networks

To read more about Openstack networks please visit the [upstream docs](https://docs.openstack.org/python-openstackclient/latest/cli/command-objects/network.html).

### Create an Openstack Network

``` shell
openstack --os-cloud {user cloud name} network create
    [--extra-property type=<property_type>,name=<property_name>,value=<property_value>]
    [--share | --no-share]
    [--enable | --disable]
    [--project <project>]
    [--description <description>]
    [--mtu <mtu>]
    [--project-domain <project-domain>]
    [--availability-zone-hint <availability-zone>]
    [--enable-port-security | --disable-port-security]
    [--external | --internal]
    [--default | --no-default]
    [--qos-policy <qos-policy>]
    [--transparent-vlan | --no-transparent-vlan]
    [--provider-network-type <provider-network-type>]
    [--provider-physical-network <provider-physical-network>]
    [--provider-segment <provider-segment>]
    [--dns-domain <dns-domain>]
    [--tag <tag> | --no-tag]
    --subnet <subnet>
    <name>
```

### List Openstack Networks

``` shell
openstack --os-cloud {user cloud name} network list
    [--sort-column SORT_COLUMN]
    [--sort-ascending | --sort-descending]
    [--external | --internal]
    [--long]
    [--name <name>]
    [--enable | --disable]
    [--project <project>]
    [--project-domain <project-domain>]
    [--share | --no-share]
    [--status <status>]
    [--provider-network-type <provider-network-type>]
    [--provider-physical-network <provider-physical-network>]
    [--provider-segment <provider-segment>]
    [--agent <agent-id>]
    [--tags <tag>[,<tag>,...]]
    [--any-tags <tag>[,<tag>,...]]
    [--not-tags <tag>[,<tag>,...]]
    [--not-any-tags <tag>[,<tag>,...]]
```

### Set Openstack Network Properties

``` shell
openstack --os-cloud {user cloud name} network set
    [--extra-property type=<property_type>,name=<property_name>,value=<property_value>]
    [--name <name>]
    [--enable | --disable]
    [--share | --no-share]
    [--description <description>]
    [--mtu <mtu>]
    [--enable-port-security | --disable-port-security]
    [--external | --internal]
    [--default | --no-default]
    [--qos-policy <qos-policy> | --no-qos-policy]
    [--tag <tag>]
    [--no-tag]
    [--provider-network-type <provider-network-type>]
    [--provider-physical-network <provider-physical-network>]
    [--provider-segment <provider-segment>]
    [--dns-domain <dns-domain>]
    <network>
```

### Show Openstack Network Details

``` shell
openstack --os-cloud {user cloud name} network show <network>
```

### Delete Openstack Network

``` shell
openstack --os-cloud {user cloud name} network delete <network> [<network> ...]
```

## Example: Creating an Openstack Network and adding Subnets

Creating the network

``` shell
openstack  --os-cloud {cloud_name} network create {network-name}
```

When creating the subnet users have the option to use ipv4 or ipv6 on this example we will be using ipv4. The user will also need to specify their network name to ensure that their subnets are connected to the network they created.

``` shell
openstack  --os-cloud {cloud_name} subnet create --ip-version 4 --subnet-range 172.18.107.0/24 --network {network-name} {subnet-name}
```
