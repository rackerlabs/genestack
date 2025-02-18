# Retrieving Project and User Information from openstack --os-cloud default Resources

As an OpenStack operator or administrator focused on support, it's essential to know how to retrieve project (tenant) and user information associated with various
resources. This document provides detailed instructions on how to obtain this information using command-line interfaces (CLIs) for the following resources.

* Instance UUID
* Image UUID
* Volume UUID
* Load Balancer UUID
* Network UUID
* Subnet UUID
* Router UUID

Retrieving project and user information from OpenStack resources is a fundamental skill for operators and administrators. By using the `openstack` command-line client, you can
efficiently gather necessary details to support operations, troubleshoot issues, and perform audits.

## Prerequisites

Access to the openstack --os-cloud default command-line client (openstack --os-cloud default command). Administrative privileges or appropriate permissions to view user and project information.
See the [documentation](openstack-clouds.md) on generating your own `clouds.yaml` file which can be used to populate the monitoring configuration file.

## Retrieving Information from an Instance UUID

The following command displays detailed information about an instance.

``` shell
openstack --os-cloud default server show <instance_uuid>
```

!!! example

    ``` shell
    openstack --os-cloud default server show 76d8fe3b-be2d-477d-9609-92d74579f948
    ```

    Sample Output

    ``` shell
    +-------------------------------------+-------------------------------------------------------------------------------------------------------------------------------------------------------------------+
    | Field                               | Value                                                                                                                                                             |
    +-------------------------------------+-------------------------------------------------------------------------------------------------------------------------------------------------------------------+
    | OS-DCF:diskConfig                   | MANUAL                                                                                                                                                            |
    | OS-EXT-AZ:availability_zone         | nova                                                                                                                                                              |
    | OS-EXT-SRV-ATTR:host                | None                                                                                                                                                              |
    | OS-EXT-SRV-ATTR:hostname            | jump-0                                                                                                                                                            |
    | OS-EXT-SRV-ATTR:hypervisor_hostname | None                                                                                                                                                              |
    | OS-EXT-SRV-ATTR:instance_name       | None                                                                                                                                                              |
    | OS-EXT-SRV-ATTR:kernel_id           | None                                                                                                                                                              |
    | OS-EXT-SRV-ATTR:launch_index        | None                                                                                                                                                              |
    | OS-EXT-SRV-ATTR:ramdisk_id          | None                                                                                                                                                              |
    | OS-EXT-SRV-ATTR:reservation_id      | None                                                                                                                                                              |
    | OS-EXT-SRV-ATTR:root_device_name    | None                                                                                                                                                              |
    | OS-EXT-SRV-ATTR:user_data           | None                                                                                                                                                              |
    | OS-EXT-STS:power_state              | Running                                                                                                                                                           |
    | OS-EXT-STS:task_state               | None                                                                                                                                                              |
    | OS-EXT-STS:vm_state                 | active                                                                                                                                                            |
    | OS-SRV-USG:launched_at              | 2024-11-05T16:50:49.000000                                                                                                                                        |
    | OS-SRV-USG:terminated_at            | None                                                                                                                                                              |
    | accessIPv4                          |                                                                                                                                                                   |
    | accessIPv6                          |                                                                                                                                                                   |
    | addresses                           | tenant-net=10.0.0.57, 65.17.193.69                                                                                                                                |
    | config_drive                        |                                                                                                                                                                   |
    | created                             | 2024-11-05T16:50:46Z                                                                                                                                              |
    | description                         | None                                                                                                                                                              |
    | flavor                              | description=, disk='10', ephemeral='0', extra_specs.:architecture='x86_architecture', extra_specs.:category='general_purpose',                                    |
    |                                     | extra_specs.hw:cpu_max_sockets='2', extra_specs.hw:cpu_max_threads='1', extra_specs.hw:mem_page_size='any', id='gp.0.1.2', is_disabled=, is_public='True',        |
    |                                     | location=, name='gp.0.1.2', original_name='gp.0.1.2', ram='2048', rxtx_factor=, swap='0', vcpus='1'                                                               |
    | hostId                              | a7fb61145d904932313274d17e5128d775e69de60f8434d081695387                                                                                                          |
    | host_status                         | None                                                                                                                                                              |
    | id                                  | 76d8fe3b-be2d-477d-9609-92d74579f948                                                                                                                              |
    | image                               | Debian-12 (727958e9-d037-45d1-9716-ea7ac322fe02)                                                                                                                  |
    | key_name                            | tenant-key                                                                                                                                                        |
    | locked                              | False                                                                                                                                                             |
    | locked_reason                       | None                                                                                                                                                              |
    | name                                | jump-0                                                                                                                                                            |
    | pinned_availability_zone            | None                                                                                                                                                              |
    | progress                            | 0                                                                                                                                                                 |
    | project_id                          | 0e32bf7ccajjjj858320995dd4a223ab                                                                                                                                  |
    | properties                          |                                                                                                                                                                   |
    | security_groups                     | name='talos-secgroup'                                                                                                                                             |
    |                                     | name='tenant-secgroup'                                                                                                                                            |
    | server_groups                       | []                                                                                                                                                                |
    | status                              | ACTIVE                                                                                                                                                            |
    | tags                                |                                                                                                                                                                   |
    | trusted_image_certificates          | None                                                                                                                                                              |
    | updated                             | 2024-11-19T16:26:16Z                                                                                                                                              |
    | user_id                             | fdff75fff6ace79f4sdfsdfsde96b1ba9fc5153ed8ba4570fbeca1fc67afab12                                                                                                  |
    | volumes_attached                    |                                                                                                                                                                   |
    +-------------------------------------+-------------------------------------------------------------------------------------------------------------------------------------------------------------------+
    ```

