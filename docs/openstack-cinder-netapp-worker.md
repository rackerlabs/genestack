---
hide:
  - footer
---

# NetApp Volume Worker – **Operator Guide**

This guide walks **cloud operators** through the end‑to‑end workflow for enabling the **NetApp ONTAP** backend in an OpenStack‑powered
Kubernetes environment.  It is opinionated toward day‑to‑day operators who need fast, repeatable steps rather than deep driver theory.

## Preparation

### Ensure DNS updated

If your storage host isn’t a Kubernetes worker, configure **systemd‑resolved** manually to allow the cinder-volume service
to resolve the OpenStack API endpoints:

```ini
[Resolve]
DNS=169.254.25.10 # Node Local DNS
Domains=openstack.svc.cluster.local svc.cluster.local cluster.local
DNSSEC=no
Cache=no-negative
```

```shell
systemctl restart systemd-resolved
```

### Requirements

The NetApp Volume Worker is a **cinder-volume** service that is configured to use the Cinder NetApp ONTAP driver. This service is responsible for
managing the creation, deletion, and management of volumes in the OpenStack environment. The NetApp Volume Worker is a stateful service
that is deployed on a baremetal node that has access to the NetApp storage system.

| Parameter                | Description                                                  |
| ------------------------ | ------------------------------------------------------------ |
| `LOGIN`                  | NetApp administrative credentials (secure vault recommended) |
| `PASSWORD`               | NetApp administrative credentials (secure vault recommended) |
| `SERVER_NAME_OR_ADDRESS` | FQDN or IP of the ONTAP cluster                              |
| `SERVER_PORT`            | `80` (HTTP) or `443` (HTTPS)                                 |
| `VSERVER`                | SVM that will host the LUNs                                  |
| 'PROTOCOL'               | `iscsi` or `NFS`                                             |

## Configure the cinder backends

Example of the cinder backend configuration:

```yaml {title="cinder-helm-overrides.yaml"}
conf:
  cinder:
    DEFAULT:
      default_availability_zone: az1
      default_volume_type: netapp-iscsi
      enabled_backends: netapp-iscsi-block1
  backends:
    netapp-iscsi-block1:
      netapp_login: <LOGIN>
      netapp_password: <PASSWORD>
      netapp_server_hostname: <SERVER_NAME_OR_ADDRESS>
      netapp_server_port: <SERVER_PORT>
      netapp_storage_family: ontap_cluster
      netapp_storage_protocol: <PROTOCOL>
      netapp_transport_type: http
      netapp_vserver: <VSERVER>
      netapp_dedup: true
      netapp_compression: true
      netapp_thick_provisioned: true
      netapp_lun_space_reservation: enabled # Reserve lun space inside netapp volume (thick)
      volume_driver: cinder.volume.drivers.netapp.common.NetAppDriver
      volume_backend_name: netapp-iscsi
```

Once configured, the cinder API must be updated but before updating the configuration, the
volume type must be pre-created.
Ensure that the name of volume type name matches the cinder configuration along with the
`volume_backend_name` property that groups multiple hosts into a pool of nodes.

The name of the volume type can be freely choosen but its properties and name must match what is configured
under `default_volume_type` and `volume_backend_name`

Refer to additional information for Cinder API:

- [Volume QoS](openstack-cinder-volume-qos-policies.md)
- [Provisioning Specs](openstack-cinder-volume-provisioning-specs.md)
- [Extra Specs](openstack-cinder-volume-type-specs.md)

```shell
openstack --os-cloud default volume type create netapp-iscsi --property volume_backend_name=netapp-iscsi

/opt/genestack/bin/install-cinder.sh
```

## Install cinder-volume on bare metal node

The Genestack inventory `/etc/genestack/inventory/inventory.yaml` must be configured with the
`cinder_storage_nodes` group:

!!! tip
    Since most storage operations are done on the NetApp storage the `cinder-volume` service can be
    colocated on the contoller nodes. The glance image operations such as download of images and upload
    into storage volumes is still executed on the node where the `cinder-volume` service resides.

```yaml
storage_nodes:
  children:
    cinder_storage_nodes: # nodes used for cinder storage labeled as openstack-storage-node=enabled
      vars:
        cinder_backend_name: netapp-iscsi-block1
        cinder_worker_name: netapp
        storage_network_multipath: true
        storage_network_interface: ansible_br_storage # Omit if br-storage is already present
      hosts:
        controller1: null
```

