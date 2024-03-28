# Swift Object Store

## Goal

Use the command-line utility `swift` to perform operations on your object store.

## Requirements

TBD

## Swift client documentation

```shell
swift --help
```

### Useful commands

| command      | description                                                                                                                         |
|--------------|-------------------------------------------------------------------------------------------------------------------------------------|
| list         | Lists the containers for the account or the objects for a container.                                                                |
| capabilities | Retrieve capability of the proxy.                                                                                                   |
| post         | Updates meta information for the account, container, or object.<br>If the container is not found, it will be created automatically. |
| stat         | Displays information for the account, container, or object.                                                                         |
| upload       | Uploads specified files and directories to the given container.                                                                     |
| download     | Download objects from containers.                                                                                                   |
| tempurl      | Generates a temporary URL for a Swift object.                                                                                       |
| delete       | Delete a container or objects within a container.                                                                                   |

For a more detailed explanation of any specific command, add `--help` after it:

```shell
swift list --help
```

```example
Usage: swift list [--long] [--lh] [--totals] [--prefix <prefix>]
                  [--delimiter <delimiter>] [--header <header:value>]
                  [--versions] [<container>]

Lists the containers for the account or the objects for a container.

Positional arguments:
  [<container>]           Name of container to list object in.

Optional arguments:
  -l, --long            Long listing format, similar to ls -l.
  --lh                  Report sizes in human readable format similar to
                        ls -lh.
  -t, --totals          Used with -l or --lh, only report totals.
  -p <prefix>, --prefix <prefix>
                        Only list items beginning with the prefix.
  -d <delim>, --delimiter <delim>
                        Roll up items with the given delimiter. For containers
                        only. See OpenStack Swift API documentation for what
                        this means.
  -j, --json            Display listing information in json
  --versions            Display listing information for all versions
  -H, --header <header:value>
                        Adds a custom request header to use for listing.
```

### Create an object container

Create the container named "flex-container01":
```shell
swift post flex-container01
```

If you like, make the container public:
```shell
swift post --header "X-Container-Read: .r:*" flex-container01
```

Verify the container's configuration:
```shell
swift stat flex-container01
```

```example
INSERT EXAMPLE
```

### Upload files to the container

Upload the entire contents of a folder to the container:
```shell
swift upload flex-container01 example-files/
```

```example
example-docs/readme.md
example-docs/image01.jpg
example-docs/image02.png
```

Uploading an entire folder will add that prefix to your filenames inside the container.
```shell
swift list flex-container01
```

```example
example-docs/readme.md
example-docs/image01.jpg
example-docs/image02.png
document01.rtf
document02.rtf
```

Filter the display of files only with the prefix by using the `--prefix` argument:
```shell
swift list flex-container01 --prefix example-docs
```

```example
example-docs/readme.md
example-docs/image01.jpg
example-docs/image02.png
```

### Downloading files
When the container is public, you can access each file using a specific URL, made up of your region's endpoint, the name of your container, the prefix (if any) of your object, and finally, the object name.
```shell
<REGIONAL_ENDPOINT>/v1/AUTHxxx/flex-container01/example-docs/readme.md
```

Using the swift client to download a single file:
```shell
swift download flex-container01 document01.rtf
```

Using the swift client to download multiple files with the same prefix:
```shell
swift download flex-container01 --prefix example-docs
```

### Deleting containers or objects
```shell
swift delete flex-container01 document01.rtf
```
```example
document01.rtf
```
Similar to downloading, you can delete multiple files with the same prefix:
```shell
swift delete flex-container01 example-docs/*
```
```example
example-docs/readme.md
example-docs/image01.jpg
example-docs/image02.png
```
Deleting a container:
```shell
swift delete flex-container01
```
```example
document01.rtf
document02.rtf
```
Deleting a container will delete all files in the container.

## Additional documentation

Additional documentation can be found at the official swift client site, on the Openstack Documentation Site.<br>
https://docs.openstack.org/python-openstackclient/latest/
