# Create Flavors

These are the default flavors expected in an OpenStack cloud. Customize these flavors based on your needs. See the upstream admin [docs](https://docs.openstack.org/nova/latest/admin/flavors.html) for more information on managing flavors.

``` shell
openstack --os-cloud default flavor create --public m1.extra_tiny --ram 512 --disk 0 --vcpus 1 --ephemeral 0 --swap 0
openstack --os-cloud default flavor create --public m1.tiny --ram 1024 --disk 10 --vcpus 1 --ephemeral 0 --swap 0
openstack --os-cloud default flavor create --public m1.small --ram 2048 --disk 20 --vcpus 2 --ephemeral 0 --swap 0
openstack --os-cloud default flavor create --public m1.medium --ram 4096 --disk 40 --vcpus 4 --ephemeral 8 --swap 2048
openstack --os-cloud default flavor create --public m1.large --ram 8192 --disk 80 --vcpus 6 --ephemeral 16 --swap 4096
openstack --os-cloud default flavor create --public m1.extra_large --ram 16384 --disk 160 --vcpus 8 --ephemeral 32 --swap 8192
```
