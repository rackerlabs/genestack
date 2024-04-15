# Create a Readonly User

The following commands will setup a readonly user which is able to read data across domains.

## Create the VMM user and project

After running the following commands, a readonly user (example: `vmm`) will have read only access to everything under the `default` and `rackspace_cloud_domain` domains.

### Create a project

``` shell
openstack --os-cloud default project create --description 'vmm enablement' vmm --domain default
```

### Create a new user

!!! tip "Make sure to set the password accordingly"

    ``` shell
    PASSWORD=SuperSecrete
    ```

``` shell
openstack --os-cloud default user create --project vmm --password ${PASSWORD} vmm --domain default
```

### Add the member role to the new user

``` shell
openstack --os-cloud default role add --user vmm --project vmm member --inherited
```

### Add the reader roles for user `vmm` to the `default` domain

``` shell
openstack --os-cloud default role add --user vmm --domain default reader --inherited
```

### Add the reader role for user `vmm` to the `rackspace_cloud_domain` domain

``` shell
openstack --os-cloud default role add --user vmm --domain rackspace_cloud_domain reader --inherited
```

### Add the reader role for user `vmm` to the system

``` shell
openstack --os-cloud default role add --user vmm --system all reader
```
