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

#### Create a snapshot of the instance

!!! note

    If necessary, list the instances to view the instance name with the list server command above.

1. Shut down the source VM before you take the snapshot to ensure that all data is flushed to disk. Use the openstack server stop command to shut down the instance:

    ``` shell
    openstack server stop myInstance
    ```

2. Use the openstack server list command to confirm that the instance shows a SHUTOFF status.

3. Use the openstack server image create command to take a snapshot:

    ``` shell
    openstack server image create myInstance --name myInstanceSnapshot
    ```

    The above command creates the image myInstance by taking a snapshot of a running server.

4. Use the openstack image list command to check the status until the status is active:

    ``` shell
    openstack image list
    ```

#### Download the snapshot

!!! note

    Get the image id from the image list command (seen above).

Download the snapshot by using the image ID:

``` shell
openstack image save --file snapshot.raw {Image ID}
```

Make the image available to the new environment, either through HTTP or direct upload to a machine (scp).

#### Import the snapshot to the new env

In the new project or cloud environment, import the snapshot:

``` shell
openstack image create NEW_IMAGE_NAME \
  --container-format bare --disk-format qcow2 --file IMAGE_URL
```

#### Boot a new sever from the snapshot

In the new project or cloud environment, use the snapshot to create the new instance:

``` shell
openstack server create --flavor m1.tiny --image myInstanceSnapshot myNewInstance
```

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
