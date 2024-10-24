# Octavia CLI Load Balancer Setup Guide

This document is intended for users who want to use the command line interface (CLI) to create/deploy a Cloud Load Balancer (CLB).  At Rackspace Technology, the default provider is Amphora.  Using the CLI is the only way to specify OVN as the provider instead of Amphora.  These instructions will help provide the necessary information to create a load balancer, listener, monitor, and pool.  This document assumes you are already familiar with creating/managing vms, networks, routers, and security groups and it assumes you already have this created.

!!! note

    At Rackspace Technology, you are not allowed to attach directly to the Public Network.  You will need to assign a floating IP to your CLB if you would like to make it publicly accessible.


## Choose the provider

Rackspace Technology provides two options for your CLB, Amphora and OVN.  Each has it's own benefits.

|  | Amphora | OVN |
| --- | --- | --- |
| Maturity | More mature | Not as mature |
| Features | L7 policies, SSL termination | does not support L7 policies or SSL termination |
| HA | yes |  no |
| Resources | uses additional vms; can be slow to deploy | uses OVN; fast to deploy |
| Performance | good | better |
| Algorithms | Round Robin <br> Least Connections <br> Source IP <br> Source IP Port | Round Robin <br> Source IP Port |

## Create the load balancer

If you do not pass the provider flag, it will use the default.  At Rackspace Technology, we default to amphora.  You can check the available providers using the following command:

``` shell
$ openstack --os-cloud default loadbalancer provider list
+---------+------------------------------+
| name    | description                  |
+---------+------------------------------+
| ovn     | "The Octavia OVN driver"     |
| amphora | "The Octavia Amphora driver" |
+---------+------------------------------+
```

If using the amphora provider, you can also select the type/flavor of load balancer.  The default at Rackspace Technology for amphora is `ha.plus`. OVN does NOT use these flavors.  To see your options use the following command:

``` shell
$ openstack --os-cloud default loadbalancer flavor list
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

Use the following command to create the load balancer.  The name and description flags are optional, but if you do not use the name flag, you will need to reference it by id later.

``` shell
$ openstack --os-cloud default loadbalancer create --name OVN-Test --vip-subnet-id CLB-SUBNET-TEST --provider ovn
+---------------------+--------------------------------------+
| Field               | Value                                |
+---------------------+--------------------------------------+
| admin_state_up      | True                                 |
| availability_zone   | az1                                  |
| created_at          | 2024-08-30T17:48:46                  |
| description         |                                      |
| flavor_id           | None                                 |
| id                  | 10339382-2024-4631-a8d2-681548120505 |
| listeners           |                                      |
| name                | OVN-Test                             |
| operating_status    | OFFLINE                              |
| pools               |                                      |
| project_id          | 9e822f3bce56475787f3000aa4ef89e6     |
| provider            | ovn                                  |
| provisioning_status | PENDING_CREATE                       |
| updated_at          | None                                 |
| vip_address         | 192.168.32.214                       |
| vip_network_id      | 1a602d99-71a2-48f1-b8af-319235ebc473 |
| vip_port_id         | 38c74c73-bc3f-430e-b663-d419ce7be4e6 |
| vip_qos_policy_id   | None                                 |
| vip_subnet_id       | 5e1f5e82-952e-4e8a-bf1b-32dd832569a5 |
| vip_vnic_type       | normal                               |
| tags                |                                      |
| additional_vips     | []                                   |
+---------------------+--------------------------------------+

$ openstack --os-cloud default loadbalancer list
+--------------------------------------+----------+----------------------------------+----------------+---------------------+------------------+----------+
| id                                   | name     | project_id                       | vip_address    | provisioning_status | operating_status | provider |
+--------------------------------------+----------+----------------------------------+----------------+---------------------+------------------+----------+
| 10339382-2024-4631-a8d2-681548120505 | OVN-Test | 9e822f3bce56475787f3000aa4ef89e6 | 192.168.32.214 | ACTIVE              | ONLINE           | ovn      |
+--------------------------------------+----------+----------------------------------+----------------+---------------------+------------------+----------+
```

If you used amphora as the provider, it may take a few minutes before the provisioning_status is active.


## Create the listener

``` shell
$ openstack --os-cloud default loadbalancer listener create --protocol TCP --protocol-port 80 --name HTTP-listener OVN-Test
+-----------------------------+--------------------------------------+
| Field                       | Value                                |
+-----------------------------+--------------------------------------+
| admin_state_up              | True                                 |
| connection_limit            | -1                                   |
| created_at                  | 2024-08-30T17:55:35                  |
| default_pool_id             | None                                 |
| default_tls_container_ref   | None                                 |
| description                 |                                      |
| id                          | 0fad0e34-e87f-4c1a-ad4b-1faa168fe97f |
| insert_headers              | None                                 |
| l7policies                  |                                      |
| loadbalancers               | 10339382-2024-4631-a8d2-681548120505 |
| name                        | HTTP-listener                        |
| operating_status            | OFFLINE                              |
| project_id                  | 9e822f3bce56475787f3000aa4ef89e6     |
| protocol                    | TCP                                  |
| protocol_port               | 80                                   |
| provisioning_status         | PENDING_CREATE                       |
| sni_container_refs          | []                                   |
| timeout_client_data         | 50000                                |
| timeout_member_connect      | 5000                                 |
| timeout_member_data         | 50000                                |
| timeout_tcp_inspect         | 0                                    |
| updated_at                  | None                                 |
| client_ca_tls_container_ref | None                                 |
| client_authentication       | NONE                                 |
| client_crl_container_ref    | None                                 |
| allowed_cidrs               | None                                 |
| tls_ciphers                 | None                                 |
| tls_versions                | None                                 |
| alpn_protocols              | None                                 |
| tags                        |                                      |
| hsts_max_age                | None                                 |
| hsts_include_subdomains     | False                                |
| hsts_preload                | False                                |
+-----------------------------+--------------------------------------+

