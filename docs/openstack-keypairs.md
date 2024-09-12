# Openstack Keypairs

Read more about Openstack keypairs using the [upstream docs](https://docs.openstack.org/python-openstackclient/latest/cli/command-objects/keypair.html).

#### List and view Keypairs

``` shell
openstack --os-cloud={cloud name} keypair list
    [--sort-column SORT_COLUMN]
    [--sort-ascending | --sort-descending]
    [--user <user>]
    [--user-domain <user-domain>]
    [--project <project>]
    [--project-domain <project-domain>]
    [--limit <limit>]
    [--marker <marker>]
```

#### Create a Keypair

Before launching an instance, you must add a public key to the Compute service.

``` shell
openstack --os-cloud={cloud name} keypair create
    [--public-key <file> | --private-key <file>]
    [--type <type>]
    [--user <user>]
    [--user-domain <user-domain>]
    <name>
```

!!! note

    --type <type> Keypair type (supported by –os-compute-api-version 2.2 or above)

This command generates a key pair with the name that you specify for KEY_NAME, writes the private key to the .pem file that you specify, and registers the public key to the Nova database.

#### Import a Keypair

If you have already generated a key pair and the public key is located at ~/.ssh/id_rsa.pub, run the following command to upload the public key.

``` shell
openstack --os-cloud={cloud name} keypair create --public-key ~/.ssh/id_rsa.pub KEY_NAME
```

This command registers the public key at the Nova database and names the key pair the name that you specify for KEY_NAME

#### Delete a Keypair

``` shell
openstack --os-cloud={cloud name} keypair delete
    [--user <user>]
    [--user-domain <user-domain>]
    <key>
    [<key> ...]
```

#### Show Keypair Details

``` shell
openstack --os-cloud={cloud name} keypair show
    [--public-key]
    [--user <user>]
    [--user-domain <user-domain>]
    <key>
```
