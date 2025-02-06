# Volume QoS Policies

## LVM


### Example QoS policy for LVM driver volume type

In order to apply a QoS policy to the `lvmdriver-1` volume type, you must first create the QoS policy.

``` shell
root@openstack-node-0:~# kubectl --namespace openstack exec -ti openstack-admin-client -- openstack volume qos create --consumer "both" --property "read_iops_sec_per_gb=1" --property "write_iops_sec_per_gb=1" lvmdriver-1-iops
+------------+-----------------------------------------------------+
| Field      | Value                                               |
+------------+-----------------------------------------------------+
| consumer   | both                                                |
| id         | b35fdf9c-d5bd-40f9-ae3a-8605c246ef2e                |
| name       | lvmdriver-1-iops                                    |
| properties | read_iops_sec_per_gb='1', write_iops_sec_per_gb='1' |
+------------+-----------------------------------------------------+
```

Once you have created the QoS policy, apply it to the `lvmdriver-1` volume type.
The command will utilize the `QOS_ID` and `VOLUME_TYPE_ID`.

``` shell
root@openstack-node-0:~# kubectl --namespace openstack exec -ti openstack-admin-client -- openstack volume qos associate b35fdf9c-d5bd-40f9-ae3a-8605c246ef2e 6af6ade2-53ca-4260-8b79-1ba2f208c91d
```

## NetAPP ONTAP

The most recent releases of the ONTAP driver (OpenStack Train and higher) allow QoS policies to be set per volume at the Cinder volume type rather than trying to utilize a QoS policy created on a target NetApp device. For a more detailed explanation, consult [NetApp Cinder QoS Concepts](https://netapp-openstack-dev.github.io/openstack-docs/train/cinder/key_concepts/section_cinder-key-concepts.html#qos-spec)

### Example QoS policy for NetApp ONTAP volume type

In order to apply a QoS policy to the `netapp-1` volume type, you must first create the QoS policy.

``` shell
root@openstack-node-0:~# kubectl --namespace openstack exec -ti openstack-admin-client -- openstack volume qos create --consumer "back-end" --property "peakIOPSperGiB=8" --property "expectedIOPSperGiB=7" netapp-qos
+------------+--------------------------------------------+
| Field      | Value                                      |
+------------+--------------------------------------------+
| consumer   | back-end                                   |
| id         | 9435160f-0e4a-4486-88b0-d6beb022732a       |
| name       | netapp-qos                                 |
| properties | expectedIOPSperGiB='7', peakIOPSperGiB='8' |
+------------+--------------------------------------------+
```

`expectedIOPSperGiB=7` was chosen because the target IOPSperGiB or expectedIOPSperGiB will be observed to be `5 IOPSperGiB` or `5,000 IOPS` when running FIO tests. Likewise, the `peakIOPSperGiB=8` was chosen because it is a value of `1` over the `expectedIOPSperGiB=7` and will effectively cap a burst in IOPs to an actual observerd value of `6 IOPSperGiB` or `6,000 IOPS`.

``` shell
root@openstack-node-0:~# kubectl --namespace openstack exec -ti openstack-admin-client -- openstack volume type show 1bdb5364-ed04-4bbe-8e41-9c5fae148c3d
+--------------------+----------------------------------------+
| Field              | Value                                  |
+--------------------+----------------------------------------+
| access_project_ids |                                        |
| description        | None                                   |
| id                 | 1bdb5364-ed04-4bbe-8e41-9c5fae148c3d   |
| is_public          | False                                  |
| name               | netapp-1                               |
| properties         | volume_backend_name='netapp-1-backend' |
| qos_specs_id       | None                                   |
+--------------------+----------------------------------------+
```

Once you have created the QoS policy, apply it to the `netapp-1` volume type.
The command will utilize the `QOS_ID` and `VOLUME_TYPE_ID`.

``` shell
root@openstack-node-0:~# kubectl --namespace openstack exec -ti openstack-admin-client -- openstack volume qos associate 9435160f-0e4a-4486-88b0-d6beb022732a 1bdb5364-ed04-4bbe-8e41-9c5fae148c3d
root@openstack-node-0:~# kubectl --namespace openstack exec -ti openstack-admin-client -- openstack volume type show 1bdb5364-ed04-4bbe-8e41-9c5fae148c3d
+--------------------+----------------------------------------+
| Field              | Value                                  |
+--------------------+----------------------------------------+
| access_project_ids |                                        |
| description        | None                                   |
| id                 | 1bdb5364-ed04-4bbe-8e41-9c5fae148c3d   |
| is_public          | False                                  |
| name               | netapp-1                               |
| properties         | volume_backend_name='netapp-1-backend' |
| qos_specs_id       | 9435160f-0e4a-4486-88b0-d6beb022732a   |
+--------------------+----------------------------------------+
```

## Disassociate a QoS policy from a volume type

In order to delete a QoS policy, you must first disassociate it from any volume types that it has been associated with.

``` shell
root@openstack-node-0:~# kubectl --namespace openstack exec -ti openstack-admin-client -- openstack volume qos disassociate --volume-type 1bdb5364-ed04-4bbe-8e41-9c5fae148c3d 9435160f-0e4a-4486-88b0-d6beb022732a
root@openstack-node-0:~# kubectl --namespace openstack exec -ti openstack-admin-client -- openstack volume type show 1bdb5364-ed04-4bbe-8e41-9c5fae148c3d
+--------------------+----------------------------------------+
| Field              | Value                                  |
+--------------------+----------------------------------------+
| access_project_ids |                                        |
| description        | None                                   |
| id                 | 1bdb5364-ed04-4bbe-8e41-9c5fae148c3d   |
| is_public          | False                                  |
| name               | netapp-1                               |
| properties         | volume_backend_name='netapp-1-backend' |
| qos_specs_id       | None                                   |
+--------------------+----------------------------------------+
```

## Delete a QoS policy

``` shell
root@openstack-node-0:~# kubectl --namespace openstack exec -ti openstack-admin-client -- openstack volume qos delete 9435160f-0e4a-4486-88b0-d6beb022732a
```
