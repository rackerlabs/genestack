# Create and Use Flex Block Storage Snapshots

Previous section: [Prepare Your Flex Block Storage Volume](prepare-your-flex-block-storage-volume.md)

A snapshot is a copy made of your volume at a specific moment in time. It contains the full directory structure of the volume. Each subsequent snapshot on a volume is a delta that captures the changes from the previous snapshot. You can use snapshots as incremental backups of your volumes, as restore points for your data, as long-term storage, or as starting points for new Flex Block Storage volumes.

The first snapshot of a volume takes up only as much storage space as the data that fills it. For example, if you have a 1 TB volume with 500 GB of data on it, your snapshot is only 500 GB. When you create new volumes from a snapshot, the new volume must be of equal size or larger than the original volume. The new volume must also be in the same region, but it can be a different type.

!!! tip

    It is a good idea to detach your volume from your server before you take a snapshot. This is the safest method to prevent your server from writing information while you are backing it up, which could get your data out of sync. To detach your volume, see [Detach and Delete Flex Block Storage Volume](detach-and-delete-flex-block-storage-volume.md).

    More advanced users might sync the file system to ensure the integrity of the data on your snapshots. Performing a sync flushes file system buffers and writes the data out to disk:

    ``` shell
    sync
    ```

## Create a snapshot

1. Log in to the Skyline portal.

    - SJC: [https://skyline.api.sjc3.rackspacecloud.com/](https://skyline.api.sjc3.rackspacecloud.com/)
    - DFW: [https://skyline.api.dfw3.rackspacecloud.com/](https://skyline.api.dfw3.rackspacecloud.com/)
    - IAD: [https://skyline.api.iad3.rackspacecloud.com/](https://skyline.api.iad3.rackspacecloud.com/)

2. Click **Storage** in the main navigation.

3. Click **Volumes** in the Storage sub-navigation.

4. Click the name of the volume you want to snapshot.

5. From the Volume Details screen, click **More > Data Protection > Create Snapshot**.

6. Give the snapshot a name.

7. Click **Confirm** to create the snapshot.

!!! note

    The data in the snapshot is captured at the point in time when you click Create Snapshot. While the status shows "Creating", the snapshot already exists at that point in time. During this phase, the snapshot is being compressed and stored.

After the snapshot creation completes, you can safely re-attach your volume if you detached it.

!!! warning

    If a snapshot of a volume exists, you cannot delete the volume until you delete the snapshot.

## Create a volume from a snapshot

The volume you create from a snapshot must be the same size or larger and in the same region as the original volume. However, you may choose a different volume type.

1. In the Skyline portal, navigate to **Storage > Snapshots**.

2. Find the snapshot you want to use and click **Create Volume**.

3. Give your volume a name.

4. Select a volume type:

    | Volume Type       | Description                                      |
    | ----------------- | ------------------------------------------------ |
    | HA-Performance    | HA Block Performance with at rest encryption     |
    | HA-Standard       | HA Block Standard with at rest encryption        |
    | Performance       | Performance with LUKS encryption                 |
    | Standard          | Standard with LUKS encryption                    |
    | Capacity          | Capacity with LUKS encryption                    |

5. Click **Confirm** to create the volume.

The larger your volume, the longer it takes to create.

## Delete a snapshot

1. In the Skyline portal, navigate to **Storage > Snapshots**.

2. Find the snapshot you want to delete and click **Delete**.

3. Confirm the deletion.

## Next steps

- [Detach and Delete Cloud Block Storage Volumes](detach-and-delete-flex-block-storage-volume.md)
- [Create and Attach a Cloud Block Storage Volume](create-and-attach-a-flex-block-storage-volume.md)
