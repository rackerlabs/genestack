# Set Volume Type Specifications

## Example: NetApp ONTAP driver volume specifications (deduplication and compression)

To set additional properties on a NetApp volume type, use the following syntax to set and unset properties

``` shell

root@openstack-node-0:~# kubectl --namespace openstack exec -ti openstack-admin-client -- openstack volume type set --property netapp_dedup='true' <VOLUME_TYPE_ID>

root@openstack-node-0:~# kubectl --namespace openstack exec -ti openstack-admin-client -- openstack volume type set --property netapp_compression='true' <VOLUME_TYPE_ID>

root@openstack-node-0:~# kubectl --namespace openstack exec -ti openstack-admin-client -- openstack volume type unset --property netapp_dedup <VOLUME_TYPE_ID>

root@openstack-node-0:~# kubectl --namespace openstack exec -ti openstack-admin-client -- openstack volume type unset --property netapp_compression <VOLUME_TYPE_ID>
```

