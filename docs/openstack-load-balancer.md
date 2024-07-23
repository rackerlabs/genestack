# Openstack Load Balancers

To read more about Openstack load balancers please visit the [upstream docs](https://docs.openstack.org/python-openstackclient/latest/cli/plugin-commands/octavia.html).

### Create a Load Balancer

``` shell
openstack --os-cloud {user cloud name} loadbalancer create
    [--name <name>]
    [--description <description>]
    [--vip-address <vip_address>]
    [--vip-port-id <vip_port_id>]
    [--vip-subnet-id <vip_subnet_id>]
    [--vip-network-id <vip_network_id>]
    [--vip-qos-policy-id <vip_qos_policy_id>]
    [--additional-vip subnet-id=<name-or-uuid>[,ip-address=<ip>]]
    [--project <project>]
    [--provider <provider>]
    [--availability-zone <availability_zone>]
    [--enable | --disable]
    [--flavor <flavor>]
    [--wait]
    [--tag <tag> | --no-tag]
```

### List Load Balancers

``` shell
openstack --os-cloud {user cloud name} loadbalancer list
    [--sort-column SORT_COLUMN]
    [--sort-ascending | --sort-descending]
    [--name <name>]
    [--enable | --disable]
    [--project <project-id>]
    [--vip-network-id <vip_network_id>]
    [--vip-subnet-id <vip_subnet_id>]
    [--vip-qos-policy-id <vip_qos_policy_id>]
    [--vip-port-id <vip_port_id>]
    [--provisioning-status {ACTIVE,ERROR,PENDING_CREATE,PENDING_UPDATE,PENDING_DELETE}]
    [--operating-status {ONLINE,DRAINING,OFFLINE,DEGRADED,ERROR,NO_MONITOR}]
    [--provider <provider>]
    [--flavor <flavor>]
    [--availability-zone <availability_zone>]
    [--tags <tag>[,<tag>,...]]
    [--any-tags <tag>[,<tag>,...]]
    [--not-tags <tag>[,<tag>,...]]
    [--not-any-tags <tag>[,<tag>,...]]
```

### Delete Load Balancers

``` shell
openstack --os-cloud {user cloud name} loadbalancer delete [--cascade] [--wait] <load_balancer>
```

### Show Load Balancer's Details

``` shell
openstack --os-cloud {user cloud name} loadbalancer show <load_balancer>
```

### Update Load Balancer

``` shell
openstack --os-cloud {user cloud name} loadbalancer set
    [--name <name>]
    [--description <description>]
    [--vip-qos-policy-id <vip_qos_policy_id>]
    [--enable | --disable]
    [--wait]
    [--tag <tag>]
    [--no-tag]
    <load_balancer>
 ```

### Create Load Balancer Listener

``` shell
openstack --os-cloud {user cloud name} loadbalancer listener create
    [--name <name>]
    [--description <description>]
    --protocol
    {TCP,HTTP,HTTPS,TERMINATED_HTTPS,UDP,SCTP,PROMETHEUS}
    [--connection-limit <limit>]
    [--default-pool <pool>]
    [--default-tls-container-ref <container_ref>]
    [--sni-container-refs [<container_ref> ...]]
    [--insert-headers <header=value,...>]
    --protocol-port <port>
    [--timeout-client-data <timeout>]
    [--timeout-member-connect <timeout>]
    [--timeout-member-data <timeout>]
    [--timeout-tcp-inspect <timeout>]
    [--enable | --disable]
    [--client-ca-tls-container-ref <container_ref>]
    [--client-authentication {NONE,OPTIONAL,MANDATORY}]
    [--client-crl-container-ref <client_crl_container_ref>]
    [--allowed-cidr [<allowed_cidr>]]
    [--wait]
    [--tls-ciphers <tls_ciphers>]
    [--tls-version [<tls_versions>]]
    [--alpn-protocol [<alpn_protocols>]]
    [--hsts-max-age <hsts_max_age>]
    [--hsts-include-subdomains]
    [--hsts-preload]
    [--tag <tag> | --no-tag]
    <loadbalancer>
 ```

### List Load Balancer Listeners

``` shell
openstack --os-cloud {user cloud name} loadbalancer listener list
    [--sort-column SORT_COLUMN]
    [--sort-ascending | --sort-descending]
    [--name <name>]
    [--loadbalancer <loadbalancer>]
    [--enable | --disable]
    [--project <project>]
    [--tags <tag>[,<tag>,...]]
    [--any-tags <tag>[,<tag>,...]]
    [--not-tags <tag>[,<tag>,...]]
    [--not-any-tags <tag>[,<tag>,...]]
```

### Delete Load Balancer Listeners

``` shell
openstack loadbalancer listener delete [--wait] <listener>
```
