# Data-Loss – Auto Close

```
Hello {{ customer_name }},

This message is a follow-up to our previous notifications regarding Flex Block Storage device, {{ service_name }}, {{ item }}.

The host server failed and we were unable to recover data for your device.

Please reference this ID if you need to contact support: FLEXHD-{{ id }}

You have the option to deploy a new Cloud Block Storage device. (More details: https://docs.rackspacecloud.com/create-and-attach-a-cloud-block-storage-volume/)

Before a new Flex Block Storage device can be used in place of the current device, you may need to perform additional steps such as attaching the new device to an existing server and restoring from Cloud Backups. The current device will continue to incur billing until it is deleted.

If the Flex Block Storage device was the system disk for your server, you will need to delete the current server and system disk and redeploy. Your newly-deployed server will have new IPs. If you require your services to have a stable IP, we recommend deploying a Cloud Load Balancer and adding your servers behind the load balancer.

We apologize for any inconvenience this may cause you. If we can help you increase redundancy in your environment or if we can do anything else to help, please contact a member of our support team by visiting us in live-chat at https://mycloud.rackspace.com/ or by calling.

Best Regards,
The Rackspace Cloud
US Toll Free: 1-800-961-4454
International: +44-20-8734-4345
```
