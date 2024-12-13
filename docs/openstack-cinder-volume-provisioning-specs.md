# Set Volume Type Provisioning Specifications

*Before* creating a volume within any volume type, the provisioning specifications must be set.

## Minimum and Maximum volume size

These specifications are set in the volume type. The following commands constrain the `lvmdriver-1` volume type to a size between 10 GB and 2 TB.

``` shell
root@openstack-node-0:~# kubectl --namespace openstack exec -ti openstack-admin-client -- openstack volume type set --property provisioning:min_vol_size=10 6af6ade2-53ca-4260-8b79-1ba2f208c91d
root@openstack-node-0:~# kubectl --namespace openstack exec -ti openstack-admin-client -- openstack volume type set --property provisioning:max_vol_size=2048 6af6ade2-53ca-4260-8b79-1ba2f208c91d
```
