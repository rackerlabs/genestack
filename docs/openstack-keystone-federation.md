# Setup the Keystone Federation Plugin

## Create the domain

``` shell
openstack --os-cloud default domain create rackspace_cloud_domain
```

## Create the identity provider

``` shell
openstack --os-cloud default identity provider create --remote-id rackspace --domain rackspace_cloud_domain rackspace
```

### Create the mapping for our identity provider

You're also welcome to generate your own mapping to suit your needs; however, if you want to use the example mapping (which is suitable for production) you can.

``` json
[
    {
        "local": [
            {
                "user": {
                    "name": "{0}",
                    "email": "{1}"
                }
            },
            {
                "projects": [
                    {
                        "name": "{2}_Flex",
                        "roles": [
                            {
                                "name": "member"
                            },
                            {
                                "name": "load-balancer_member"
                            },
                            {
                                "name": "heat_stack_user"
                            }
                        ]
                    }
                ]
            }
        ],
        "remote": [
            {
                "type": "RXT_UserName"
            },
            {
                "type": "RXT_Email"
            },
            {
                "type": "RXT_TenantName"
            },
            {
                "type": "RXT_orgPersonType",
                "any_one_of": [
                    "admin",
                    "default",
                    "user-admin",
                    "tenant-access"
                ]
            }
        ]
    }
]
```

!!! tip

    Save the mapping to a local file before uploading it to keystone. In the examples, the mapping is stored at `/tmp/mapping.json`.

Now register the mapping within Keystone.

``` shell
openstack --os-cloud default mapping create --rules /tmp/mapping.json rackspace_mapping
```

## Create the federation protocol

``` shell
openstack --os-cloud default federation protocol create rackspace --mapping rackspace_mapping --identity-provider rackspace
```
