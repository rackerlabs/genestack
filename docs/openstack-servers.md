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

#### Creating a Server with User Data

You can place user data in a local file and pass it through the --user-data <user-data-file> parameter at instance creation.

``` shell
openstack server create --image ubuntu-cloudimage --flavor 1 \
    --user-data mydata.file VM_INSTANCE
```

#### Creating a Server with Config drives

Config drives are special drives that are attached to an instance when it boots. The instance can mount this drive and read files from it to get information that is normally available through the metadata service.

To enable the config drive for an instance, pass the --config-drive true parameter to the openstack server create command.

The following example enables the config drive and passes a user data file and two key/value metadata pairs, all of which are accessible from the config drive:

``` shell
openstack server create --config-drive true --image my-image-name \
    --flavor 1 --key-name mykey --user-data ./my-user-data.txt \
    --property role=webservers --property essential=false MYINSTANCE
```

Read more about Openstack Config drives using the [upstream docs](https://docs.openstack.org/nova/latest/admin/config-drive.html).

#### Delete a server

``` shell
openstack server delete [--wait] <server> [<server> ...]
```

# Launch a server from a snapshot

Please visit the Openstack Snapshot page [here](openstack-snapshot.md).

# Launch a server from a volume

Please visit the Openstack Volumes page [here](openstack-volumes.md).

# Server Creation Example

Below is a quick example of how one could set up a server.

You will need to get your cloud name from your clouds.yaml. More information on this can be found [here](build-test-envs.md). Underneath "clouds:" you will find your cloud name.

First we are going to create our network "my_network"

``` shell
openstack --os-cloud={cloud_name} network create my_network
```

Second create the subnet "my_subnet"

``` shell
openstack --os-cloud={cloud_name} subnet create --ip-version 4 --subnet-range {cidr range} --network my_network my_subnet
```

Third create the router "my_router"

``` shell
openstack --os-cloud={cloud_name} router create my_router
```

Fourth add "my_subnet" to "my_router" and set the router's external gateway using PUBLICNET to allow outbound network access.

``` shell
openstack --os-cloud={cloud_name} router add subnet my_router my_dmz_subnet

openstack --os-cloud={cloud_name} router set --external-gateway PUBLICNET my_router
```

Fifth gather the UUIDS for our image, flavor and network to create our server.

``` shell
openstack --os-cloud={cloud_name} image list
openstack --os-cloud={cloud_name} flavor list
openstack --os-cloud={cloud_name} network list
```

Lastly create your server!

``` shell
openstack --os-cloud={cloud_name} server create --flavor {flavor uuid} --image {image uuid} --boot-from-volume 25 --network {network uuid} my_first_server
```
