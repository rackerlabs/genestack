# Quota Management

Resouce quotas can be set in an OpenStack environment to ensure that we do not unintentionally exhaust
the capacity. In OpenStack quotas can be set to give each resource some operational limit.

Quotas are checked in the follwing order:

* Project specific limit

If set for a specific resource this limit will be used first. Exmaple, for a project we can set quotas
for any resource like so:

```shell
  openstack quota set --cores 100 <project>
```

* Default limits

These are hard limit set the database under `quota_classes` for the default quota class. If project sepcific
limit is not set for a given resource and default limit is set, OpenStack uses this limit.

To set a default limit for a resource:

```shell
  openstack quota set --cores 120 default
```

!!! note
    Once the default limit is set via the API, it takes precedence over config limits. Once it is set, we can only
    modify the limit, but it can not be deleted via the API. It can however be deleted manually from the database.


* Config provided limits

We can set limits on resource through the config file under the quota config group.


### Useful quota commands

```shell title="Show the default quota"
  openstack quota show --default
```

```shell title="Show quota for a project"
  openstack quota show <project>
```

```shell title="Update quota for resource instance in default class"
  openstack quota set --instances 15 default
```

```shell title="Update quota for a resource for a project"
  openstack quota set --instances 20 <project>
```

!!! note
    Quotas class has been replaced with a new driver unified limits. Please see OpenStack docs for unified limits.
