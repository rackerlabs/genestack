# Openstack Floating Ips

To read more about Openstack Floating Ips using the [upstream docs](https://docs.openstack.org/python-openstackclient/pike/cli/command-objects/floating-ip.html).

#### List and view floating ips

``` shell
$ openstack floating ip list
    [--network <network>]
    [--port <port>]
    [--fixed-ip-address <ip-address>]
    [--long]
    [--status <status>]
    [--project <project> [--project-domain <project-domain>]]
    [--router <router>]
```

#### Create a floating ip

``` shell
$ openstack floating ip create
    [--subnet <subnet>]
    [--port <port>]
    [--floating-ip-address <ip-address>]
    [--fixed-ip-address <ip-address>]
    [--description <description>]
    [--project <project> [--project-domain <project-domain>]]
    <network>
```

#### Delete a floating ip(s)

!!! note

    Ip address or ID can be used to specify which ip to delete.


``` shell
$ openstack floating ip delete <floating-ip> [<floating-ip> ...]
```

#### Floating ip set

Set floating IP properties

``` shell
$ openstack floating ip set
    --port <port>
    [--fixed-ip-address <ip-address>]
    <floating-ip>
```

#### Display floating ip details

``` shell
$ openstack floating ip show <floating-ip>
```

#### Unset floating IP Properties

``` shell
$ openstack floating ip unset
    --port
    <floating-ip>
```

#### Associate floating IP addresses

You can assign a floating IP address to a project and to an instance.

Associate an IP address with an instance in the project, as follows:

``` shell
$ openstack server add floating ip INSTANCE_NAME_OR_ID FLOATING_IP_ADDRESS
```

#### Disassociate floating IP addresses

To disassociate a floating IP address from an instance:

``` shell
$ openstack server remove floating ip INSTANCE_NAME_OR_ID FLOATING_IP_ADDRESS
```
To remove the floating IP address from a project:

``` shell
$ openstack floating ip delete FLOATING_IP_ADDRESS
```
