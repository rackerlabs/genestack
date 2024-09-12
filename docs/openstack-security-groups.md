# Openstack Security Groups

To read more about Openstack Security Groups using the [upstream docs](https://docs.openstack.org/nova/queens/admin/security-groups.html).

#### List and view current security groups

``` shell
openstack --os-cloud={cloud name} security group list
```

#### Create Security Groups

``` shell
openstack --os-cloud={cloud name} security group create SECURITY_GROUP_NAME --description GROUP_DESCRIPTION
```

#### Delete a specific Security Group

``` shell
openstack --os-cloud={cloud name} security group delete SECURITY_GROUP_NAME
```

#### Create and manage security group rules

To list the rules for a security group, run the following command:

``` shell
openstack --os-cloud={cloud name} security group rule list SECURITY_GROUP_NAME
```

Add a new group rule:

``` shell
openstack --os-cloud={cloud name} security group rule create SEC_GROUP_NAME \
    --protocol PROTOCOL --dst-port FROM_PORT:TO_PORT --remote-ip CIDR
```

The arguments are positional, and the from-port and to-port arguments specify the local port range connections are allowed to access, not the source and destination ports of the connection.

#### To allow both HTTP and HTTPS traffic:

``` shell
openstack --os-cloud={cloud name} security group rule create global_http \
    --protocol tcp --dst-port 443:443 --remote-ip 0.0.0.0/0
```

#### To allow SSH access to the instances, choose one of the following options:

1. Allow access from all IP addresses, specified as IP subnet 0.0.0.0/0 in CIDR notation:

    ``` shell
    openstack --os-cloud={cloud name} security group rule create SECURITY_GROUP_NAME \
      --protocol tcp --dst-port 22:22 --remote-ip 0.0.0.0/0
    ```
2. Allow access only from IP addresses from other security groups (source groups) to access the specified port:

     ``` shell
    openstack --os-cloud={cloud name} security group rule create SECURITY_GROUP_NAME \
      --protocol tcp --dst-port 22:22 --remote-group SOURCE_GROUP_NAME
    ```
#### To allow pinging of the instances, choose one of the following options:

1. Allow pinging from all IP addresses, specified as IP subnet 0.0.0.0/0 in CIDR notation

     ``` shell
    openstack --os-cloud={cloud name} security group rule create --protocol icmp \
    SECURITY_GROUP_NAME
    ```

    This allows access to all codes and all types of ICMP traffic.

2. Allow only members of other security groups (source groups) to ping instances.

     ``` shell
    openstack --os-cloud={cloud name} security group rule create --protocol icmp \
      --remote-group SOURCE_GROUP_NAME SECURITY_GROUP
    ```

#### To allow access through a UDP port, such as allowing access to a DNS server that runs on a VM, choose one of the following options:

1. Allow UDP access from IP addresses, specified as IP subnet 0.0.0.0/0 in CIDR notation.

     ``` shell
    openstack --os-cloud={cloud name} security group rule create --protocol udp \
      --dst-port 53:53 SECURITY_GROUP
    ```

2. Allow only IP addresses from other security groups (source groups) to access the specified port.

    ``` shell
    openstack --os-cloud={cloud name} security group rule create --protocol udp \
    --dst-port 53:53 --remote-group SOURCE_GROUP_NAME SECURITY_GROUP
    ```

####  Allow RDP access only from IP addresses from other security groups

    ``` shell
    openstack --os-cloud={cloud name} security group rule create SECURITY_GROUP_NAME \
      --protocol tcp --dst-port 33:89 --remote-group SOURCE_GROUP_NAME
    ```

#### Delete a security group rule

``` shell
openstack --os-cloud={cloud name} security group rule delete RULE_ID
```
