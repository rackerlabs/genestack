# Creating Different Neutron Network Types

The following commands are examples of creating several different network types.
NOTE: When creating the subnet we are specifically limiting neutrons ability to attach
ip's from Shared Provider networks directly to instances with --service-type.  If you want
to attach Shared Provider Network's ip's directly to instances, remove lines beginning with
--service-type

## Create Shared Provider Networks

### Flat Network

``` shell
openstack --os-cloud default network create --share \
                                            --availability-zone-hint az1 \
                                            --external \
                                            --provider-network-type flat \
                                            --provider-physical-network physnet1 \
                                            flat
```

#### Flat Subnet

``` shell
openstack --os-cloud default subnet create --subnet-range 172.16.24.0/22 \
                                           --gateway 172.16.24.2 \
                                           --dns-nameserver 172.16.24.2 \
                                           --allocation-pool start=172.16.25.150,end=172.16.25.200 \
                                           --dhcp \
                                           --network flat \
                                           --service-type network:floatingip \
                                           --service-type network:router_gateway \
                                           --service-type network:distributed \
                                           flat_subnet
```

### VLAN Network

``` shell
openstack --os-cloud default network create --share \
                                            --availability-zone-hint az1 \
                                            --external \
                                            --provider-segment 404 \
                                            --provider-network-type vlan \
                                            --provider-physical-network physnet1 \
                                            vlan404
```

#### VLAN Subnet

``` shell
openstack --os-cloud default subnet create --subnet-range 10.10.10.0/23 \
                                           --gateway 10.10.10.1 \
                                           --dns-nameserver 10.10.10.1 \
                                           --allocation-pool start=10.10.11.10,end=10.10.11.254 \
                                           --dhcp \
                                           --network vlan404 \
                                           --service-type network:floatingip \
                                           --service-type network:router_gateway \
                                           --service-type network:distributed \
                                           vlan404_subnet
```

## Creating Tenant type networks

### L3 (Tenant) Network

``` shell
openstack --os-cloud default network create l3
```

#### L3 (Tenant) Subnet

``` shell
openstack --os-cloud default subnet create --subnet-range 10.0.10.0/24 \
                                           --gateway 10.0.10.1 \
                                           --dns-nameserver 1.1.1.1 \
                                           --allocation-pool start=10.0.10.2,end=10.0.10.254 \
                                           --dhcp \
                                           --network l3 \
                                           l3_subnet
```