$ openstack --os-cloud default loadbalancer listener list
+--------------------------------------+-----------------+---------------+----------------------------------+----------+---------------+----------------+
| id                                   | default_pool_id | name          | project_id                       | protocol | protocol_port | admin_state_up |
+--------------------------------------+-----------------+---------------+----------------------------------+----------+---------------+----------------+
| 0fad0e34-e87f-4c1a-ad4b-1faa168fe97f | None            | HTTP-listener | 9e822f3bce56475787f3000aa4ef89e6 | TCP      |            80 | True           |
+--------------------------------------+-----------------+---------------+----------------------------------+----------+---------------+----------------+
```

## Create the monitor

The monitor will check to see if the servers in your pool are responding properly (defined by your monitor).  This is optional, but recommended.  Originally, we did not configure a monitor and so, you may notice that the rest of the examples do not show the monitor applied.

``` shell
$ openstack --os-cloud default loadbalancer healthmonitor create --delay 5 --max-retries 3 --timeout 5 --type TCP HTTP_POOL
+---------------------+--------------------------------------+
| Field               | Value                                |
+---------------------+--------------------------------------+
| project_id          | 9e822f3bce56475787f3000aa4ef89e6     |
| name                |                                      |
| admin_state_up      | True                                 |
| pools               | 02b3c02e-7efa-4988-83b5-4a5b6d5d238a |
| created_at          | 2024-08-30T19:57:54                  |
| provisioning_status | PENDING_CREATE                       |
| updated_at          | None                                 |
| delay               | 5                                    |
| expected_codes      | None                                 |
| max_retries         | 3                                    |
| http_method         | None                                 |
| timeout             | 5                                    |
| max_retries_down    | 3                                    |
| url_path            | None                                 |
| type                | TCP                                  |
| id                  | 3edfc7a2-77ec-4dfd-93d1-a0dc9b011da8 |
| operating_status    | OFFLINE                              |
| http_version        | None                                 |
| domain_name         | None                                 |
| tags                |                                      |
+---------------------+--------------------------------------+

$ openstack --os-cloud default loadbalancer healthmonitor list
+--------------------------------------+------+----------------------------------+------+----------------+
| id                                   | name | project_id                       | type | admin_state_up |
+--------------------------------------+------+----------------------------------+------+----------------+
| 3edfc7a2-77ec-4dfd-93d1-a0dc9b011da8 |      | 9e822f3bce56475787f3000aa4ef89e6 | TCP  | True           |
+--------------------------------------+------+----------------------------------+------+----------------+
```

## Create the pool

Here is where you will decide what load balancing algorithm to use.  OVN can only use SOURCE_IP_PORT.  Most common load balancer algorithms to use with amphora are ROUND_ROBIN or LEAST_CONNECTIONS. Use the help flag to see more options: `openstack --os-cloud default loadbalancer pool create --help`

``` shell
$ openstack --os-cloud default loadbalancer pool create --protocol TCP --lb-algorithm SOURCE_IP_PORT --listener HTTP-listener --name HTTP_POOL
+----------------------+--------------------------------------+
| Field                | Value                                |
+----------------------+--------------------------------------+
| admin_state_up       | True                                 |
| created_at           | 2024-08-30T18:03:00                  |
| description          |                                      |
| healthmonitor_id     |                                      |
| id                   | 02b3c02e-7efa-4988-83b5-4a5b6d5d238a |
| lb_algorithm         | SOURCE_IP_PORT                       |
| listeners            | 0fad0e34-e87f-4c1a-ad4b-1faa168fe97f |
| loadbalancers        | 10339382-2024-4631-a8d2-681548120505 |
| members              |                                      |
| name                 | HTTP_POOL                            |
| operating_status     | OFFLINE                              |
| project_id           | 9e822f3bce56475787f3000aa4ef89e6     |
| protocol             | TCP                                  |
| provisioning_status  | PENDING_CREATE                       |
| session_persistence  | None                                 |
| updated_at           | None                                 |
| tls_container_ref    | None                                 |
| ca_tls_container_ref | None                                 |
| crl_container_ref    | None                                 |
| tls_enabled          | False                                |
| tls_ciphers          | None                                 |
| tls_versions         | None                                 |
| tags                 |                                      |
| alpn_protocols       | None                                 |
+----------------------+--------------------------------------+

