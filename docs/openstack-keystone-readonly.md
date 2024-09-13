# Create a Platform Services Project

The following commands will setup a readonly user which is able to read data across domains.

## Create the platform-services user and project

After running the following commands, a readonly user (example: `platform-services`) will have read only access to everything under the `default` and `rackspace_cloud_domain` domains.

### Create a project

``` shell
openstack --os-cloud default project create --description 'platform-services enablement' platform-services --domain default
```

#### Create a new zamboni user

!!! tip "Make sure to set the password accordingly"

    ``` shell
    PASSWORD=SuperSecrete
    ```

``` shell
openstack --os-cloud default user create --project platform-services --password ${PASSWORD} zamboni --domain default
```

##### Add the member role to the new user

``` shell
openstack --os-cloud default role add --user zamboni --project platform-services member --inherited
```

##### Add the reader roles for user `zamboni` to the `default` domain

``` shell
openstack --os-cloud default role add --user zamboni --domain default reader --inherited
```

##### Add the reader role for user `zamboni` to the `rackspace_cloud_domain` domain

``` shell
openstack --os-cloud default role add --user zamboni --domain rackspace_cloud_domain reader --inherited
```

##### Add the reader role for user `zamboni` to the system

``` shell
openstack --os-cloud default role add --user zamboni --system all reader
```

#### Create a new member user

!!! tip "Make sure to set the password accordingly"

    ``` shell
    PASSWORD=SuperSecrete
    ```

``` shell
openstack --os-cloud default user create --project platform-services --password ${PASSWORD} platform-services --domain default
```

##### Add the member roles to the new platform-services user

``` shell
openstack --os-cloud default role add --user platform-services --project platform-services member --inherited
openstack --os-cloud default role add --user platform-services --domain default member --inherited
```

#### Create a new core user

!!! tip "Make sure to set the password accordingly"

    ``` shell
    PASSWORD=SuperSecrete
    ```

``` shell
openstack --os-cloud default user create --project platform-services --password ${PASSWORD} platform-services-core --domain default
```

##### Add the member role to the new core user

``` shell
openstack --os-cloud default role add --user platform-services-core --project platform-services member --inherited
```

##### Add the reader roles for user `platform-services-core` to the `default` domain

``` shell
openstack --os-cloud default role add --user platform-services-core --domain default reader --inherited
```

##### Add the reader role for user `platform-services-core` to the `rackspace_cloud_domain` domain

``` shell
openstack --os-cloud default role add --user platform-services-core --domain rackspace_cloud_domain reader --inherited
```

##### Add the reader role for user `platform-services-core` to the system

``` shell
openstack --os-cloud default role add --user platform-services-core --system all reader
```

#### Create a new alt user

!!! tip "Make sure to set the password accordingly"

    ``` shell
    PASSWORD=SuperSecrete
    ```

``` shell
openstack --os-cloud default user create --project platform-services --password ${PASSWORD} platform-services-core-alt --domain default
```

##### Add the member role to the new core-alt user

``` shell
openstack --os-cloud default role add --user platform-services-core-alt --project platform-services member --inherited
```

##### Add the reader roles for user `platform-services-core-alt` to the `default` domain

``` shell
openstack --os-cloud default role add --user platform-services-core-alt --domain default reader --inherited
```

##### Add the reader role for user `platform-services-core-alt` to the `rackspace_cloud_domain` domain

``` shell
openstack --os-cloud default role add --user platform-services-core-alt --domain rackspace_cloud_domain reader --inherited
```

##### Add the reader role for user `platform-services-core-alt` to the system

``` shell
openstack --os-cloud default role add --user platform-services-core-alt --system all reader
```
