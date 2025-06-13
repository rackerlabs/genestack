# NetApp Volume Worker – **Operator Guide**

This guide walks **cloud operators** through the end‑to‑end workflow for enabling the **NetApp ONTAP** backend in an OpenStack‑powered
Kubernetes environment.  It is opinionated toward day‑to‑day operators who need fast, repeatable steps rather than deep driver theory.

## At‑a‑glance workflow

1. ✅ Pre‑flight checks
2. 🛠 Backend & secret creation
3. 🖥 Compute‑node preparation
4. 🚀 Deploy the NetApp Volume Worker
5. 🔎 Validate & troubleshoot

## 1  Pre‑Flight Checks

The NetApp Volume Worker is a **cinder-volume** service that is configured to use the NetApp ONTAP driver. This service is responsible for
managing the creation, deletion, and management of volumes in the OpenStack environment. The NetApp Volume Worker is a stateful service
that is deployed on a baremetal node that has access to the NetApp storage system.

### 1.1  Gather NetApp Credentials

| Parameter                | Description                                                  |
| ------------------------ | ------------------------------------------------------------ |
| `LOGIN`                  | NetApp administrative credentials (secure vault recommended) |
| `PASSWORD`               | NetApp administrative credentials (secure vault recommended) |
| `SERVER_NAME_OR_ADDRESS` | FQDN or IP of the ONTAP cluster                              |
| `SERVER_PORT`            | `80` (HTTP) or `443` (HTTPS)                                 |
| `VSERVER`                | SVM that will host the LUNs                                  |

## 2  Cinder Backends

Before deploying a new backend, ensure that your volume type has been set up correctly and that you have applied QoS policies, provisioning
specifications (min and max volume size), and any extra specs. See [Cinder Volume QoS Policies](openstack-cinder-volume-qos-policies.md),
[Cinder Volume Provisioning Specs](openstack-cinder-volume-provisioning-specs.md), and [Cinder Volume Type Specs](openstack-cinder-volume-type-specs.md).

### 2.1  Define Backends in Helm Override

The NetApp ONTAP driver requires a backend configuration to be set in the Kubernetes environment. The backend configuration
specifies the storage system that the NetApp Volume Worker will use to create and manage volumes. The backend configuration
is a Kubernetes secret that contains the necessary configuration parameters for the NetApp ONTAP driver. To define the backends,
update the helm overrides file with the necessary configuration parameters.

Edit (or create) `cinder-helm-netapp-overrides.yaml`:

``` yaml
conf:
  backends:
    block-ha-performance-at-rest-encrypted:
      netapp_login: <LOGIN>
      netapp_password: <PASSWORD>
      netapp_server_hostname: <SERVER_NAME_OR_ADDRESS>
      netapp_server_port: <SERVER_PORT>
      netapp_storage_family: ontap_cluster
      netapp_storage_protocol: iscsi
      netapp_transport_type: http
      netapp_vserver: <VSERVER>
      netapp_dedup: true
      netapp_compression: true
      netapp_thick_provisioned: true
      netapp_lun_space_reservation: enabled
      volume_driver: cinder.volume.drivers.netapp.common.NetAppDriver
      volume_backend_name: block-ha-performance-at-rest-encrypted
    block-ha-standard-at-rest-encrypted:
      # …same pattern…
```

Commit the override to your GitOps repo (if applicable) so that it is version‑controlled.

## 3  Compute‑Node Preparation

## 3.1  Prepare the Inventory

Within the `inventory.yaml` file, ensure you have the following variables for your storage nodes:

The netapp backend can use both NFS or iSCSI protocols. The following example provides the variables that can be used for both protocols.

!!! genestack "Storage Node Variables"

    If you are using iSCSI, ensure that the `enable_iscsi` variable is set to `true`. If you are using NFS, set it to `false`.
    The `custom_multipath` variable is optional and can be set to `true` if you are running multipath on the storage nodes.

```  yaml
openstack_compute_nodes:
  vars:
    enable_iscsi: false      # optional -- enable iSCSI on storage nodes
    custom_multipath: false  # optional -- enable when running multipath
storage_nodes:
  vars:
    enable_iscsi: false      # optional -- enable iSCSI on storage nodes
    custom_multipath: false  # optional -- enable when running multipath
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

### 3.1  Nova chart overrides

Edit `/etc/genestack/helm-configs/nova/nova-helm-cinder-overrides.yaml`

``` yaml
enable_iscsi: true  # optional – enables templated multipath.conf
```

#### 3.1.1  Optionally Enable Multipath

``` yaml
volume_use_multipath: true  # optional – enables templated multipath.conf
```

### 3.2  Configure Services on Hosts

Add the variables to inventory and rerun **host‑setup**:

``` yaml
storage:
  vars:
    enable_iscsi: true      # optional -- enable iSCSI on storage nodes
    custom_multipath: true  # optional – enables templated multipath.conf
