# Openstack Images

To read more about Openstack images please visit the [upstream docs](https://docs.openstack.org/python-openstackclient/latest/cli/command-objects/image-v1.html#image-create).

#### List and view images

``` shell
openstack --os-cloud={cloud name} image list
    [--sort-column SORT_COLUMN]
    [--sort-ascending | --sort-descending]
    [--public | --private]
    [--property <key=value>]
    [--long]
    [--sort <key>[:<direction>]]
```

#### View image details

``` shell
openstack --os-cloud={cloud name} image show <imageName>
```

#### Create a image

``` shell
openstack --os-cloud={cloud name} image create
    [--id <id>]
    [--store <store>]
    [--container-format <container-format>]
    [--disk-format <disk-format>]
    [--size <size>]
    [--min-disk <disk-gb>]
    [--min-ram <ram-mb>]
    [--location <image-url>]
    [--copy-from <image-url>]
    [--file <file> | --volume <volume>]
    [--force]
    [--checksum <checksum>]
    [--protected | --unprotected]
    [--public | --private]
    [--property <key=value>]
    [--project <project>]
    <image-name>
```

#### Delete a image

``` shell
openstack --os-cloud={cloud name} image delete <image> [<image> ...]
```

#### Retrieving Images

Please visit this page for examples of retrieving images [here](https://docs.openstack.org/image-guide/obtain-images.html).

#### Creating a server from an image

Specify the server name, flavor ID, and image ID.

``` shell
openstack --os-cloud={cloud name} server create --flavor FLAVOR_ID --image IMAGE_ID --key-name KEY_NAME \
  --user-data USER_DATA_FILE --security-group SEC_GROUP_NAME --property KEY=VALUE \
  INSTANCE_NAME
```
