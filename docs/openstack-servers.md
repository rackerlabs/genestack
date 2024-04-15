# Openstack Servers

To read more about Openstack Servers using the [upstream docs](https://docs.openstack.org/python-openstackclient/latest/cli/command-objects/server.html).

#### List and view servers

``` shell
openstack server list
    [--quote {all,minimal,none,nonnumeric}]
    [--reservation-id <reservation-id>]
    [--ip <ip-address-regex>]
    [--ip6 <ip-address-regex>]
    [--name <name-regex>]
    [--instance-name <server-name>]
    [--status <status>]
    [--flavor <flavor>]
    [--image <image>]
    [--host <hostname>]
    [--all-projects]
    [--project <project>]
    [--project-domain <project-domain>]
    [--user <user>]
    [--user-domain <user-domain>]
    [--long]
    [-n]
    [--marker <server>]
    [--limit <num-servers>]
    [--deleted]
    [--changes-since <changes-since>]
```

#### Create a new server

``` shell
openstack server create
    (--image <image> | --volume <volume>)
    --flavor <flavor>
    [--security-group <security-group>]
    [--key-name <key-name>]
    [--property <key=value>]
    [--file <dest-filename=source-filename>]
    [--user-data <user-data>]
    [--availability-zone <zone-name>]
    [--block-device-mapping <dev-name=mapping>]
    [--nic <net-id=net-uuid,v4-fixed-ip=ip-addr,v6-fixed-ip=ip-addr,port-id=port-uuid,auto,none>]
    [--network <network>]
    [--port <port>]
    [--hint <key=value>]
    [--config-drive <config-drive-volume>|True]
    [--min <count>]
    [--max <count>]
    [--wait]
    <server-name>
```

#### Delete a server

``` shell
openstack server delete [--wait] <server> [<server> ...]
```

# Launch a server from a snapshot

Please visit the Openstack Snapshot page [here](openstack-snapshot.md).

# Launch a server from a volume

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
