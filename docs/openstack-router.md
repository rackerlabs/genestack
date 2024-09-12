# Openstack Router

Read more about Openstack Routers using the [upstream docs](https://docs.openstack.org/python-openstackclient/latest/cli/command-objects/router.html).

#### Get List of Routers

``` shell
openstack --os-cloud={cloud name} router list
    [--sort-column SORT_COLUMN]
    [--sort-ascending | --sort-descending]
    [--name <name>]
    [--enable | --disable]
    [--long]
    [--project <project>]
    [--project-domain <project-domain>]
    [--agent <agent-id>]
    [--tags <tag>[,<tag>,...]]
    [--any-tags <tag>[,<tag>,...]]
    [--not-tags <tag>[,<tag>,...]]
    [--not-any-tags <tag>[,<tag>,...]]
```

#### Create a Router

``` shell
openstack --os-cloud={cloud name} router create
    [--extra-property type=<property_type>,name=<property_name>,value=<property_value>]
    [--enable | --disable]
    [--distributed | --centralized]
    [--ha | --no-ha]
    [--description <description>]
    [--project <project>]
    [--project-domain <project-domain>]
    [--availability-zone-hint <availability-zone>]
    [--tag <tag> | --no-tag]
    [--external-gateway <network>]
    [--fixed-ip subnet=<subnet>,ip-address=<ip-address>]
    [--enable-snat | --disable-snat]
    [--enable-ndp-proxy | --disable-ndp-proxy]
    [--flavor <flavor-id>]
    [--enable-default-route-bfd]
    [--disable-default-route-bfd]
    [--enable-default-route-ecmp]
    [--disable-default-route-ecmp]
    <name>
```

#### Add a Gateway to Router

``` shell
openstack --os-cloud={cloud name} router add gateway
    [--fixed-ip subnet=<subnet>,ip-address=<ip-address>]
    <router>
    <network>
```

#### Add a Subnet to Router

``` shell
openstack --os-cloud={cloud name} router add subnet <router> <subnet>
```

#### Add a Port to Router

``` shell
openstack --os-cloud={cloud name} router add port <router> <port>
```

#### Set Router Properties

``` shell
openstack --os-cloud={cloud name} router set
    [--extra-property type=<property_type>,name=<property_name>,value=<property_value>]
    [--name <name>]
    [--description <description>]
    [--enable | --disable]
    [--distributed | --centralized]
    [--route destination=<subnet>,gateway=<ip-address>]
    [--no-route]
    [--ha | --no-ha]
    [--external-gateway <network>]
    [--fixed-ip subnet=<subnet>,ip-address=<ip-address>]
    [--enable-snat | --disable-snat]
    [--enable-ndp-proxy | --disable-ndp-proxy]
    [--qos-policy <qos-policy> | --no-qos-policy]
    [--tag <tag>]
    [--no-tag]
    [--enable-default-route-bfd]
    [--disable-default-route-bfd]
    [--enable-default-route-ecmp]
    [--disable-default-route-ecmp]
    <router>
```

#### Delete Router

``` shell
openstack --os-cloud={cloud name} router add subnet <router> <subnet>
```

#### Create Router Port


``` shell
openstack --os-cloud={cloud name} port create [-h] [-f {json,shell,table,value,yaml}]
                             [-c COLUMN] [--noindent] [--prefix PREFIX]
                             [--max-width <integer>] [--fit-width]
                             [--print-empty] --network <network>
                             [--description <description>]
                             [--device <device-id>]
                             [--mac-address <mac-address>]
                             [--device-owner <device-owner>]
                             [--vnic-type <vnic-type>] [--host <host-id>]
                             [--dns-domain dns-domain] [--dns-name <dns-name>]
                             [--fixed-ip subnet=<subnet>,ip-address=<ip-address> | --no-fixed-ip]
                             [--binding-profile <binding-profile>]
                             [--enable | --disable]
                             [--enable-uplink-status-propagation | --disable-uplink-status-propagation]
                             [--project <project>]
                             [--project-domain <project-domain>]
                             [--extra-dhcp-option name=<name>[,value=<value>,ip-version={4,6}]]
                             [--security-group <security-group> | --no-security-group]
                             [--qos-policy <qos-policy>]
                             [--enable-port-security | --disable-port-security]
                             [--allowed-address ip-address=<ip-address>[,mac-address=<mac-address>]]
                             [--tag <tag> | --no-tag]
                             <name>
```

#### Creating a Router with Subnets Example

``` shell
openstack --os-cloud={cloud name} router create {router_name}
```

Add subnet to the router and set the router's external gateway using PUBLICNET to allow outbound network access.

``` shell
openstack --os-cloud={cloud name} router add subnet {router_name} {subnet_name}
```

Set the external gateway

``` shell
openstack --os-cloud={cloud name} router set --external-gateway PUBLICNET {router_name}
```
