# Return to Service - Auto Close

```text
Hello {{ customer_name }},

Your Flex Block Storage volume,
{{ service_name }}, {{ item }} has been returned to service.

If your volume is in a read-only state, take the following actions in
listed order to return it to a read-write state:

Please Note: to avoid risk of data corruption, customers must unmount affected
storage volumes PRIOR TO the file system check.

(1) Unmount the storage volume
(2) Run a file system check (linux: fsck, Windows: chkdsk)
(3) Remount the volume in read-write mode.

If your Flex Block Storage device will not mount in read-write mode after a
filesystem check, we recommend rebooting the associated virtual machine server.

Boot from Volume Servers Only:

If the server will not boot, or the filesystem is stuck in read-only mode after
a reboot, take the following actions in listed order to return the virtual
machine server to an Active state:

(1) Note the Flex Block Storage volume's details
(2) Shut the virtual server down
(3) Detach the volume
(4) Re-attach the volume to virtual server
(5) Once the volume is attached ('in-use'), start the server

Please reference this incident ID if you need to contact support: FLEXHD-{{ id }}

Best Regards,
The Rackspace Cloud
US Toll Free: 1-800-961-4454
International: +44-20-8734-4345
```
