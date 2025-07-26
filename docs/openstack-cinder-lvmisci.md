# Cinder LVM iSCSI – **Operator Guide**

This guide explains how a **cloud operator** can enable the **reference LVM backend** over iSCSI for OpenStack Cinder. It assumes you are running
the volume service directly on bare‑metal storage nodes.

In order to utilize the logical volume driver (reference), it must be deployed in hybrid way, outside of the K8s workflow on baremetal volume hosts.
Specifically, iSCSI is incompatible with containerized work environments. Fortunately, Genestack has a playbook which will facilitate the installation
of cinder-volume services and ensure that everything is deployed in working order on the baremetal nodes. The playbook can be found at
`playbooks/deploy-cinder-volumes-reference.yaml`. Included in the playbooks directory is an example inventory for cinder hosts; however, any inventory
should work fine.

## Quick path to success

1. 📝 Pre‑flight checklist
2. 🦾 Storage‑node preparation
3. 🚀 Run the deployment playbook
4. 📦 Create volume type & policies
5. 🔍 Validate operations
6. ⚙️ Enable iSCSI + multipath for computes

## 1  Pre‑Flight Checklist

| Item                                 | Why it matters                                                  |
| ------------------------------------ | --------------------------------------------------------------- |
| CoreDNS reachable from storage nodes | Cinder‑Volume must talk to Keystone & RabbitMQ over service DNS |
| Free block device (e.g. `/dev/vdf`)  | Will be turned into the **cinder‑volumes‑1** VG                 |
| Playbook inventory updated           | Storage nodes grouped as `cinder_storage_nodes`                 |
| Volume‑type policies drafted         | QoS, provisioning, and extra specs prepared                     |

!!! warning "VG name must match driver stanza"

    The reference driver hard‑codes `lvmdriver-1` (volume type) and `cinder-volumes-1` (volume group). Keep these names unless you also
    edit the playbook templates.

## 2  Storage‑Node Preparation

Because the Cinder Reference LVM driver is incompatible with a containerized work environment, the services are setup as baremetal targets.
Genestack has a playbook which will facilitate the installation of our services and ensure that we've deployed everything in a working order.
The playbook can be found at `playbooks/deploy-cinder-volumes-reference.yaml`. Included in the playbooks directory is an example inventory
for our cinder hosts; however, any inventory should work fine.

### 2.1  Ensure DNS Works

If your storage host isn’t a Kubernetes worker, configure **systemd‑resolved** manually:

``` ini
[Resolve]
DNS=169.254.25.10  # CoreDNS VIP
Domains=openstack.svc.cluster.local svc.cluster.local cluster.local
DNSSEC=no
Cache=no-negative
```

``` bash
systemctl restart systemd-resolved
```

### 2.2  Create Volume Group

``` bash
pvcreate /dev/vdf
vgcreate cinder-volumes-1 /dev/vdf
```

Add additional PVs to extend capacity later as needed.

## 3  Deploy the LVM Volume Worker

Add the `enable_iscsi` and `storage_network_multipath` variables to the inventory file vars stanzas pertaining to nova_compute_nodes
and cinder_storage_nodes. Additionally, add the `storage_network_multipath` to the inventory file vars only for cinder_storage_nodes.
Edit /opt/genestack/ansible/playbooks/templates/genestack-multipath.conf.j2 to meet your specific requirements. Then re-run
`host-setup.yaml` on compute nodes and block nodes.

## 3.1  Prepare the Inventory

Within the `inventory.yaml` file, ensure you have the following variables for your storage nodes:

```  yaml
openstack_compute_nodes:
  vars:
    enable_iscsi: true
    custom_multipath: false  # optional -- enable when running multipath with custom multipath.conf
storage_nodes:
  vars:
    enable_iscsi: true
    storage_network_multipath: false  # optional -- enable when running multipath
```

Hosts should be grouped as `storage_nodes` in the inventory file. The host are simple and can be defined as follows:

```  yaml
  hosts:
    1258871-tenant.prod.sjc3.ohthree.com:
      ansible_host: "172.24.9.40"
      network_mgmt_address: "172.24.9.40"
      network_overlay_address: "172.24.65.40"
      network_storage_address: "172.24.13.40"
      network_storage_a_address: "172.24.68.40"  # optional -- for multi-path
      network_storage_b_address: "172.24.72.40"  # optional -- for multi-path
```

## 3.2 Run the Playbook

Use the hybrid playbook to install `cinder-volume` as a **systemd** service:

```  bash
ansible-playbook -i inventory.yaml playbooks/deploy-cinder-volumes-reference.yaml
```

