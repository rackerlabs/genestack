---
hide:
  - footer
---

# Cinder LVM iSCSI – **Operator Guide**

This guide explains how a **cloud operator** can enable the **reference LVM backend** over iSCSI for OpenStack Cinder. It assumes you are running
the volume service directly on bare‑metal storage nodes.

In order to utilize the logical volume driver (reference), it must be deployed in hybrid way, outside of the K8s workflow on baremetal volume hosts.
Specifically, iSCSI is incompatible with containerized work environments. Fortunately, Genestack has a playbook which will facilitate the installation
of cinder-volume services and ensure that everything is deployed in working order on the baremetal nodes.

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

### Create Volume Group

Before deploying `cinder-volume`, backends must be defined and injected into the `cinder-etc` configmap.
This example also assumes that a local LVM group `cinder-volumes` is pre-configured as as following:

```shell
pvcreate --metadatasize 2048 physical_volume_device_path
vgcreate cinder-volumes physical_volume_device_path
```

## Configure the cinder backends

Example of the cinder backend configuration:

```yaml {title="cinder-helm-overrides.yaml"}
conf:
  cinder:
    DEFAULT:
      default_availability_zone: az1
      default_volume_type: lvm-ssd
      enabled_backends: lvm-ssd-1
  backends:
    lvm-ssd-1:
      volume_driver: cinder.volume.drivers.lvm.LVMVolumeDriver
      volume_group: cinder-volumes
      volume_backend_name: lvm-ssd
      iscsi_protocol: iscsi
      iscsi_helper: lioadm
```

Once configured, the cinder API must be updated but before updating the configuration, the
volume type must be pre-created.
Ensure that the name of volume type name matches the cinder configuration along with the
`volume_backend_name` property that groups multiple hosts into a pool of nodes.

Refer to additional information for Cinder API:

- [Volume QoS](openstack-cinder-volume-qos-policies.md)
- [Provisioning Specs](openstack-cinder-volume-provisioning-specs.md)
- [Extra Specs](openstack-cinder-volume-type-specs.md)

```shell
openstack --os-cloud default volume type create lvm-ssd --property volume_backend_name=lvm-ssd

/opt/genestack/bin/install-cinder.sh
```

## Install cinder-volume on bare metal node

The Genestack inventory `/etc/genestack/inventory/inventory.yaml` must be configured with the
`cinder_storage_nodes` group:

```yaml
storage_nodes:
  children:
    cinder_storage_nodes: # nodes used for cinder storage labeled as openstack-storage-node=enabled
      vars:
        cinder_backend_name: lvm-ssd-1
        cinder_worker_name: lvm
        storage_network_multipath: false # Enable when multiple storage network exist
        storage_network_interface: ansible_br_storage # Omit if br-storage is already present
      hosts:
        cinder-host1: null
```

!!! warning
    Do not colocate the cinder-volume service with hosts that are also used for Longhorn, as
    both use the kernel iSCSI stack. The service can only run on bare metal node and can't be
    containerized either.

Once all requirements are met, the cinder-volume service can be installed.

```shell
source /opt/genestack/scripts/genestack.rc

ansible-playbook /opt/genestack/ansible/playbooks/deploy-cinder-volume.yaml -e cinder_backend_name=lvm-ssd-1 -e cinder_worker_name=lvm
```

Check that the service becomes available:

```shell
+------------------+---------------------------+------+---------+-------+----------------------------+---------+---------------+
| Binary           | Host                      | Zone | Status  | State | Updated At                 | Cluster | Backend State |
+------------------+---------------------------+------+---------+-------+----------------------------+---------+---------------+
| cinder-scheduler | cinder-volume-worker      | az1  | enabled | up    | 2026-04-09T02:52:01.000000 | None    | None          |
| cinder-backup    | cinder-host1              | az1  | enabled | up    | 2026-04-09T02:51:57.000000 | None    | None          |
| cinder-volume    | cinder-host1@lvm-ssd-1    | az1  | enabled | up    | 2026-04-09T02:51:59.000000 | None    | None          |
+------------------+---------------------------+------+---------+-------+----------------------------+---------+---------------+
```

### Create a test volume

