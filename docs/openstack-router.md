# Openstack Router

Read more about Openstack Routers using the [upstream docs](https://docs.openstack.org/python-openstackclient/latest/cli/command-objects/router.html).

#### Get List of Routers

``` shell
openstack router list
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
openstack router create
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
openstack router add gateway
    [--fixed-ip subnet=<subnet>,ip-address=<ip-address>]
    <router>
    <network>
```

#### Add a Subnet to Router

``` shell
openstack router add subnet <router> <subnet>
```

#### Add a Port to Router

``` shell
openstack router add port <router> <port>
```

#### Set Router Properties

``` shell
openstack router set
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
openstack router add subnet <router> <subnet>
```
