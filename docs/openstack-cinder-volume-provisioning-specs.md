# Set Volume Type Provisioning Specifications

*Before* creating a volume within any volume type, the provisioning specifications must be set.

## Minimum and Maximum volume size

These specifications are set in the volume type. The following commands constrain the `lvmdriver-1` volume type to a size between 10 GB and 2 TB.

``` shell
root@openstack-node-0:~# kubectl --namespace openstack exec -ti openstack-admin-client -- openstack volume type set --property provisioning:min_vol_size=10 6af6ade2-53ca-4260-8b79-1ba2f208c91d
root@openstack-node-0:~# kubectl --namespace openstack exec -ti openstack-admin-client -- openstack volume type set --property provisioning:max_vol_size=2048 6af6ade2-53ca-4260-8b79-1ba2f208c91d
```

## Sample Provisioning Script

``` shell
#!/bin/bash

openstack volume type create --description 'Capacity with LUKS encryption' --encryption-provider luks --encryption-cipher aes-xts-plain64 --encryption-key-size 256 --encryption-control-location front-end --property volume_backend_name=LVM_iSCSI --property provisioning:max_vol_size='2048' --property provisioning:min_vol_size='100' Capacity
openstack volume type create --description 'Standard with LUKS encryption' --encryption-provider luks --encryption-cipher aes-xts-plain64 --encryption-key-size 256 --encryption-control-location front-end --property volume_backend_name=LVM_iSCSI --property provisioning:max_vol_size='2048' --property provisioning:min_vol_size='10' Standard
openstack volume type create --description 'Performance with LUKS encryption' --encryption-provider luks --encryption-cipher aes-xts-plain64 --encryption-key-size 256 --encryption-control-location front-end --property volume_backend_name=LVM_iSCSI --property provisioning:max_vol_size='2048' --property provisioning:min_vol_size='10' Performance


openstack volume qos create --property read_iops_sec_per_gb='1' --property write_iops_sec_per_gb='1' Capacity-Block
openstack volume qos create --property read_iops_sec_per_gb='5' --property write_iops_sec_per_gb='5' Standard-Block
openstack volume qos create --property read_iops_sec_per_gb='10' --property write_iops_sec_per_gb='10' Performance-Block

openstack volume qos associate Capacity-Block Capacity
openstack volume qos associate Standard-Block Standard
openstack volume qos associate Performance-Block Performance

openstack volume type set --private __DEFAULT__
```
