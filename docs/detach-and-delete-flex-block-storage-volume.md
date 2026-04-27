# Detach and Delete Flex Block Storage Volumes

## Detach a volume from a server

!!! warning

    Unmount the volume from within the server's operating system before detaching it to avoid data corruption.

1. Log in to the Skyline portal.

    - SJC: [https://skyline.api.sjc3.rackspacecloud.com/](https://skyline.api.sjc3.rackspacecloud.com/)
    - DFW: [https://skyline.api.dfw3.rackspacecloud.com/](https://skyline.api.dfw3.rackspacecloud.com/)
    - IAD: [https://skyline.api.iad3.rackspacecloud.com/](https://skyline.api.iad3.rackspacecloud.com/)

2. Click **Storage** in the main navigation.

3. Click **Volumes** in the Storage sub-navigation.

4. Click the name of the volume you want to detach.

5. From the Volume Details screen, click **More > Instance Related > Detach**.

6. Confirm the detach action.

The volume status will return to `available` and can be re-attached to another server.

## Delete a volume

A volume must be in `available` status (detached) before it can be deleted.

1. Log in to the Skyline portal.

    - SJC: [https://skyline.api.sjc3.rackspacecloud.com/](https://skyline.api.sjc3.rackspacecloud.com/)
    - DFW: [https://skyline.api.dfw3.rackspacecloud.com/](https://skyline.api.dfw3.rackspacecloud.com/)
    - IAD: [https://skyline.api.iad3.rackspacecloud.com/](https://skyline.api.iad3.rackspacecloud.com/)

2. Click **Storage** in the main navigation.

3. Click **Volumes** in the Storage sub-navigation.

4. Select the volume you want to delete.

5. Click **Delete** and confirm the action.

The volume will be permanently removed. This action cannot be undone.

## Detach an operating system disk that uses the boot-from-volume functionality

If your server boots from a Block Storage Volume and you need to detach the boot volume. In this case, you will not be able to detach the boot volume, even if you shutdown your instance, you will not be able to detach it.
