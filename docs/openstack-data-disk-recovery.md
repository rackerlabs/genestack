# Instance Data Disk Recovery

Below is an operational guide for OpenStack operators who need to mount (and later unmount) a virtual machine’s data disk for recovery or data inspection. This procedure leverages the Linux Network Block Device (NBD) module (`nbd`) in conjunction with the `qemu-nbd` utility. It assumes intermediate Linux system administration skills and familiarity with OpenStack’s Nova instance storage locations.

## Overview

In an OpenStack environment, each Nova instance’s disk is typically stored under `/var/lib/nova/instances/<INSTANCE_ID>`. Mounting a VM disk directly on a hypervisor or another server can be useful when you need to:

- Recover files from a corrupted or inaccessible instance.
- Inspect or troubleshoot data that may be causing issues within the VM.
- Perform forensics or backups on a specific partition.

The following instructions outline how to attach a VM disk image as a block device, mount it to the filesystem, and then cleanly detach it afterward.

## Prerequisites

1. **Root or Sudo Access**: You must have sufficient privileges to run `modprobe`, `qemu-nbd`, and mount commands.
2. **qemu-nbd Installed**: The `qemu-utils` or `qemu-kvm` package (depending on your distribution) must be installed to provide the `qemu-nbd` command.
3. **Identify the Correct Instance Disk**: Ensure you have the correct path to the VM’s disk file under `/var/lib/nova/instances`.

!!! note

    Always confirm the instance UUID (`00000000-0000-0000-0000-000000000000` in the examples) corresponds to the target VM.

## Mounting the VM Disk (Attach Procedure)

Before mounting the VM disk, you need to connect the disk file to a Network Block Device (NBD) and then mount the desired partition. It is recommended that be done only on instances that are powered off.

### Load the NBD Kernel Module

``` shell
modprobe nbd max_part=8
```

- `nbd` is the Network Block Device driver.
- `max_part=8` ensures up to eight partitions can be recognized on each NBD device.

### Connect qemu-nbd to the Disk File

``` shell
qemu-nbd --connect=/dev/nbd0 /var/lib/nova/instances/00000000-0000-0000-0000-000000000000/disk
```

- This command associates the instance disk file with the `/dev/nbd0` block device.

#### Identify Partitions** (Optional but recommended)

``` shell
fdisk /dev/nbd0 -l
```

- Lists all partitions on `/dev/nbd0`, helping you determine which partition to mount.
- Commonly, the first partition is `/dev/nbd0p1`, the second `/dev/nbd0p2`, etc.

### Create a Mount Point

``` shell
mkdir /mnt/00000000-0000-0000-0000-000000000000
```

- Make a new directory where you will mount the disk’s partition.

### Mount the Desired Partition

``` shell
mount /dev/nbd0p1 /mnt/00000000-0000-0000-0000-000000000000
```

- Adapts to whichever partition (`p1`, `p2`, etc.) you need to access.
- At this point, you can navigate to `/mnt/00000000-0000-0000-0000-000000000000` and inspect or recover data.

## Unmounting the VM Disk (Detach Procedure)

When your recovery or data inspection is complete, you should properly unmount the disk and detach the NBD device.

### Unmount the Partition

``` shell
umount /mnt/00000000-0000-0000-0000-000000000000
```

- Ensure no processes are accessing the mount point before unmounting.

### Remove the Mount Point Directory

``` shell
rmdir /mnt/00000000-0000-0000-0000-000000000000
```

- This step is optional but helps keep the filesystem clean.

### Disconnect the qemu-nbd Association

``` shell
qemu-nbd --disconnect /dev/nbd0
```

- Frees the `/dev/nbd0` device from the disk file.

### Remove the NBD Module

``` shell
rmmod nbd
```

- Unloads the `nbd` kernel module if no longer needed.
- This helps prevent accidental reuse of `/dev/nbd0` by another process.

## Additional Considerations

1. **Data Consistency**: Mounting an active disk used by a running VM can lead to data corruption if the VM is simultaneously writing to that disk. Ideally, power off the VM or ensure the disk is not in active use before performing these steps.
2. **Multiple Partitions**: If you have more than one partition (e.g., root on `/dev/nbd0p1`, swap on `/dev/nbd0p2`), mount only the partition(s) you specifically need.
3. **Filesystem Type**: If you encounter errors mounting the filesystem (e.g., an unsupported or unfamiliar file system type), consider specifying the filesystem with `-t`, such as `mount -t ext4 /dev/nbd0p1 /mnt/...`.
4. **Cleanup**: Always remember to unmount and disconnect when finished. Leaving a disk mounted can risk accidental data changes or locks.

## Conclusion

Mounting a VM’s data disk using `qemu-nbd` in an OpenStack environment can greatly simplify recovery, troubleshooting, or forensic efforts. By safely attaching and detaching the disk file, operators can inspect and manipulate VM data without having to boot the instance. With the above procedure, you can maintain a secure, controlled environment for delicate recovery operations.
