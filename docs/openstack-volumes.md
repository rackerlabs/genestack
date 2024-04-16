#Openstack Volumes

#### Boot instance from volume

You can create a bootable volume from an existing image, volume, or snapshot. This procedure shows you how to create a volume from an image and use the volume to boot an instance.

1. List available images, noting the ID of the image that you wish to use.

    ``` shell
    openstack image list
    ```

2. Create a bootable volume from the chosen image.

    ``` shell
    openstack volume create \
    --image {Image ID} --size 10 \
    test-volume
    ```

3. Create a server, specifying the volume as the boot device.

    ``` shell
    openstack server create \
    --flavor $FLAVOR --network $NETWORK \
    --volume {Volume ID}\
    --wait test-server
    ```

4. List volumes once again to ensure the status has changed to in-use and the volume is correctly reporting the attachment.

    ``` shell
    openstack volume list
    ```

    ``` shell
    openstack server volume list test-server
    ```
# Additional Server Volume Commands

#### Add Volume to Server

``` shell
openstack server add volume
    [--device <device>]
    [--tag <tag>]
    [--enable-delete-on-termination | --disable-delete-on-termination]
    <server>
    <volume>
```

#### Remove Volume from Server

``` shell
openstack server remove volume <server> <volume>
```