$ openstack --os-cloud default loadbalancer pool list
+--------------------------------------+-----------+----------------------------------+---------------------+----------+----------------+----------------+
| id                                   | name      | project_id                       | provisioning_status | protocol | lb_algorithm   | admin_state_up |
+--------------------------------------+-----------+----------------------------------+---------------------+----------+----------------+----------------+
| 02b3c02e-7efa-4988-83b5-4a5b6d5d238a | HTTP_POOL | 9e822f3bce56475787f3000aa4ef89e6 | ACTIVE              | TCP      | SOURCE_IP_PORT | True           |
+--------------------------------------+-----------+----------------------------------+---------------------+----------+----------------+----------------+
```

## Add the servers to the pool

First, get the IPs of the servers you would like to add to the pool:

``` shell
$ openstack --os-cloud default server list | grep OVN
| 1d0353e0-d82c-4954-b849-2f4e858e372e | OVN-CLB-2 | ACTIVE | CLB-TEST=192.168.32.87   | Ubuntu-20.04 | gp.0.1.2 |
| d97a3662-7def-4eb5-b047-db8da8f74f5c | OVN-CLB-3 | ACTIVE | CLB-TEST=192.168.32.124  | Ubuntu-20.04 | gp.0.1.2 |
| 031e0b95-4b4f-46f7-8e42-3ce9039b431c | OVN-CLB-1 | ACTIVE | CLB-TEST=192.168.32.175  | Ubuntu-20.04 | gp.0.1.2 |
```

Add the servers using the IP address:

``` shell
$ openstack --os-cloud default loadbalancer member create --address 192.168.32.175 --protocol-port 80 --name SERVER1 HTTP_POOL
$ openstack --os-cloud default loadbalancer member create --address 192.168.32.87 --protocol-port 80 --name SERVER2 HTTP_POOL
$ openstack --os-cloud default loadbalancer member create --address 192.168.32.124 --protocol-port 80 --name SERVER3 HTTP_POOL

$ openstack --os-cloud default loadbalancer member list HTTP_POOL
+--------------------------------------+---------+----------------------------------+---------------------+----------------+---------------+------------------+--------+
| id                                   | name    | project_id                       | provisioning_status | address        | protocol_port | operating_status | weight |
+--------------------------------------+---------+----------------------------------+---------------------+----------------+---------------+------------------+--------+
| 44436497-7ac9-4a53-bb3c-7e883331cd93 | SERVER1 | 9e822f3bce56475787f3000aa4ef89e6 | ACTIVE              | 192.168.32.175 |            80 | NO_MONITOR       |      1 |
| be484beb-583b-488f-85b9-dc57d0522a9f | SERVER2 | 9e822f3bce56475787f3000aa4ef89e6 | ACTIVE              | 192.168.32.87  |            80 | NO_MONITOR       |      1 |
| d4ac7f15-8bd9-4fd9-be83-3a071f9774f9 | SERVER3 | 9e822f3bce56475787f3000aa4ef89e6 | ACTIVE              | 192.168.32.124 |            80 | NO_MONITOR       |      1 |
+--------------------------------------+---------+----------------------------------+---------------------+----------------+---------------+------------------+--------+
```


## OPTIONAL: Associate a floating IP

If you want to make the load balancer publically accessible, you will need to associate a floating IP to it.  First get a list of your available floating IPs:

``` shell
$ openstack --os-cloud default floating ip list | grep None
| 753914ad-31b8-44eb-9ad7-cb9d75b81b58 | 65.17.X.X | None | None | 723f8fa2-dbf7-4cec-8d5f-017e62c12f79 | 9e822f3bce56475787f3000aa4ef89e6 |
```

You will also need to know the port id of your load balancer:

``` shell
$ openstack --os-cloud default loadbalancer show OVN-Test | grep vip_port_id
| vip_port_id         | 38c74c73-bc3f-430e-b663-d419ce7be4e6 |
```

With both of these pieces of information, you can associate your floating IP:

``` shell
openstack --os-cloud default floating ip set --port 38c74c73-bc3f-430e-b663-d419ce7be4e6 65.17.X.X
```
