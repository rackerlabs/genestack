# Return to Service - Auto Close

```
Hello {{ customer_name }},

This message is to inform you that your Flex Block Storage device, {{ service_name }}, {{ item }} has been returned to service.

If your volume remains in a read-only state, take the following actions in listed order to return it to a read-write state:

Please Note: to avoid risk of data corruption, customers must unmount affected storage volumes PRIOR TO the file system check.

(1) Unmount the storage volume
(2) Run a file system check (linux: fsck, Windows: chkdsk)
(3) Remount the volume in read-write mode.

If your Flex Block Storage device will not mount in read-write mode after a filesystem check, we recommend rebooting.

Boot from Volume Servers Only: If the server will not boot, or the filesystem remains stuck in read-only mode after a reboot, you should take the following actions in listed order to return the server to an Active state:

(1) Note the Flex Block Storage Volume's details
(2) Shut the server down
(3) Detach the volume from within the portal
(4) Re-attach the volume from within the portal to the /dev/vda position by expanding the 'Advanced Options' link and entering /dev/vda into the field provided
(5) Once the volume shows as attached, issue a reboot to the server

If we can help you increase redundancy in your environment or if we can do anything else to assist you, please contact a member of our support team by visiting us in live-chat at https://mycloud.rackspace.com/ or contacting us using the telephone number below.

Please reference this incident ID if you need to contact support: FLEXHD-{{ id }}

Best Regards,
The Rackspace Cloud
US Toll Free: 1-800-961-4454
International: +44-20-8734-4345
```