Once all requirements are met, the cinder-volume service can be installed.

```shell
source /opt/genestack/scripts/genestack.rc

ansible-playbook /opt/genestack/ansible/playbooks/deploy-cinder-volume.yaml
```

Check that the service becomes available:

```shell
+------------------+------------------------------------------+------+---------+-------+----------------------------+---------+---------------+
| Binary           | Host                                     | Zone | Status  | State | Updated At                 | Cluster | Backend State |
+------------------+------------------------------------------+------+---------+-------+----------------------------+---------+---------------+
| cinder-scheduler | cinder-volume-worker                     | az1  | enabled | up    | 2026-04-09T02:52:01.000000 | None    | None          |
| cinder-volume    | cinder-volume-netapp-worker@netapp-iscsi | az1  | enabled | up    | 2026-04-09T02:51:59.000000 | None    | None          |
+------------------+----------------------------------------¡-+------+---------+-------+----------------------------+---------+---------------+
```

### Create a test volume

```shell
openstack --os-cloud default volume create --size 1 --type netapp-iscsi smoke-test-netapp
```

!!! example "Expected Output"

    ```shell
    +---------------------+--------------------------------------+
    | Field               | Value                                |
    +---------------------+--------------------------------------+
    | attachments         | []                                   |
    | availability_zone   | az1                                  |
    | bootable            | false                                |
    | consistencygroup_id | None                                 |
    | created_at          | 2023-12-26T17:46:15.639697           |
    | description         | None                                 |
    | encrypted           | False                                |
    | id                  | c744af27-fb40-4ffa-8a84-b9f44cb19b2b |
    | migration_status    | None                                 |
    | multiattach         | False                                |
    | name                | smoke-test-netapp                    |
    | properties          |                                      |
    | replication_status  | None                                 |
    | size                | 1                                    |
    | snapshot_id         | None                                 |
    | source_volid        | None                                 |
    | status              | creating                             |
    | type                | netapp-iscsi                         |
    | updated_at          | None                                 |
    | user_id             | 2ddf90575e1846368253474789964074     |
    +---------------------+--------------------------------------+
    ```

### Validate the test volume

```shell
openstack --os-cloud default volume list
```

!!! example "Expected Output"

    ```shell
    +--------------------------------------+-------------------+-----------+------+-------------+
    | ID                                   | Name              | Status    | Size | Attached to |
    +--------------------------------------+-------------------+-----------+------+-------------+
    | c744af27-fb40-4ffa-8a84-b9f44cb19b2b | smoke-test-netapp | available |    1 |             |
    +--------------------------------------+-------------------+-----------+------+-------------+
    ```

##  Enable iSCSI & Multipath on Compute Nodes

###  Nova chart overrides

Edit `/etc/genestack/helm-configs/nova/nova-helm-cinder-overrides.yaml`

```yaml
enable_iscsi: true
```

#### Optionally Enable multipath

```yaml
volume_use_multipath: true
```

### Host services

Add to inventory and rerun **host‑setup**:

```yaml
storage:
  vars:
    enable_iscsi: true
    storage_network_multipath: true # optional – uses queue-length policy
```

!!! Tip "When using multipath"

    Deploy two storage bridges and VLANs (`storage_network_interface`, `storage_network_interface_secondary`  for path redundancy
    or configure at least 2x iSCSI enabled LIF on the netapp storage as target and benefit from simplified bonding on the

The multipath output can also be validated on the compute nodes.

```shell
multipath -ll
```

!!! example "Expected Output"

    ```shell
       3600a098038323434303f5948454d3965 dm-110 NETAPP,LUN C-Mode
       size=80G features='3 queue_if_no_path pg_init_retries 50' hwhandler='1 alua' wp=rw
       |-+- policy='service-time 0' prio=0 status=active
       | `- 17:0:0:7 sdbd 67:112 active undef running
       `-+- policy='service-time 0' prio=0 status=enabled
         `- 18:0:0:7 sdbe 67:128 active undef running
    ```

## Appendix

### Common Issues

| Symptom                           | Cause                             | Resolution                                     |
| --------------------------------- | --------------------------------- | ---------------------------------------------- |
| `No valid host was found`         | Volume type not mapped to backend | Check `volume_backend_name` extra‑spec         |
| VM cannot reach disk after reboot | Multipath disabled                | Ensure **Enable iSCSI & Multipath** completed  |
