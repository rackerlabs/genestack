# Object Store Management using the OpenStack client

## Goal

Use the command-line utility `openstack` to perform operations on your object store.

## Prerequisites

Ensure you have followed the instructions in [OpenStack Getting Started with CLI](openstack-getting-started-cli.md) and ensure that you can authenticate.

## OpenStack client documentation

``` shell
openstack --help --os-cloud $CLOUD container $COMMAND

openstack --help --os-cloud $CLOUD object $COMMAND
```

### Useful commands

| commands         | description                     |
|------------------|---------------------------------|
| container list   | List containers                 |
| container set    | Set container properties        |
| container unset  | Unset container properties      |
| container show   | Display container details       |
| container create | Create new container            |
| container save   | Save container contents locally |
| container delete | Delete container                |
| object list      | List objects                    |
| object set       | Set object properties           |
| object unset     | Unset object properties         |
| object show      | Display object details          |
| object create    | Upload object to container      |
| object save      | Save (download) object locally  |
| object delete    | Delete object from container    |

For a more detailed explanation of any specific command, add `--help`:

``` shell
openstack --help --os-cloud $CLOUD object $COMMAND
```

!!! example

    ``` shell
    $ openstack --help --os-cloud $CLOUD object list

    usage: openstack object list [-h] [-f {csv,df-to-csv,json,table,value,yaml}]
                                 [-c COLUMN] [--format-config-file FORMAT_CONFIG]
                                 [--quote {all,minimal,none,nonnumeric}] [--noindent]
                                 [--max-width <integer>] [--fit-width] [--print-empty]
                                 [--sort-column SORT_COLUMN] [--sort-ascending |
                                 --sort-descending] [--prefix <prefix>]
                                 [--delimiter <delimiter>] [--limit <limit>]
                                 [--marker <marker>] [--end-marker <end-marker>] [--long]
                                 [--all]
                                 <container>

    List objects

    positional arguments:
      <container>   Container to list

    options:
      -h, --help            show this help message and exit
      --prefix <prefix>
                            Filter list using <prefix>
      --delimiter <delimiter>
                            Roll up items with <delimiter>
      --limit <limit>
                            The maximum number of entries to return. If the value exceeds the server-
                            defined maximum, then the maximum value will be used.
      --marker <marker>
                            The first position in the collection to return results from. This should be a
                            value that was returned in a previous request.
      --end-marker <end-marker>
                            End anchor for paging
      --long                List additional fields in output
      --all                 List all objects in container (default is 10000)
    ... (continues)

    ```

### Create an object container

Create the container named "flex-container01":
``` shell
openstack --os-cloud $CLOUD container create flex-container01
```

If you like, make the container public:

!!! note

    Note that it's much simpler to create a public container than to attempt to set it public after it's created.

However, you can use either the [swift client](storage-object-store-swift-cli.md), or the [skyline GUI](storage-object-store-skyline-gui.md) to accomplish this.

``` shell
openstack --os-cloud $CLOUD container create --public flex-container01
```

Verify the container's configuration:
``` shell
openstack --os-cloud $CLOUD container show flex-container01
```

### Upload a file to the container

Upload the entire contents of a folder to the container:
``` shell
openstack --os-cloud $CLOUD object create flex-container01 example/*
```

!!! example

    ``` shell
    $ openstack --os-cloud $CLOUD object create flex-container01 example/*
    +---------------------+------------------+------------------------------------+
    | obje                | container        | etag                               |
    +---------------------+------------------+------------------------------------+
    | example/example.txt | flex-container01 | "f5222fe12bc675311e17201856a10219" |
    +---------------------+------------------+------------------------------------+
    ```

Uploading an entire folder will add that prefix to your filenames inside the container.
``` shell
openstack --os-cloud $CLOUD object list flex-container01
```

!!! example

    ``` shell
    $ openstack --os-cloud $CLOUD object list flex-container01
    +---------------------+
    | Name                |
    +---------------------+
    | example.rtf         |
    | example/example.txt |
    +---------------------+
    ```

Filter the display of files only with the prefix by using the `--prefix` argument:
``` shell
openstack --os-cloud $CLOUD object list flex-container01 --prefix example
```

!!! example

    ``` shell
    $ openstack --os-cloud $CLOUD object list flex-container01 --prefix example
    +---------------------+
    | Name                |
    +---------------------+
    | example/example.txt |
    +---------------------+
    ```

### Downloading files
When the container is public, you can access each file using a specific URL, made up of your region's endpoint, the name of your container, the prefix (if any) of your object, and finally, the object name.
``` shell
<REGIONAL_ENDPOINT>/storage/container/detail/flex-container01/example.rtf
```

Download a single file from the container:
``` shell
openstack --os-cloud $CLOUD object save flex-container01 example.rtf
```

### Deleting containers or objects
``` shell
openstack --os-cloud $CLOUD object delete flex-container01 example.rtf
```

!!! example

    ``` shell
    $ openstack --os-cloud $CLOUD object delete flex-container01 example.rtf
    ```

Deleting a container:
``` shell
openstack --os-cloud $CLOUD container delete flex-container01
```

!!! example

    ``` shell
    $ openstack --os-cloud $CLOUD container delete flex-container01
    ```

If you need to delete a non-empty container, you'll need to issue the `--recursive` flag. Without this flag, the container must already be empty.

!!! example

    ``` shell
    $ openstack --os-cloud $CLOUD container --recursive delete flex-container01
    ```

### Setting and removing object expiration
At this time, setting and removing object expiration can be done using the the [swift client](storage-object-store-swift-cli.md).

## Additional documentation

Additional documentation can be found at the official openstack client site, on the Openstack Documentation Site.\
https://docs.openstack.org/python-openstackclient/ussuri/cli/command-objects/container.html\
https://docs.openstack.org/python-openstackclient/ussuri/cli/command-objects/object.html
