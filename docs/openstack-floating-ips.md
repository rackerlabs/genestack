# Openstack Floating Ips

To read more about Openstack Floating Ips using the [upstream docs](https://docs.openstack.org/python-openstackclient/latest/cli/command-objects/floating-ip.html).

#### List and view floating ips

``` shell
openstack --os-cloud={cloud name} floating ip list
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
openstack --os-cloud={cloud name} floating ip create
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
openstack --os-cloud={cloud name} floating ip delete <floating-ip> [<floating-ip> ...]
```

#### Floating ip set

Set floating IP properties

``` shell
openstack --os-cloud={cloud name} floating ip set
    --port <port>
    [--fixed-ip-address <ip-address>]
    <floating-ip>
```

#### Display floating ip details

``` shell
openstack --os-cloud={cloud name} floating ip show $VIP
```

#### Unset floating IP Properties

``` shell
openstack --os-cloud={cloud name} floating ip unset --port $VIP
```

#### Associate floating IP addresses

You can assign a floating IP address to a project and to an instance.

Associate an IP address with an instance in the project, as follows:

``` shell
openstack --os-cloud={cloud name} server add floating ip $INSTANCE_UUID $VIP
```

#### Disassociate floating IP addresses

To disassociate a floating IP address from an instance:

``` shell
openstack --os-cloud={cloud name} server remove floating ip $INSTANCE_UUID $VIP
```

To remove the floating IP address from a project:

``` shell
openstack --os-cloud={cloud name} floating ip delete $VIP
```

#### Floating Ip Example

Below is a quick example of how we can assign floating ips.

You will need to get your cloud name from your `clouds.yaml`. More information on this can be found [here](build-test-envs.md). Underneath "clouds:" you will find your cloud name.

First create a floating ip either from PUBLICNET or the public ip pool.

``` shell
openstack --os-cloud={cloud name} floating ip create PUBLICNET
```

Second get the cloud server UUID.

``` shell
openstack --os-cloud={cloud name} server list
```

Third add the floating ip to the server

``` shell
openstack --os-cloud={cloud name} server add floating ip $UUID $VIP
```

#### Shared floating IP and virtual IP

You can often use a load balancer instead of a shared floating IP or virtual IP.
For advanced networking needs, using an instance that does something like you
might do with a network appliance operating system, you might need a real shared
floating IP that two instances can share with something like _keepalived_, but
you should probably use a load balancer unless you actually need the additional
capabilities from a shared floating IP or virtual IP.

In _Genestack_ Flex, with OVN, you can implement a shared floating IP mostly as
standard for OpenStack, but Neutron's `allowed-address-pairs` depends on your
Neutron plugin, _ML2/OVN_ in this case, so while most OpenStack documentation
will show altering `allowed-address-pairs` with a CIDR as seen
[here](https://docs.openstack.org/neutron/latest/admin/archives/introduction.html#allowed-address-pairs),
OVN doesn't support CIDRs on its equivalent to port security on logical switch
ports in its NB database, so you just have to use a single IP address instead of
a CIDR.

With that caveat, you can set up a shared floating IP like this:

1. Create a Neutron network

    ``` shell
    openstack --os-cloud={cloud name} network create tester-network
    ```

2. Create a subnet for the network

    ``` shell
    openstack --os-cloud={cloud name} subnet create --network tester-network \
                            --subnet-range $CIDR \
                            tester-subnet
    ```

3. Create servers on the network

    Create `tester1` server.

    ``` shell
    openstack --os-cloud={cloud name} server create tester1 --flavor m1.tiny \
                                    --key-name keypair \
                                    --network tester-network \
                                    --image $IMAGE_UUID
    ```

    Create `tester2` server.

    ``` shell
    openstack --os-cloud={cloud name} server create tester2 --flavor m1.tiny \
                                    --key-name keypair \
                                    --network tester-network \
                                    --image $IMAGE_UUID
    ```

4. Create a port with a fixed IP for the VIP.

    ``` shell
    openstack --os-cloud={cloud name} port create --fixed-ip subnet=tester-subnet \
                          --network tester-network \
                          --no-security-group tester-vip-port
    ```

   You will probably want to note the IP on the port here as your VIP.

5. Create a router

    You will typically need a router with an external gateway to use any
    public IP, depending on your configuration.

    ``` shell
    openstack --os-cloud={cloud name} router create tester-router
    ```

6. Add at external Internet gateway to the router

    At Rackspace, we usually call the public Internet network for instances
    PUBLICNET. You can use the name or ID that provides external networks
    for your own installation.

    ``` shell
    openstack --os-cloud={cloud name} router set --external-gateway PUBLICNET tester-router
    ```

7. Add the subnet to the router

    ``` shell
    openstack --os-cloud={cloud name} router add subnet tester-router tester-subnet
    ```

8. Create a floating IP for the port

    You can't do this step until you've created the router as above, because
    Neutron requires reachability between the subnet for the port and the
    floating IP for the network. If you followed in order, this should work
    here.

    ``` shell
    openstack --os-cloud={cloud name} floating ip create --port tester-vip-port PUBLICNET
    ```

    Note and retain the ID and/or IP returned, since you will need it for the
    next step.

9. Put the floating IP in the `allowed-address-pair` list of the ports for your
   two instances.

   Here, **specify only the VIP IP address**/**omit the netmask**. This deviates
   from other examples you may see, which may include a netmask, because it can
   vary with details of the plugin used with Neutron. For Neutron with ML2/OVN,
   you only specify the IP address here, without a netmask.

   You use the private VIP because the DNAT occurs before it reaches the
   instances.

   ``` shell
   openstack --os-cloud={cloud name} port list server tester1 # retrieve port UUID
   openstack --os-cloud={cloud name} port set --allowed-address ip-address=<VIP> <port1UUID>
   ```

   ``` shell
   openstack --os-cloud={cloud name} port list server tester2 # retrieve port UUID
   openstack --os-cloud={cloud name} port set --allowed-address ip-address=<VIP> <port2UUID>
   ```

The steps above complete creating the shared floating IP and VIP. The following
steps allow you to test it.

1. Create a bastion server.

    With the two test instances connected to a subnet on a router with an
    external gateway, they can reach the Internet, but you will probably need
    a server with a floating IP to reach these two servers to install and
    configure _keepalived_ and test your shared floating IP / VIP. This example
    shows only a test.

    ``` shell
    openstack --os-cloud={cloud name} server create tester-bastion --flavor m1.tiny \
                                           --key-name keypair \
                                           --network tester-network \
                                           --image $IMAGE_UUID
    ```

2. Add floating IP to bastion server.

    You can specify the UUID or IP of the floating IP.

     ``` shell
     openstack --os-cloud={cloud name} server add floating ip tester-bastion $UUID
     ```

3. Alter security group rules to allow SSH and ICMP:

    You will likely find you can't SSH to the floating IP you added to the
    instance unless you've altered your default security group or taken other
    steps because the default security group will prevent all ingress traffic.

    ``` shell
    openstack --os-cloud={cloud name} security group rule create --proto tcp \
                                         --dst-port 22 \
                                         --remote-ip 0.0.0.0/0 default
    ```

    Now enable ICMP.

    ``` shell
    openstack --os-cloud={cloud name} security group rule create --proto icmp \
                                         --dst-port -1 default
    ```

4. SSH to the first test instance from the bastion.

5. Configure the VIP on the interface as a test on the first test instance:

    ``` shell
    sudo ip address add $VIP/24 dev enp3s0
    ```

    Note that you add the internal VIP here, not the floating public IP. Use
    the appropriate netmask (usually /24 unless you picked something else.)

6. Ping the floating IP.

    Ping should now work. For a general floating IP on the Internet, you can
    usually ping from any location, so you don't necessarily have to use your
    bastion.

    ``` shell
    ping $VIP
    ```

    Since the ports for the two servers look almost identical, if it works on
    one, it should work on the other, so you can delete the IP from the first
    instance and try it on the second:

    ``` shell
    sudo ip address del $VIP/24 dev enp3s0
    ```

    You may need to ping the internal IP address from your bastion server or
    take other steps to take care of the ARP caches. You can use arping on
    the instance with the VIP for that:

    ``` shell
    sudo arping -i enp3s0 -U -S $VIP $VIP  # VIP twice
    ```

    and ^C/break out of it once ping starts working with the address.