```

!!! note "The provided `genestack-multipath.conf` template distributes I/O across **all** active paths (queue‑length algorithm). Adjust for your environment if necessary."

### 3.3  DNS Sanity Check

If the storage node was not bootstrapped as a Kubernetes worker, ensure it resolves cluster DNS:

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

## 4  Deploy the NetApp Volume Worker

Run the reference playbook against the `cinder_storage_nodes` group:

``` bash
ansible-playbook -i inventory.yaml deploy-cinder-volumes-netapp-reference.yaml
```

The playbook

1. Installs the `cinder-volume-netapp` systemd unit.
2. Renders `/etc/cinder/cinder.conf` with your backend stanza.
3. Labels the node so Helm skips native Cinder chart pods.

## 5  Validate & Troubleshoot

## 5.1  Create Volume Type & Attach Policies

``` bash
openstack --os-cloud default volume type create block-ha-performance-at-rest-encrypted
```

!!! example "Expected Output"

    ``` shell
    +-------------+----------------------------------------+
    | Field       | Value                                  |
    +-------------+----------------------------------------+
    | description | None                                   |
    | id          | 6af6ade2-53ca-4260-8b79-1ba2f208c91d   |
    | is_public   | True                                   |
    | name        | block-ha-performance-at-rest-encrypted |
    +-------------+----------------------------------------+
    ```

Refer to:

- [Volume QoS](openstack-cinder-volume-qos-policies.md)
- [Provisioning Specs](openstack-cinder-volume-provisioning-specs.md)
- [Extra Specs](openstack-cinder-volume-type-specs.md)

!!! warning "Backend without policies = sad tenants"

    Skipping this step may leave tenants with a backend they cannot consume or that violates performance guarantees.

### 5.2  Service Health

``` bash
kubectl -n openstack exec -ti openstack-admin-client -- openstack volume service list
```

Successful output should resemble the following, with the backend name matching your `volume_backend_name`:

!!! example "Expected Output"

    ``` shell
    +------------------+--------------------------------------------------------------------+------+---------+-------+----------------------------+
    | Binary           | Host                                                               | Zone | Status  | State | Updated At                 |
    +------------------+--------------------------------------------------------------------+------+---------+-------+----------------------------+
    | cinder-scheduler | cinder-volume-worker                                               | az1  | enabled | up    | 2023-12-26T17:43:07.000000 |
    | cinder-volume    | cinder-volume-netapp-worker@block-ha-performance-at-rest-encrypted | az1  | enabled | up    | 2023-12-26T17:43:04.000000 |
    +------------------+--------------------------------------------------------------------+------+---------+-------+----------------------------+
    ```

### 5.3  Create a Test Volume

``` bash
openstack --os-cloud default volume create --size 1 --type block-ha-performance-at-rest-encrypted smoke-test-vol
```

!!! example "Expected Output"

    ``` shell
    +---------------------+----------------------------------------+
    | Field               | Value                                  |
    +---------------------+----------------------------------------+
    | attachments         | []                                     |
    | availability_zone   | az1                                    |
    | bootable            | false                                  |
    | consistencygroup_id | None                                   |
    | created_at          | 2023-12-26T17:46:15.639697             |
    | description         | None                                   |
    | encrypted           | False                                  |
    | id                  | c744af27-fb40-4ffa-8a84-b9f44cb19b2b   |
    | migration_status    | None                                   |
    | multiattach         | False                                  |
    | name                | test                                   |
    | properties          |                                        |
    | replication_status  | None                                   |
    | size                | 1                                      |
    | snapshot_id         | None                                   |
    | source_volid        | None                                   |
    | status              | creating                               |
    | type                | block-ha-performance-at-rest-encrypted |
    | updated_at          | None                                   |
    | user_id             | 2ddf90575e1846368253474789964074       |
    +---------------------+----------------------------------------+
    ```

### 5.3.1  Validate the test volume

``` bash
kubectl --namespace openstack exec -ti openstack-admin-client -- openstack volume list
```

!!! example "Expected Output"

    ``` shell
    +--------------------------------------+------+-----------+------+-------------+
    | ID                                   | Name | Status    | Size | Attached to |
    +--------------------------------------+------+-----------+------+-------------+
    | c744af27-fb40-4ffa-8a84-b9f44cb19b2b | test | available |    1 |             |
    +--------------------------------------+------+-----------+------+-------------+
    ```

If the volume transitions to **available** and ONTAP shows a corresponding LUN, the backend is operational.

## 6  Verify Multipath Operations

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

### Variable Reference

| Variable                                        | Purpose                                               |
| ----------------------------------------------- | ----------------------------------------------------- |
| `netapp_login`                                  | Credentials to ONTAP                                  |
| `netapp_password`                               | Credentials to ONTAP                                  |
| `netapp_server_hostname`                        | Cluster management interface hostname                 |
| `netapp_server_port`                            | Cluster management interface port                     |
| `netapp_storage_family`                         | Always `ontap_cluster` for ONTAP                      |
| `netapp_storage_protocol`                       | `iscsi`, `nfs`, or `fc` (guide assumes iSCSI)         |
| `netapp_vserver`                                | SVM hosting the volumes                               |
| `netapp_dedup`, `netapp_compression`            | Space efficiency flags                                |
| `netapp_thick_provisioned`                      | `true` → thick LUNs; `false` → thin                   |
| `netapp_lun_space_reservation`                  | `enabled`/`disabled`                                  |
| `volume_backend_name`                           | Identifier referenced by **volume type extra\_specs** |

### Common Issues

| Symptom                   | Likely Cause                       | Fix                                                  |
| ------------------------- | ---------------------------------- | ---------------------------------------------------- |
| `No valid host was found` | Backend mis‑named in `extra_specs` | Ensure `volume_backend_name` matches type‑extra‑spec |
| iSCSI session flaps       | Multipath not enabled              | Verify `multipathd` is running and config is correct |
| DNS resolution fails      | Node not using CoreDNS             | Review **3.3 DNS Sanity Check**                      |