With the `user_id` and `project_id` fields, you can retrieve user and project details and proceed to the [Project and User Information](#project-and-user-information) section.

## Retrieving Information from an Image UUID

The following command displays information about an image.

``` shell
openstack --os-cloud default image show <image_uuid>
```

The owner field indicates the project ID that owns the image.

!!! example

    ``` shell
    openstack --os-cloud default image show 727958e9-d037-45d1-9716-ea7ac322fe02
    ```

    Sample Output

    ``` shell
    +------------------+--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
    | Field            | Value                                                                                                                                                                                |
    +------------------+--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
    | checksum         | 9cc9a43ad051fda5475ca79f05df549c                                                                                                                                                     |
    | container_format | bare                                                                                                                                                                                 |
    | created_at       | 2024-06-21T17:07:16Z                                                                                                                                                                 |
    | disk_format      | qcow2                                                                                                                                                                                |
    | file             | /v2/images/727958e9-d037-45d1-9716-ea7ac322fe02/file                                                                                                                                 |
    | id               | 727958e9-d037-45d1-9716-ea7ac322fe02                                                                                                                                                 |
    | min_disk         | 0                                                                                                                                                                                    |
    | min_ram          | 0                                                                                                                                                                                    |
    | name             | Debian-12                                                                                                                                                                            |
    | owner            | 8fb86e74be8d49f3befde1f647d9f2ef                                                                                                                                                     |
    | properties       | hw_firmware_type='uefi', hw_machine_type='q35', hw_qemu_guest_agent='yes', hw_vif_multiqueue_enabled='True', hypervisor_type='kvm', img_config_drive='optional',                     |
    |                  | os_admin_user='debian', os_distro='debian', os_hash_algo='sha512',                                                                                                                   |
    |                  | os_hash_value='e7efdc6e0ae643b05c6d53e10efbfd4454a769e13ddd69b5fabaa3e00c0ec431e6d6022530ecc922d944875409f4db66f69f1c134f64098959ab43de321d67c7', os_hidden='False',                 |
    |                  | os_require_quiesce='True', os_type='linux', os_version='12', owner_specified.openstack.md5='', owner_specified.openstack.object='images/Debian-12',                                  |
    |                  | owner_specified.openstack.sha256=''                                                                                                                                                  |
    | protected        | False                                                                                                                                                                                |
    | schema           | /v2/schemas/image                                                                                                                                                                    |
    | size             | 346670592                                                                                                                                                                            |
    | status           | active                                                                                                                                                                               |
    | tags             |                                                                                                                                                                                      |
    | updated_at       | 2024-09-24T22:31:14Z                                                                                                                                                                 |
    | virtual_size     | 2147483648                                                                                                                                                                           |
    | visibility       | public                                                                                                                                                                               |
    +------------------+--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
    ```

The `owner` field represents the project ID for the owner of a given image, With the `owner` field, you can retrieve user and project details and proceed to
the [Project and User Information](#project-and-user-information) section.

## Retrieving Information from a Volume UUID

The following command displays information about a volume.

``` shell
openstack --os-cloud default volume show <volume_uuid>
```

!!! example

    ``` shell
    openstack --os-cloud default volume show 43ef9068-b9f9-4b5c-8da7-5f6f6999e50f
    ```

    Sample Output

    ``` shell
    +------------------------------+--------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
    | Field                        | Value                                                                                                                                                                    |
    +------------------------------+--------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
    | attachments                  | [{'id': '43ef9068-b9f9-4b5c-8da7-5f6f6999e50f', 'attachment_id': '33ea9695-a819-4253-8579-1fb2f2c1af98', 'volume_id': '43ef9068-b9f9-4b5c-8da7-5f6f6999e50f',            |
    |                              | 'server_id': '1896bf60-db4f-4312-b2f5-feccdff31a51', 'host_name': None, 'device': '/dev/vdc', 'attached_at': '2024-11-06T03:04:38.000000'}]                              |
    | availability_zone            | nova                                                                                                                                                                     |
    | bootable                     | false                                                                                                                                                                    |
    | consistencygroup_id          | None                                                                                                                                                                     |
    | created_at                   | 2024-11-06T03:04:22.000000                                                                                                                                               |
    | description                  | None                                                                                                                                                                     |
    | encrypted                    | True                                                                                                                                                                     |
    | id                           | 43ef9068-b9f9-4b5c-8da7-5f6f6999e50f                                                                                                                                     |
    | multiattach                  | False                                                                                                                                                                    |
    | name                         | longhorn-2                                                                                                                                                               |
    | os-vol-tenant-attr:tenant_id | 0e32bf7ccajjjj858320995dd4a223ab                                                                                                                                         |
    | properties                   |                                                                                                                                                                          |
    | replication_status           | None                                                                                                                                                                     |
    | size                         | 100                                                                                                                                                                      |
    | snapshot_id                  | None                                                                                                                                                                     |
    | source_volid                 | None                                                                                                                                                                     |
    | status                       | in-use                                                                                                                                                                   |
    | type                         | Capacity                                                                                                                                                                 |
    | updated_at                   | 2024-11-06T03:04:46.000000                                                                                                                                               |
    | user_id                      | fdff75fff6ace79f4sdfsdfsde96b1ba9fc5153ed8ba4570fbeca1fc67afab12                                                                                                         |
    +------------------------------+--------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
    ```

With the `os-vol-tenant-attr:tenant_id` field, you can retrieve user and project details and proceed to the [Project and User Information](#project-and-user-information) section.

## Retrieving Information from a Load Balancer UUID

The following command displays details about a load balancer.

``` shell
openstack --os-cloud default loadbalancer show <loadbalancer_uuid>
```

The project_id field indicates the owning project.

!!! example

    ``` shell
    openstack --os-cloud default loadbalancer show 4a9a5d27-38bd-401f-8215-bba278474fe3
    ```

    Sample Output

    ``` shell
    +---------------------+--------------------------------------+
    | Field               | Value                                |
    +---------------------+--------------------------------------+
    | admin_state_up      | True                                 |
    | availability_zone   | None                                 |
    | created_at          | 2024-11-21T17:14:10                  |
    | description         |                                      |
    | flavor_id           | None                                 |
    | id                  | 4a9a5d27-38bd-401f-8215-bba278474fe3 |
    | listeners           | 6377d5f8-5098-44b6-b735-b82e53eb75f7 |
    | name                | talos-control-plane-good             |
    | operating_status    | ONLINE                               |
    | pools               | 3219e759-7fd8-40bf-98ea-beac9223ba59 |
    | project_id          | 0e32bf7ccajjjj858320995dd4a223ab     |
    | provider            | ovn                                  |
    | provisioning_status | ACTIVE                               |
    | updated_at          | 2024-11-21T17:17:41                  |
    | vip_address         | 10.0.0.10                            |
    | vip_network_id      | 426b1280-a3e8-4bea-ab9d-e360d315be89 |
    | vip_port_id         | 803749df-4cae-497f-8628-b22805f45e74 |
    | vip_qos_policy_id   | None                                 |
    | vip_subnet_id       | b4448aa6-bb7d-4e01-86c1-80e589d3fb92 |
    | vip_vnic_type       | normal                               |
    | tags                |                                      |
    | additional_vips     | []                                   |
    +---------------------+--------------------------------------+
    ```

With the `project_id` field, you can retrieve user and project details and proceed to the [Project and User Information](#project-and-user-information) section.

## Retrieving Information from a Network UUID

The following command provides details about a network.

``` shell
openstack --os-cloud default network show <network_uuid>
```

!!! example

    ``` shell
    openstack --os-cloud default network show 426b1280-a3e8-4bea-ab9d-e360d315be89
    ```

    Sample Output

    ``` shell
    +---------------------------+--------------------------------------+
    | Field                     | Value                                |
    +---------------------------+--------------------------------------+
    | admin_state_up            | UP                                   |
    | availability_zone_hints   | nova                                 |
    | availability_zones        | nova                                 |
    | created_at                | 2024-11-05T03:14:50Z                 |
    | description               |                                      |
    | dns_domain                | None                                 |
    | id                        | 426b1280-a3e8-4bea-ab9d-e360d315be89 |
    | ipv4_address_scope        | None                                 |
    | ipv6_address_scope        | None                                 |
    | is_default                | None                                 |
    | is_vlan_transparent       | None                                 |
    | l2_adjacency              | True                                 |
    | mtu                       | 3942                                 |
    | name                      | tenant-net                           |
    | port_security_enabled     | True                                 |
    | project_id                | 0e32bf7ccajjjj858320995dd4a223ab     |
    | provider:network_type     | None                                 |
    | provider:physical_network | None                                 |
    | provider:segmentation_id  | None                                 |
    | qos_policy_id             | None                                 |
    | revision_number           | 2                                    |
    | router:external           | Internal                             |
    | segments                  | None                                 |
    | shared                    | False                                |
    | status                    | ACTIVE                               |
    | subnets                   | b4448aa6-bb7d-4e01-86c1-80e589d3fb92 |
    | tags                      |                                      |
    | updated_at                | 2024-11-05T03:14:51Z                 |
    +---------------------------+--------------------------------------+
    ```

With the `project_id` field, you can retrieve user and project details and proceed to the [Project and User Information](#project-and-user-information) section.

## Retrieving Information from a Subnet UUID

The following command displays details about a subnet.

``` shell
openstack --os-cloud default subnet show <subnet_uuid>
```

!!! example

    ``` shell
    openstack --os-cloud default subnet show b4448aa6-bb7d-4e01-86c1-80e589d3fb92
    ```

    Sample Output

    ``` shell
    +----------------------+--------------------------------------+
    | Field                | Value                                |
    +----------------------+--------------------------------------+
    | allocation_pools     | 10.0.0.2-10.0.0.254                  |
    | cidr                 | 10.0.0.0/24                          |
    | created_at           | 2024-11-05T03:14:51Z                 |
    | description          |                                      |
    | dns_nameservers      | 8.8.8.8                              |
    | dns_publish_fixed_ip | None                                 |
    | enable_dhcp          | True                                 |
    | gateway_ip           | 10.0.0.1                             |
    | host_routes          |                                      |
    | id                   | b4448aa6-bb7d-4e01-86c1-80e589d3fb92 |
    | ip_version           | 4                                    |
    | ipv6_address_mode    | None                                 |
    | ipv6_ra_mode         | None                                 |
    | name                 | tenant-subnet                        |
    | network_id           | 426b1280-a3e8-4bea-ab9d-e360d315be89 |
    | project_id           | 0e32bf7ccajjjj858320995dd4a223ab     |
    | revision_number      | 0                                    |
    | segment_id           | None                                 |
    | service_types        |                                      |
    | subnetpool_id        | None                                 |
    | tags                 |                                      |
    | updated_at           | 2024-11-05T03:14:51Z                 |
    +----------------------+--------------------------------------+
    ```

With the `project_id` field, you can retrieve user and project details and proceed to the [Project and User Information](#project-and-user-information) section.

## Retrieving Information from a Router UUID

The following command provides details about a router.

``` shell
openstack --os-cloud default router show <router_uuid>
```

!!! example

    ``` shell
    openstack --os-cloud default router show 63cce307-1476-4ada-aacd-e013226e02af
    ```

    Sample Output

    ``` shell
    +---------------------------+-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
    | Field                     | Value                                                                                                                                                                       |
    +---------------------------+-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
    | admin_state_up            | UP                                                                                                                                                                          |
    | availability_zone_hints   | nova                                                                                                                                                                        |
    | availability_zones        | nova                                                                                                                                                                        |
    | created_at                | 2024-11-05T03:09:07Z                                                                                                                                                        |
    | description               |                                                                                                                                                                             |
    | enable_default_route_bfd  | False                                                                                                                                                                       |
    | enable_default_route_ecmp | False                                                                                                                                                                       |
    | enable_ndp_proxy          | None                                                                                                                                                                        |
    | external_gateway_info     | {"network_id": "723f8fa2-dbf7-4cec-8d5f-017e62c12f79", "external_fixed_ips": [{"subnet_id": "31bf7e05-be6e-4c5b-908d-abe47c80ba41", "ip_address": "X.X.X.X"}],              |
    |                           | "enable_snat": true}                                                                                                                                                        |
    | external_gateways         | [{'network_id': '723f8fa2-dbf7-4cec-8d5f-017e62c12f79', 'external_fixed_ips': [{'ip_address': 'X.X.X.X', 'subnet_id': '31bf7e05-be6e-4c5b-908d-abe47c80ba41'}]}]            |
    | flavor_id                 | None                                                                                                                                                                        |
    | id                        | 63cce307-1476-4ada-aacd-e013226e02af                                                                                                                                        |
    | interfaces_info           | [{"port_id": "dd39cd69-84a1-4276-bdaa-d699a8372090", "ip_address": "10.0.0.1", "subnet_id": "b4448aa6-bb7d-4e01-86c1-80e589d3fb92"}]                                        |
    | name                      | tenant-router                                                                                                                                                               |
    | project_id                | 0e32bf7ccajjjj858320995dd4a223ab                                                                                                                                            |
    | revision_number           | 5                                                                                                                                                                           |
    | routes                    |                                                                                                                                                                             |
    | status                    | ACTIVE                                                                                                                                                                      |
    | tags                      |                                                                                                                                                                             |
    | tenant_id                 | 0e32bf7ccajjjj858320995dd4a223ab                                                                                                                                            |
    | updated_at                | 2024-11-05T03:15:24Z                                                                                                                                                        |
    +---------------------------+-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
    ```

With the `project_id` or `tenant_id` field, you can retrieve user and project details and proceed to the [Project and User Information](#project-and-user-information) section.

## Project and User Information

By using the previous command outputs, you can retrieve detailed information about the project and user associated with the resources.

### Retrieve Project Details

``` shell
openstack --os-cloud default project show <project_id>
```

!!! example

    ``` shell
    openstack --os-cloud default project show 0e32bf7ccajjjj858320995dd4a223ab
    ```

    Sample Output

    ``` shell
    +-------------+--------------------------------------+
    | Field       | Value                                |
    +-------------+--------------------------------------+
    | description |                                      |
    | domain_id   | eb6ce3086fba4luio2be7d6b23efbb95     |
    | enabled     | True                                 |
    | id          | 0e32bf7ccajjjj858320995dd4a223ab     |
    | is_domain   | False                                |
    | name        | 3965512c-e2c0-48a7-acef-3cdfb2b95ef8 |
    | options     | {}                                   |
    | parent_id   | eb6ce3086fba4luio2be7d6b23efbb95     |
    | tags        | []                                   |
    +-------------+--------------------------------------+
    ```

### Retrieve User Details

``` shell
openstack --os-cloud default user show <user_id>
```

!!! example

    ``` shell
    openstack --os-cloud default user show fdff75fff6ace79f4sdfsdfsde96b1ba9fc5153ed8ba4570fbeca1fc67afab12
    ```

    Sample Output

    ``` shell
    +---------------------+------------------------------------------------------------------+
    | Field               | Value                                                            |
    +---------------------+------------------------------------------------------------------+
    | default_project_id  | None                                                             |
    | domain_id           | eb6ce3086fba4luio2be7d6b23efbb95                                 |
    | email               | user@emailaddress.com                                            |
    | enabled             | True                                                             |
    | id                  | fdff75fff6ace79f4sdfsdfsde96b1ba9fc5153ed8ba4570fbeca1fc67afab12 |
    | name                | username                                                         |
    | description         | None                                                             |
    | password_expires_at | None                                                             |
    +---------------------+------------------------------------------------------------------+
    ```

## Notes and Tips

Here are a few additional tips and considerations to keep in mind when retrieving project and user information from OpenStack resources.

### Permissions

Ensure you have administrative privileges or the necessary role assignments to access user and project information.

### Help and Manual Pages

Use the `--help` option with any command to get more information

``` shell
openstack --os-cloud default server show --help
```

### Logging and Auditing

If user information is not readily available, consult service logs (e.g., Nova, Neutron, Cinder logs) or audit records. OpenStack services may record operations in
logs with user and project context.

### API Usage

For advanced queries, consider using the [OpenStack APIs](https://docs.openstack.org/api-quick-start) directly with tools like curl or scripting with
SDKs (Python SDK, etc.).
