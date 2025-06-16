# Decommission a Cinder Block Node

Reference this guide when decommissioning or cleaning off an existing
Cinder block node.

## Determine how RAID is being constructed:

	1. mdraid passthrough with PERC
	2. Additional volume groups through physical RAID card (usually /dev/sdb)

Determine SCSI based drives (usually under hardware raid controller)

``` console
root@block-node:~# lsblk -S
NAME HCTL       TYPE VENDOR   MODEL            REV SERIAL                           TRAN
sda  0:2:0:0    disk DELL     PERC H740P Mini 5.16 00d2f42fec4627702b00454e3e80e04e 
sdb  0:2:1:0    disk DELL     PERC H740P Mini 5.16 00fb4d2eab6420862d00454e3e80e04e 
```

Determine mdraid device

```console
root@block-node:~# lsblk -Mpa -e 7
    NAME         MAJ:MIN RM   SIZE RO TYPE   MOUNTPOINTS
    /dev/sda       8:0    0 446.6G  0 disk   
    ├─/dev/sda1    8:1    0   200M  0 part   /boot/efi
    ├─/dev/sda2    8:2    0     1M  0 part   
    └─/dev/sda3    8:3    0 446.4G  0 part   /
    /dev/sdb       8:16   0   2.9T  0 disk   
    /dev/nbd0     43:0    0     0B  0 disk   
    /dev/nbd1     43:32   0     0B  0 disk   
    /dev/nbd2     43:64   0     0B  0 disk   
    /dev/nbd3     43:96   0     0B  0 disk   
    /dev/nbd4     43:128  0     0B  0 disk   
    /dev/nbd5     43:160  0     0B  0 disk   
    /dev/nbd6     43:192  0     0B  0 disk   
    /dev/nbd7     43:224  0     0B  0 disk   
┌┈▶ /dev/nvme0n1 259:0    0   3.5T  0 disk   
├┈▶ /dev/nvme1n1 259:1    0   3.5T  0 disk   
├┈▶ /dev/nvme2n1 259:2    0   3.5T  0 disk   
└┬▶ /dev/nvme3n1 259:3    0   3.5T  0 disk   
 └┈┈/dev/md127     9:127  0     7T  0 raid10 
    /dev/nvme4n1 259:4    0   3.5T  0 disk   
    /dev/nvme5n1 259:5    0   3.5T  0 disk   
    /dev/nvme6n1 259:6    0   3.5T  0 disk   
    /dev/nvme8n1 259:7    0   3.5T  0 disk   
    /dev/nvme9n1 259:8    0   3.5T  0 disk   
    /dev/nvme7n1 259:9    0   3.5T  0 disk   
    /dev/nbd8     43:256  0     0B  0 disk   
    /dev/nbd9     43:288  0     0B  0 disk   
    /dev/nbd10    43:320  0     0B  0 disk   
    /dev/nbd11    43:352  0     0B  0 disk   
    /dev/nbd12    43:384  0     0B  0 disk   
    /dev/nbd13    43:416  0     0B  0 disk   
    /dev/nbd14    43:448  0     0B  0 disk   
    /dev/nbd15    43:480  0     0B  0 disk   

root@block-node:~# cat /proc/mdstat
Personalities : [raid10] [linear] [multipath] [raid0] [raid1] [raid6] [raid5] [raid4] 
md127 : active raid10 nvme0n1[0] nvme2n1[2] nvme1n1[1] nvme3n1[3]
      7501210624 blocks super 1.2 512K chunks 2 near-copies [4/2] [UUUU]
      bitmap: 0/56 pages [0KB], 65536KB chunk

unused devices: <none>
```

!!! note

    In this example, the mdraid device is confirmed to be `/dev/md127`. This path
    will be used exclusively throughout this document; however, `/dev/md127` should be
    substituted with actual mdraid device found on the block node being decommissioned

``` console
root@block-node:~# mdadm --detail <MDRAID_DEVICE>
root@block-node:~# mdadm --detail /dev/md127
```

## Remove PVs and VGs

Determine which disks or mdraid array PVs cinder-volumes-1 volume group is assigned to

``` console
root@block-node:~# pvs
```

Remove cinder-volumes-1 volume group from PVs

``` console
root@block-node:~# vgremove cinder-volumes-1
```

Remove PV from disks and mdraid arrays

``` console
root@block-node:~# pvremove /dev/sdb
root@block-node:~# pvremove /dev/md127
```

There should no longer be a PV/VG/LVM filesystem on the disk (/dev/sdb) and mdraid

## Zero disks under hardware raid controller

Write zeros to disks in a screen session (/dev/sdb not mdraid)

``` console
root@block-node:~# dd if=/dev/zero of=/dev/sdb bs=4096 status=progress
```

## Resize mdraid

In another screen session, manipulate mdraid group size. In order to accomplish this, the mdraid needs to be reduced.

Check existing mdraid array size

