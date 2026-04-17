# Create and Attach a Flex Block Storage Volume

In Rackspace Flex Block Storage, powered by OpenStack Cinder, you work with volumes. Volumes are detachable block storage devices that expand the storage capacity of your server. Similar to a USB drive, a volume may only be attached to one server at a time and retains its data even when not attached.

Volume types and their performance characteristics are defined by your cloud operator. Each type may have different QoS policies, size constraints, and capabilities. Common examples are as below.

| Volume Type    | Max Size | Min Size | QoS Properties                                                           |
| -------------- | -------- | -------- | ------------------------------------------------------------------------ |
| Capacity       | 2TB      | 100GB    | READ: 1 IOPS per second per GiB, WRITE: 1 IOPS per second per GiB       |
| Standard       | 2TB      | 10GB     | READ: 5 IOPS per second per GiB, WRITE: 5 IOPS per second per GiB       |
| Performance    | 2TB      | 10GB     | READ: 10 IOPS per second per GiB, WRITE: 10 IOPS per second per GiB     |
| HA-Standard    | 2TB      | 5GB      | Absolute Minimum IOPS: 128, Absolute Peak IOPS per GiB: 20              |
| HA-Performance | 2TB      | 5GB      | Absolute Minimum IOPS: 256, Absolute Peak IOPS per GiB: 40              |

Available in regions: IAD, DFW, SJC

!!! note "IAD region difference"

    In the IAD region, the Capacity volume type has `WRITE: 2 IOPS per second per GiB` instead of 1.

!!! note

    Volumes can only be attached to servers in the same availability zone. Confirm the name and availability zone of the target server before creating a volume.

## Prerequisites
- A running server to attach the volume to.

## Create a volume

1. Log in to the Skyline portal.

    - SJC: [https://skyline.api.sjc3.rackspacecloud.com/](https://skyline.api.sjc3.rackspacecloud.com/)
    - DFW: [https://skyline.api.dfw3.rackspacecloud.com/](https://skyline.api.dfw3.rackspacecloud.com/) 
    - IAD: [https://skyline.api.iad3.rackspacecloud.com/](https://skyline.api.iad3.rackspacecloud.com/) 

2. Click **Storage** in the main navigation.

3. Click **Volumes** in the Storage sub-navigation.

4. Click the **Create Volume** button.

5. Give your volume a name.

6. Select the availability zone. Volumes can be attached only to servers in the same availability zone.

7. Select a volume type:

    | Volume Type       | Description                                      |
    | ----------------- | ------------------------------------------------ |
    | HA-Performance    | HA Block Performance with at rest encryption     |
    | HA-Standard       | HA Block Standard with at rest encryption        |
    | Performance       | Performance with LUKS encryption                 |
    | Standard          | Standard with LUKS encryption                    |
    | Capacity          | Capacity with LUKS encryption                    |

8. Select the size of the volume, from 5 GB to 2 TB depending on their types.

9. Click the **Create Volume** button. The larger your volume, the longer it may take to create. When your volume is created, a green Available icon displays under Status on the Volume Details page.

## View volume details

The Volume Details screen displays basic information about the volume. Here you can see the Volume's Status, what server it may be attached to, its size, status, and type. Additionally, if your volume is attached to a Linux server, you can see its path.

The Volume Details screen displays by default once you create the volume. You can also see a volume's details by clicking its name in the Volumes list (Storage > Volumes).

The top section of the Volume Detail page displays the following fields:

| Field         | Description                                                              |
| ------------- | ------------------------------------------------------------------------ |
| ID            | The unique identifier of the volume                                      |
| Name          | The name of the volume                                                   |
| Status        | Current state: `In-use`, `Available`, `Creating`, `Deleting`, `Error`    |
| Type          | The volume type (e.g. Standard, Capacity, Performance, HA-Standard, HA-Performance) |
| Description   | User-provided description of the volume                                  |
| Size          | Size of the volume (e.g. 40GiB)                                         |
| Encrypted     | Whether the volume is encrypted (Yes/No)                                 |
| Shared        | Whether the volume is shared (Yes/No)                                    |
| Created At    | Timestamp when the volume was created                                    |

### Status

This section displays the status of your volume. Possible statuses are:

- **Building** – Volume is still being created.
- **Available** – Volume is created, but not attached.
- **In-Use** – Volume is attached to a server.
- **Deleting** – Volume is being deleted.

Below the summary, the Detail tab contains additional sections:

### Attachments Info

In the Detail tab of the Volume Details screen, the Attachments Info column displays the attachment status of your volume:

- **Attached To** – Shows the device path and the server name the volume is attached to (e.g. `/dev/vda on test-instance`). You can click the server name to view the server's details.
- When the volume is not attached, this field displays `-`.

## Attach the volume to a server

When the volume is created, it exists by itself and cannot have any data written to it. The volume must be attached to a server in the same region before anything else can be done with it. The process for attaching a volume is the same for all servers. After you attach the volume, you must partition, format, and mount it, which we cover on the next page.

1. From the Volume Details screen, click **More > Instance Related > Attach Volume** link.

2. Click the dot next to a server name to select it.

3. Click the **OK** button to attach the volume.

It may take a few minutes to attach your volume to your server. While the Flex Block Storage volume is attaching, its status bar will be yellow in the Block Storage Volumes list. When it is done attaching, its status bar will turn green and the name of the server it is attached to displays under the heading Attached to.

To detach and delete the volume, see [Detach and Delete Flex Block Storage Volumes](detach-and-delete-flex-block-storage-volume.md).

## Next steps

- [Volume QoS Policies](openstack-cinder-volume-qos-policies.md) — understand performance tiers
- [Volume Provisioning Specs](openstack-cinder-volume-provisioning-specs.md) — size constraints and policies
- [Volume Type Specs](openstack-cinder-volume-type-specs.md) — additional volume type properties
- [OpenStack Snapshot](openstack-snapshot.md) — create snapshots of your volumes