!!! example "Runtime with CLI flags"

    ``` console
    ansible-playbook -i /etc/genestack/inventory/inventory.yaml deploy-cinder-volumes-reference.yaml \
                    -e "cinder_storage_network_interface=ansible_br_storage_a cinder_storage_network_interface_secondary=ansible_br_storage_b storage_network_multipath=true cinder_backend_name=lvmdriver-1" \
                    --user ubuntu \
                    --become 'cinder_storage_nodes'
    ```

    !!! note

        Consider the **storage** network on your Cinder hosts that will be accessible to Nova compute hosts. By default, the playbook uses
        `ansible_default_ipv4.address` to configure the target address, which may or may not work for your environment. Append var, i.e.,
        `-e cinder_storage_network_interface=ansible_br_mgmt` to use the specified iface address in `cinder.conf` for `my_ip` and
        `target_ip_address` in `cinder/backends.conf`. **Interface names with a `-` must be entered with a `_` and be prefixed with `ansible`**

The playbook will:

1. Drop the python release payload.
2. Render `/etc/cinder/cinder.conf` with an `[lvmdriver-1]` stanza.
3. Enable + start `cinder-volume` under systemd.

## 4  Create Volume Type & Attach Policies

``` bash
openstack --os-cloud default volume type create lvmdriver-1
```

!!! example "Expected Output"

    ``` shell
    +-------------+--------------------------------------+
    | Field       | Value                                |
    +-------------+--------------------------------------+
    | description | None                                 |
    | id          | 6af6ade2-53ca-4260-8b79-1ba2f208c91d |
    | is_public   | True                                 |
    | name        | lvmdriver-1                          |
    +-------------+--------------------------------------+
    ```

Refer to:

- [Volume QoS](openstack-cinder-volume-qos-policies.md)
- [Provisioning Specs](openstack-cinder-volume-provisioning-specs.md)
- [Extra Specs](openstack-cinder-volume-type-specs.md)

## 5  Validate Operations

### 5.1  Service status

``` bash
kubectl -n openstack exec -ti openstack-admin-client -- openstack volume service list
```

!!! example "Expected Output"

    ``` shell
    root@openstack-node-0:~# kubectl --namespace openstack exec -ti openstack-admin-client -- openstack volume service list
    +------------------+--------------------------------------------+------+---------+-------+----------------------------+
    | Binary           | Host                                       | Zone | Status  | State | Updated At                 |
    +------------------+--------------------------------------------+------+---------+-------+----------------------------+
    | cinder-scheduler | cinder-volume-worker                       | nova | enabled | up    | 2023-12-26T17:43:07.000000 |
    | cinder-volume    | openstack-node-4.cluster.local@lvmdriver-1 | nova | enabled | up    | 2023-12-26T17:43:04.000000 |
    +------------------+--------------------------------------------+------+---------+-------+----------------------------+
    ```

Should show `openstack-node‑X@lvmdriver-1` **enabled/up**.

### 5.2  Create a test volume

``` bash
openstack --os-cloud default volume create --size 1 --type lvmdriver-1 smoke-test-lvm
```

!!! example "Expected Output"

    ``` shell
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
    | type                | lvmdriver-1                          |
    | updated_at          | None                                 |
    | user_id             | 2ddf90575e1846368253474789964074     |
    +---------------------+--------------------------------------+
    ```

### 5.3  Validate the test volume

``` bash
root@openstack-node-0:~# kubectl --namespace openstack exec -ti openstack-admin-client -- openstack volume list
```

!!! example "Expected Output"

    ``` shell
    +--------------------------------------+------+-----------+------+-------------+
    | ID                                   | Name | Status    | Size | Attached to |
    +--------------------------------------+------+-----------+------+-------------+
    | c744af27-fb40-4ffa-8a84-b9f44cb19b2b | test | available |    1 |             |
    +--------------------------------------+------+-----------+------+-------------+
    ```

Check on the storage node:

``` bash
lvs
```

You can validate the environment is operational by logging into the storage nodes to validate the LVM targets are being created.

!!! example "Expected Output"

    ``` shell
    LV                                   VG               Attr       LSize Pool Origin Data%  Meta%  Move Log Cpy%Sync Convert
    c744af27-fb40-4ffa-8a84-b9f44cb19b2b cinder-volumes-1 -wi-a----- 1.00g
    ```

If the LV exists, Cinder is provisioning correctly.

## 6  Enable iSCSI & Multipath on Compute Nodes

### 6.1  Nova chart overrides

Edit `/etc/genestack/helm-configs/nova/nova-helm-cinder-overrides.yaml`

``` yaml
enable_iscsi: true
```

#### 6.1.1  Optionally Enable Multipath

``` yaml
volume_use_multipath: true
```

### 6.2  Host services

Add to inventory and rerun **host‑setup**:

``` yaml
storage:
  vars:
    enable_iscsi: true
    storage_network_multipath: true   # optional – uses queue-length policy
```

!!! Tip "When using Multipath"

    Deploy two storage VLANs (`network_storage_address` and `network_storage_a_address`, `network_storage_b_address`) for path redundancy.

## 7  Verify Multipath Operations

If multipath is enabled on compute nodes, you can verify dual iscsi targets on the storage nodes.

``` bash
tgtadm --mode target --op show
```

!!! example "Expected Output"

    ``` shell
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

``` bash
multipath -ll
```

!!! example "Expected Output"

    ``` shell
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