``` console
root@block-node:~# mdadm --detail /dev/md127

/dev/md127:
           Version : 1.2
     Creation Time : Fri Apr 12 02:03:10 2024
        Raid Level : raid10
        Array Size : 16877726208 (15.72 TiB 17.28 TB)
     Used Dev Size : 3750605824 (3.49 TiB 3.84 TB)
      Raid Devices : 9
     Total Devices : 10
       Persistence : Superblock is persistent

     Intent Bitmap : Internal

       Update Time : Thu Jun  5 14:54:50 2025
             State : clean 
    Active Devices : 9
   Working Devices : 10
    Failed Devices : 0
     Spare Devices : 1

            Layout : near=2
        Chunk Size : 512K

Consistency Policy : bitmap

              Name : data
              UUID : 5710553f:c9aff9ef:647edd34:2c3966a5
            Events : 18404

    Number   Major   Minor   RaidDevice State
       0     259        0        0      active sync   /dev/nvme0n1
       1     259        1        1      active sync   /dev/nvme1n1
       2     259        2        2      active sync   /dev/nvme2n1
       3     259        3        3      active sync   /dev/nvme3n1
       4     259        4        4      active sync   /dev/nvme4n1
       5     259        5        5      active sync   /dev/nvme5n1
       6     259        6        6      active sync   /dev/nvme6n1
       7     259        9        7      active sync   /dev/nvme7n1
       8     259        7        8      active sync   /dev/nvme8n1

       9     259        8        -      spare   /dev/nvme9n1
```

### Reduce mdraid array size to current mdraid size on compute nodes

``` console
root@block-node:~# mdadm --grow /dev/md127 --array-size 7501210624
```

Now that the mdraid array size is smaller, the number of disks can be reduced to 4

``` console
root@block-node:~# mdadm --grow -n4 /dev/md127 --backup-file /root/mdadm.md127.backup

root@block-node:~# mdadm --detail /dev/md127

/dev/md127:
           Version : 1.2
     Creation Time : Fri Apr 12 02:03:10 2024
        Raid Level : raid10
        Array Size : 7501210624 (6.99 TiB 7.68 TB)
     Used Dev Size : 3750605312 (3.49 TiB 3.84 TB)
      Raid Devices : 4
     Total Devices : 10
       Persistence : Superblock is persistent

     Intent Bitmap : Internal

       Update Time : Thu Jun  5 15:21:52 2025
             State : clean, reshaping 
    Active Devices : 9
   Working Devices : 10
    Failed Devices : 0
     Spare Devices : 1

            Layout : near=2
        Chunk Size : 512K

Consistency Policy : bitmap

    Reshape Status : 0% complete
     Delta Devices : -5, (9->4)

              Name : data
              UUID : 5710553f:c9aff9ef:647edd34:2c3966a5
            Events : 18406

    Number   Major   Minor   RaidDevice State
       0     259        0        0      active sync set-A   /dev/nvme0n1
       1     259        1        1      active sync set-B   /dev/nvme1n1
       2     259        2        2      active sync set-A   /dev/nvme2n1
       3     259        3        3      active sync set-B   /dev/nvme3n1

       4     259        4        4      active sync set-A   /dev/nvme4n1
       5     259        5        5      active sync set-B   /dev/nvme5n1
       6     259        6        6      active sync set-A   /dev/nvme6n1
       7     259        9        7      active sync set-B   /dev/nvme7n1
       8     259        7        8      active sync set-A   /dev/nvme8n1
       9     259        8        -      spare   /dev/nvme9n1
```

!!! note

    NOTE: Reshape of the Array will take hours (approximately 12 hours). WAIT UNTIL THIS IS COMPLETE before removing disks

## Remove extra nvme drives from mdraid

Once Reshape has completed:

Drives 4-9 can be removed. Drives 0, 1, 2, 3 are now the actual active drives.

``` console
root@block-node:~# mdadm /dev/md127 --fail /dev/nvme4n1
root@block-node:~# mdadm /dev/md127 --fail /dev/nvme5n1
root@block-node:~# mdadm /dev/md127 --fail /dev/nvme6n1
root@block-node:~# mdadm /dev/md127 --fail /dev/nvme7n1
root@block-node:~# mdadm /dev/md127 --fail /dev/nvme8n1
root@block-node:~# mdadm /dev/md127 --fail /dev/nvme9n1

root@block-node:~# mdadm /dev/md127 --remove /dev/nvme4n1
root@block-node:~# mdadm /dev/md127 --remove /dev/nvme5n1
root@block-node:~# mdadm /dev/md127 --remove /dev/nvme6n1
root@block-node:~# mdadm /dev/md127 --remove /dev/nvme7n1
root@block-node:~# mdadm /dev/md127 --remove /dev/nvme8n1
root@block-node:~# mdadm /dev/md127 --remove /dev/nvme9n1
```

## Stop and disable Cinder components

``` console
root@block-node:~# systemctl stop cinder-volume-netapp
root@block-node:~# systemctl stop cinder-volume
root@block-node:~# systemctl stop cinder-backup

root@block-node:~# systemctl disable cinder-volume-netapp
root@block-node:~# systemctl disable cinder-volume
root@block-node:~# systemctl disable cinder-backup
```

## Remove Cinder virtualenv and conf

``` console
root@block-node:~# rm -rf /etc/cinder
root@block-node:~# rm -rf /opt/cinder
root@block-node:~# rm -rf /var/lib/cinder
```

## Update initramfs

``` console
root@block-node:~# mdadm --detail --scan > /etc/mdadm/mdadm.conf
root@block-node:~# update-initramfs -u -k all
```