```shell
openstack --os-cloud default volume create --size 1 --type lvm-ssd smoke-test-lvm
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
    | name                | test                                 |
    | properties          |                                      |
    | replication_status  | None                                 |
    | size                | 1                                    |
    | snapshot_id         | None                                 |
    | source_volid        | None                                 |
    | status              | creating                             |
    | type                | lvm-ssd                              |
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
    +--------------------------------------+------+-----------+------+-------------+
    | ID                                   | Name | Status    | Size | Attached to |
    +--------------------------------------+------+-----------+------+-------------+
    | c744af27-fb40-4ffa-8a84-b9f44cb19b2b | test | available |    1 |             |
    +--------------------------------------+------+-----------+------+-------------+
    ```

Check on the storage node:

```shell
lvs
```

You can validate the environment is operational by logging into the storage nodes to validate the LVM targets are being created.

!!! example "Expected Output"

    ```shell
    LV                                   VG             Attr       LSize Pool Origin Data%  Meta%  Move Log Cpy%Sync Convert
    c744af27-fb40-4ffa-8a84-b9f44cb19b2b cinder-volumes -wi-a----- 1.00g
    ```

If the LV exists, Cinder is provisioning correctly.

##  Enable iSCSI & Multipath on Compute Nodes

###  Nova chart overrides

Edit `/etc/genestack/helm-configs/nova/nova-helm-cinder-overrides.yaml`

```yaml
enable_iscsi: true
```

#### Optionally Enable Multipath

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

!!! Tip "When using Multipath"

    Deploy two storage bridges and VLANs (`storage_network_interface`, `storage_network_interface_secondary`  for path redundancy.

## Verify Multipath Operations

If multipath is enabled on compute nodes, you can verify dual iscsi targets on the storage nodes.

```shell
tgtadm --mode target --op show
```

!!! example "Expected Output"

    ```shell
    Target 4: iqn.2010-10.org.openstack:dd88d4b9-1297-44c1-b9bc-efd6514be035
        System information:
            Driver: iscsi
            State: ready
        I_T nexus information:
            I_T nexus: 4
                Initiator: iqn.2004-10.com.ubuntu:01:8392e3447710 alias: genestack-compute2.cluster.local
                Connection: 0
                    IP Address: 10.1.2.213
            I_T nexus: 5
                Initiator: iqn.2004-10.com.ubuntu:01:8392e3447710 alias: genestack-compute2.cluster.local
                Connection: 0
                    IP Address: 10.1.1.213
        LUN information:
            LUN: 0
                Type: controller
                SCSI ID: IET     00040000
                SCSI SN: beaf40
                Size: 0 MB, Block size: 1
                Online: Yes
                Removable media: No
                Prevent removal: No
                Readonly: No
                SWP: No
                Thin-provisioning: No
                Backing store type: null
                Backing store path: None
                Backing store flags:
            LUN: 1
                Type: disk
                SCSI ID: IET     00040001
                SCSI SN: beaf41
                Size: 10737 MB, Block size: 512
                Online: Yes
                Removable media: No
                Prevent removal: No
                Readonly: No
                SWP: No
                Thin-provisioning: No
                Backing store type: rdwr
                Backing store path: /dev/cinder-volumes-1/dd88d4b9-1297-44c1-b9bc-efd6514be035
                Backing store flags:
        Account information:
            sRs8FV73FeaF2LFnPb4j
        ACL information:
            ALL
    ```

The multipath output can also be validated on the compute nodes.

```shell
multipath -ll
```

!!! example "Expected Output"

    ```shell
    360000000000000000e00000000010001 dm-0 IET,VIRTUAL-DISK
    size=10G features='0' hwhandler='0' wp=rw
    `-+- policy='queue-length 0' prio=1 status=active
    |- 2:0:0:1 sda 8:0  active ready running
    `- 3:0:0:1 sdb 8:16 active ready running
    ```

## Appendix

### Common Issues

| Symptom                           | Cause                             | Resolution                                      |
| --------------------------------- | --------------------------------- | ----------------------------------------------- |
| `No valid host was found`         | Volume type not mapped to backend | Check `volume_backend_name` extra‑spec          |
| `tgtadm` shows no targets         | `cinder-volume` failed to start   | `journalctl -u cinder-volume` for details       |
| VM cannot reach disk after reboot | Multipath disabled                | Ensure **6 Enable iSCSI & Multipath** completed |
