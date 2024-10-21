# FIPS Enabled Cinder Storage (LUKS)

!!! note

    Genestack ships with Barbican key manager enabled by default for Cinder and Nova services. No further configuration is needed.

??? warning "LUKS encrypted volumes are currently only supported in iSCSI workloads."
    Ceph RBD is needs additional testing.  NFS backed Cinder volumes are known not to work:"

     * https://review.opendev.org/c/openstack/cinder/+/597148
     * https://review.opendev.org/c/openstack/cinder/+/749155
     * https://bugs.launchpad.net/nova/+bug/1987311
     * https://review.opendev.org/c/openstack/nova/+/854030

To create a FIPS enabled Cinder front end to be consumed by clients the folllowing command is run:

!!! note

    These set of commands is ran against our standard LVM iSCSI deployment covered in [Genestack Cinder LVM iSCSI](https://docs.rackspacecloud.com/openstack-cinder-lvmisci/) With modified commands to be run after cinder service is deployed on your storage nodes.

```shell
# kubectl --namespace openstack exec -ti openstack-admin-client -- openstack volume type create --encryption-provider luks \
--encryption-cipher aes-xts-plain64 --encryption-key-size 256 \
--encryption-control-location front-end --property volume_backend_name=LVM_iSCSI lvmdriver-1
```

```shell
+-------------+-----------------------------------------------------------------------------------------------------------------------------------------------+
| Field       | Value                                                                                                                                         |
+-------------+-----------------------------------------------------------------------------------------------------------------------------------------------+
| description | None                                                                                                                                          |
| encryption  | cipher='aes-xts-plain64', control_location='front-end', encryption_id='766bcb86-db37-4e7b-841c-df50e5d5c069', key_size='256', provider='luks' |
| id          | 66573d74-2f30-4a89-b51a-382ec6a371b6                                                                                                          |
| is_public   | True                                                                                                                                          |
| name        | lvmdriver-1                                                                                                                                   |
| properties  | volume_backend_name='LVM_iSCSI'                                                                                                               |
+-------------+-----------------------------------------------------------------------------------------------------------------------------------------------+
```

Verify functionality of encrypted volume

```shell
kubectl --namespace openstack exec -ti openstack-admin-client -- openstack volume create --size 1 test
```

```shell
+---------------------+--------------------------------------+
| Field               | Value                                |
+---------------------+--------------------------------------+
| attachments         | []                                   |
| availability_zone   | nova                                 |
| bootable            | false                                |
| consistencygroup_id | None                                 |
| created_at          | 2024-10-17T20:01:19.233106           |
| description         | None                                 |
| encrypted           | True                                 |
| id                  | 7b2a9061-bcb8-46d2-8b20-ecc70b35da7d |
| migration_status    | None                                 |
| multiattach         | False                                |
| name                | test                                 |
| properties          |                                      |
| replication_status  | None                                 |
| size                | 1                                    |
| snapshot_id         | None                                 |
| source_volid        | None                                 |
| status              | creating                             |
| type                | lvmdriver-1                          |
| updated_at          | None                                 |
| user_id             | 70ac20d4fa234a67bed220f80cef1cb6     |
+---------------------+--------------------------------------+
```

Verify encryption field after volume is created:

```shell
# kubectl --namespace openstack exec -ti openstack-admin-client -- openstack volume show 7b2a9061-bcb8-46d2-8b20-ecc70b35da7d
+--------------------------------+---------------------------------------------------------------+
| Field                          | Value                                                         |
+--------------------------------+---------------------------------------------------------------+
| attachments                    | []                                                            |
| availability_zone              | nova                                                          |
| bootable                       | false                                                         |
| consistencygroup_id            | None                                                          |
| created_at                     | 2024-10-17T20:01:19.000000                                    |
| description                    | None                                                          |
| encrypted                      | True                                                          |
| id                             | 7b2a9061-bcb8-46d2-8b20-ecc70b35da7d                          |
| migration_status               | None                                                          |
| multiattach                    | False                                                         |
| name                           | test                                                          |
| os-vol-host-attr:host          | genestack-storage1.lab.underworld.local@lvmdriver-1#LVM_iSCSI |
| os-vol-mig-status-attr:migstat | None                                                          |
| os-vol-mig-status-attr:name_id | None                                                          |
| os-vol-tenant-attr:tenant_id   | 2f3dd2e07f2e4a96af2f8392984e5149                              |
| properties                     |                                                               |
| replication_status             | None                                                          |
| size                           | 1                                                             |
| snapshot_id                    | None                                                          |
| source_volid                   | None                                                          |
| status                         | available                                                     |
| type                           | lvmdriver-1                                                   |
| updated_at                     | 2024-10-17T20:01:20.000000                                    |
| user_id                        | 70ac20d4fa234a67bed220f80cef1cb6                              |
+--------------------------------+---------------------------------------------------------------+
```

Extra verification, steps done on LVM iSCSI node

```shell
root@genestack-storage1:~# lsblk
NAME                                                          MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
loop0                                                           7:0    0 63.9M  1 loop /snap/core20/2105
loop1                                                           7:1    0 63.9M  1 loop /snap/core20/2318
loop3                                                           7:3    0 40.4M  1 loop /snap/snapd/20671
loop4                                                           7:4    0   87M  1 loop /snap/lxd/28373
loop5                                                           7:5    0 38.8M  1 loop /snap/snapd/21759
loop6                                                           7:6    0   87M  1 loop /snap/lxd/29351
nbd0                                                           43:0    0    0B  0 disk
nbd1                                                           43:32   0    0B  0 disk
nbd2                                                           43:64   0    0B  0 disk
nbd3                                                           43:96   0    0B  0 disk
nbd4                                                           43:128  0    0B  0 disk
nbd5                                                           43:160  0    0B  0 disk
nbd6                                                           43:192  0    0B  0 disk
nbd7                                                           43:224  0    0B  0 disk
xvda                                                          202:0    0   60G  0 disk
├─xvda1                                                       202:1    0 59.9G  0 part /
├─xvda14                                                      202:14   0    4M  0 part
└─xvda15                                                      202:15   0  106M  0 part /boot/efi
xvdb                                                          202:16   0   12M  0 disk
└─xvdb1                                                       202:17   0   10M  0 part
xvdc                                                          202:32   0  100G  0 disk
└─cinder--volumes--1-7b2a9061--bcb8--46d2--8b20--ecc70b35da7d 253:0    0    1G  0 lvm
nbd8                                                           43:256  0    0B  0 disk
nbd9                                                           43:288  0    0B  0 disk
nbd10                                                          43:320  0    0B  0 disk
nbd11                                                          43:352  0    0B  0 disk
nbd12                                                          43:384  0    0B  0 disk
nbd13                                                          43:416  0    0B  0 disk
nbd14                                                          43:448  0    0B  0 disk
nbd15                                                          43:480  0    0B  0 disk
root@genestack-storage1:~# dd if=/dev/mapper/cinder--volumes--1-7b2a9061--bcb8--46d2--8b20--ecc70b35da7d of=/root/verify-luks bs=1M
1024+0 records in
1024+0 records out
1073741824 bytes (1.1 GB, 1.0 GiB) copied, 4.75154 s, 226 MB/s
root@genestack-storage1:~# head /root/verify-luks
LUKS??aesxts-plain64sha256 ?76???N??_voTa?"M??}?? <SNIP>
```
