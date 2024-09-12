# Openstack Snapshots

#### Create a snapshot of the instance

!!! note

    If necessary, list the instances to view the instance name with the list server command above.

1. Shut down the source VM before you take the snapshot to ensure that all data is flushed to disk. Use the openstack server stop command to shut down the instance:

    ``` shell
    openstack --os-cloud={cloud name} server stop myInstance
    ```

2. Use the openstack server list command to confirm that the instance shows a SHUTOFF status.

3. Use the openstack server image create command to take a snapshot:

    ``` shell
    openstack --os-cloud={cloud name} server image create myInstance --name myInstanceSnapshot
    ```

    The above command creates the image myInstance by taking a snapshot of a running server.

4. Use the openstack image list command to check the status until the status is active:

    ``` shell
    openstack --os-cloud={cloud name} image list
    ```

#### Show Image Details

``` shell
openstack --os-cloud={cloud name} image show [--human-readable] <image>
```

#### Download the snapshot

!!! note

    Get the image id from the image list command (seen above).

Download the snapshot by using the image ID:

``` shell
openstack --os-cloud={cloud name} image save --file snapshot.raw {Image ID}
```

Make the image available to the new environment, either through HTTP or direct upload to a machine (scp).

#### Import the snapshot to the new env

In the new project or cloud environment, import the snapshot:

``` shell
openstack --os-cloud={cloud name} image create NEW_IMAGE_NAME \
  --container-format bare --disk-format qcow2 --file IMAGE_URL
```

#### Boot a new sever from the snapshot

In the new project or cloud environment, use the snapshot to create the new instance:

``` shell
openstack --os-cloud={cloud name} server create --flavor m1.tiny --image myInstanceSnapshot myNewInstance
```
