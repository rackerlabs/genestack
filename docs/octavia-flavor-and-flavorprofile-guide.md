# Octavia Flavors

This document is intended for users who want to use the command line interface (CLI) to create and manage Octavia flavors and flavor profiles for load balancing. Flavor profiles define specific configurations for the Octavia load balancer, allowing users to select from predefined flavors that match provider capabilities. This guide walks you through the process of creating and updating both flavors and flavor profiles. For instructions on creating other resources such as load balancers, listeners, monitors, and pools, please refer to the [Octavia CLI Load Balancer Setup Guide](https://docs.rackspacecloud.com/octavia-loadbalancer-setup-guide/)

## Provider Capabilities

To define a flavor, review the flavor capabilities exposed by the provider driver. Below providers already exist:
``` shell
$ openstack --os-cloud default loadbalancer provider list
+---------+------------------------------+
| name    | description                  |
+---------+------------------------------+
| ovn     | "The Octavia OVN driver"     |
| amphora | "The Octavia Amphora driver" |
+---------+------------------------------+
```

The following command lists all the available flavor capabilities in the Amphora provider.
``` shell
$ openstack --os-cloud default loadbalancer provider capability list amphora
+-------------------+-----------------------+--------------------------------------------------------------------------------------------------------------------------------------+
| type              | name                  | description                                                                                                                          |
+-------------------+-----------------------+--------------------------------------------------------------------------------------------------------------------------------------+
| flavor            | loadbalancer_topology | The load balancer topology. One of: SINGLE - One amphora per load balancer. ACTIVE_STANDBY - Two amphora per load balancer.          |
| flavor            | compute_flavor        | The compute driver flavor ID.                                                                                                        |
| flavor            | amp_image_tag         | The amphora image tag.                                                                                                               |
| flavor            | sriov_vip             | When true, the VIP port will be created using an SR-IOV VF port.                                                                     |
| availability_zone | compute_zone          | The compute availability zone.                                                                                                       |
| availability_zone | management_network    | The management network ID for the amphora.                                                                                           |
| availability_zone | valid_vip_networks    | List of network IDs that are allowed for VIP use. This overrides/replaces the list of allowed networks configured in `octavia.conf`. |
+-------------------+-----------------------+--------------------------------------------------------------------------------------------------------------------------------------+
```

## Flavor Profiles

To define a flavor profile, you specify both the provider and the flavor data, outlining the supported flavor settings for that provider. If you do not include the provider flag, the system will use the default provider, which is Amphora at Rackspace. Use the command below to create a flavor profile for the Amphora provider, setting up a load balancer with a single Amphora and the specified compute flavor. The compute_flavor in flavor_data defines the resources (CPU, RAM, disk) allocated to the Amphora VMs or containers, determining the size and performance of the load balancer instances.

``` shell
$ openstack --os-cloud default loadbalancer flavorprofile create --name fp.single.lite --provider amphora --flavor-data '{"loadbalancer_topology": "SINGLE", "compute_flavor": "f485b7c3-4efd-4c0d-b8b0-997db6bdbbce"}'
+---------------+-----------------------------------------------------------------------------------------------+
| Field         | Value                                                                                         |
+---------------+-----------------------------------------------------------------------------------------------+
| id            | 5f4d2c7c-e294-4a9c-b97a-54a2b97a17a5                                                          |
| name          | fp.single.lite                                                                                |
| provider_name | amphora                                                                                       |
| flavor_data   | {"loadbalancer_topology": "SINGLE", "compute_flavor": "f485b7c3-4efd-4c0d-b8b0-997db6bdbbce"} |
+---------------+-----------------------------------------------------------------------------------------------+
```

Use the command below to list the existing flavor profiles:
``` shell
$ openstack loadbalancer flavorprofile list
+--------------------------------------+----------------+---------------+
| id                                   | name           | provider_name |
+--------------------------------------+----------------+---------------+
| 5f4d2c7c-e294-4a9c-b97a-54a2b97a17a5 | fp.single.lite | amphora       |
| 66244e86-c714-4e80-a250-997d414db9d9 | fp.ha.plus     | amphora       |
| a252f357-bd8e-4551-a40c-f98ac857d2f8 | fp.single.pro  | amphora       |
| bea6924c-59d6-42a2-9336-df726ab0bfdf | fp.single.plus | amphora       |
| cfa628f1-2916-419c-876e-7b2d56643323 | fp.ha.lite     | amphora       |
| dc6186a0-82fc-4694-b521-50065ae26516 | fp.ha.pro      | amphora       |
+--------------------------------------+----------------+---------------+
```

### Update a Flavor Profile

To update a flavor profile, use the `openstack loadbalancer flavorprofile set` command. This allows you to modify properties of an existing flavor profile, such as its name, provider, and flavor data.
``` shell
$ openstack loadbalancer flavorprofile set --flavor-data '{"loadbalancer_topology": "ACTIVE_STANDBY"}' 5f4d2c7c-e294-4a9c-b97a-54a2b97a17a5
```

You can extend the flavor profile with additional provider capabilities as needed. Below is an example:
``` shell
$ openstack loadbalancer flavorprofile set --flavor-data '{"loadbalancer_topology": "ACTIVE_STANDBY", "amp_image_tag": "amphora-image-v2", "sriov_vip": false}' 5f4d2c7c-e294-4a9c-b97a-54a2b97a17a5
```

!!! note "Loadbalancer Topologies"

    The `loadbalancer_topology` field in the flavor data specifies the number of Amphora instances per
    load balancer. The possible values are:

    - `SINGLE`: One Amphora per load balancer.
    - `ACTIVE_STANDBY`: Two Amphora per load balancer.

## Flavors

To create a flavor using the previously defined flavor profile, run the following command:
``` shell
$ openstack loadbalancer flavor create --name single.lite --flavorprofile fp.single.lite --description "single amphora, 1 vcpu, 1024 ram, 10 disk" --enable
+-------------------+-------------------------------------------+
| Field             | Value                                     |
+-------------------+-------------------------------------------+
| id                | 3480b6d0-b803-4373-b701-53420d895059      |
| name              | single.lite                               |
| flavor_profile_id | 5f4d2c7c-e294-4a9c-b97a-54a2b97a17a5      |
| enabled           | True                                      |
| description       | single amphora, 1 vcpu, 1024 ram, 10 disk |
+-------------------+-------------------------------------------+
```
At this point, the flavor is available for use by users creating new load balancers.

Use the command below to list the existing flavors:
``` shell
$ openstack loadbalancer flavor list
+--------------------------------------+-------------+--------------------------------------+---------+
| id                                   | name        | flavor_profile_id                    | enabled |
+--------------------------------------+-------------+--------------------------------------+---------+
| 3480b6d0-b803-4373-b701-53420d895059 | single.lite | 5f4d2c7c-e294-4a9c-b97a-54a2b97a17a5 | True    |
| 351d67c3-796f-4f41-bbb9-6d8d6bc389a8 | ha.plus     | 66244e86-c714-4e80-a250-997d414db9d9 | True    |
| 63a2533d-ec47-4dc8-b04c-e4c9fd55b6e9 | single.plus | bea6924c-59d6-42a2-9336-df726ab0bfdf | True    |
| 81c4307b-e66c-4c0c-a177-c971951020d3 | ha.pro      | dc6186a0-82fc-4694-b521-50065ae26516 | True    |
| eb107a33-71ae-45a3-941a-05bbe84d33df | single.pro  | a252f357-bd8e-4551-a40c-f98ac857d2f8 | True    |
| f37c3e03-bb8f-4b3a-956c-e45a9c611319 | ha.lite     | cfa628f1-2916-419c-876e-7b2d56643323 | True    |
+--------------------------------------+-------------+--------------------------------------+---------+
```

### Update a Flavor

The `openstack loadbalancer flavor set` command updates an existing load balancer flavor, allowing you to modify attributes like name, description, or status. To disable a flavor, use the following command:
``` shell
$ openstack loadbalancer flavor set --disable 3480b6d0-b803-4373-b701-53420d895059
```
