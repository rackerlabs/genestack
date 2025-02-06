# Cinder LVM iSCSI Deployment

Once the helm deployment is complete cinder and all of it's API services will be online. However, using this setup there will be
no volume node at this point. The reason volume deployments have been disabled is because we didn't expose ceph to the openstack
environment and OSH makes a lot of ceph related assumptions. For testing purposes we're wanting to run with the logical volume
driver (reference) and manage the deployment of that driver in a hybrid way. As such there's a deployment outside of our normal
K8S workflow will be needed on our volume host.

!!! note

    The LVM volume makes the assumption that the storage node has the required volume group setup `lvmdriver-1` on the node This is not something that K8S is handling at this time.

While cinder can run with a great many different storage backends, for the simple case we want to run with the Cinder reference
driver, which makes use of Logical Volumes. Because this driver is incompatible with a containerized work environment, we need
to run the services on our baremetal targets. Genestack has a playbook which will facilitate the installation of our services
and ensure that we've deployed everything in a working order. The playbook can be found at `playbooks/deploy-cinder-volumes-reference.yaml`.
Included in the playbooks directory is an example inventory for our cinder hosts; however, any inventory should work fine.

## Host Setup

The cinder target hosts need to have some basic setup run on them to make them compatible with our Logical Volume Driver.

1. Ensure DNS is working normally.

Assuming your storage node was also deployed as a K8S node when we did our initial Kubernetes deployment, the DNS should already be
operational for you; however, in the event you need to do some manual tweaking or if the node was note deployed as a K8S worker, then
make sure you setup the DNS resolvers correctly so that your volume service node can communicate with our cluster.

!!! note

    This is expected to be our CoreDNS IP, in my case this is `169.254.25.10`.

This is an example of my **systemd-resolved** conf found in `/etc/systemd/resolved.conf`
``` conf
[Resolve]
DNS=169.254.25.10
#FallbackDNS=
Domains=openstack.svc.cluster.local svc.cluster.local cluster.local
#LLMNR=no
#MulticastDNS=no
DNSSEC=no
Cache=no-negative
#DNSStubListener=yes
```

Restart your DNS service after changes are made.

``` shell
systemctl restart systemd-resolved.service
```

2. Volume Group `cinder-volumes-1` needs to be created, which can be done in two simple commands.

Create the physical volume

``` shell
pvcreate /dev/vdf
```

Create the volume group

``` shell
vgcreate cinder-volumes-1 /dev/vdf
```

It should be noted that this setup can be tweaked and tuned to your heart's desire; additionally, you can further extend a
volume group with multiple disks. The example above is just that, an example. Check out more from the upstream docs on how
to best operate your volume groups for your specific needs.

## Hybrid Cinder Volume deployment

With the volume groups and DNS setup on your target hosts, it is now time to deploy the volume services. The playbook `playbooks/deploy-cinder-volumes-reference.yaml` will be used to create a release target for our python code-base and deploy systemd services
units to run the cinder-volume process.

!!! note

    Consider the **storage** network on your Cinder hosts that will be accessible to Nova compute hosts. By default, the playbook uses `ansible_default_ipv4.address` to configure the target address, which may or may not work for your environment. Append var, i.e., `-e cinder_storage_network_interface=ansible_br_mgmt` to use the specified iface address in `cinder.conf` for `my_ip` and `target_ip_address` in `cinder/backends.conf`. **Interface names with a `-` must be entered with a `_` and be prefixed with `ansible`**

### Example without storage network interface override

!!! note

    When deploying with multipath, the `enable_multipath` variable must be set to `true`. this can be done on the CLI or in the inventory file.

``` shell
ansible-playbook -i inventory-example.yaml deploy-cinder-volumes-reference.yaml
```

Once the playbook has finished executing, check the cinder api to verify functionality.

``` shell
root@openstack-node-0:~# kubectl --namespace openstack exec -ti openstack-admin-client -- openstack volume service list
+------------------+--------------------------------------------+------+---------+-------+----------------------------+
| Binary           | Host                                       | Zone | Status  | State | Updated At                 |
+------------------+--------------------------------------------+------+---------+-------+----------------------------+
| cinder-scheduler | cinder-volume-worker                       | nova | enabled | up    | 2023-12-26T17:43:07.000000 |
| cinder-volume    | openstack-node-4.cluster.local@lvmdriver-1 | nova | enabled | up    | 2023-12-26T17:43:04.000000 |
+------------------+--------------------------------------------+------+---------+-------+----------------------------+
```

!!! note

    The volume service is up and running with our `lvmdriver-1` target.

At this point it would be a good time to define your types within cinder. For our example purposes we need to define the `lvmdriver-1`
type so that we can schedule volumes to our environment.

``` shell
root@openstack-node-0:~# kubectl --namespace openstack exec -ti openstack-admin-client -- openstack volume type create lvmdriver-1
+-------------+--------------------------------------+
| Field       | Value                                |
+-------------+--------------------------------------+
| description | None                                 |
| id          | 6af6ade2-53ca-4260-8b79-1ba2f208c91d |
| is_public   | True                                 |
| name        | lvmdriver-1                          |
+-------------+--------------------------------------+
```

!!! warning

    **Before** creating a volume, ensure that your volume type has been set up correctly and that you have applied QoS policies, provisioning specifications (min and max volume size), and any extra specs. See [Cinder Volume QoS Policies](openstack-cinder-volume-qos-policies.md), [Cinder Volume Provisioning Specs](openstack-cinder-volume-provisioning-specs.md), and [Cinder Volume Type Specs](openstack-cinder-volume-type-specs.md).


## Validate functionality

If wanted, create a test volume to tinker with

``` shell
root@openstack-node-0:~# kubectl --namespace openstack exec -ti openstack-admin-client -- openstack volume create --size 1 test
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

root@openstack-node-0:~# kubectl --namespace openstack exec -ti openstack-admin-client -- openstack volume list
+--------------------------------------+------+-----------+------+-------------+
| ID                                   | Name | Status    | Size | Attached to |
+--------------------------------------+------+-----------+------+-------------+
| c744af27-fb40-4ffa-8a84-b9f44cb19b2b | test | available |    1 |             |
+--------------------------------------+------+-----------+------+-------------+
```

You can validate the environment is operational by logging into the storage nodes to validate the LVM targets are being created.

``` shell
root@openstack-node-4:~# lvs
  LV                                   VG               Attr       LSize Pool Origin Data%  Meta%  Move Log Cpy%Sync Convert
  c744af27-fb40-4ffa-8a84-b9f44cb19b2b cinder-volumes-1 -wi-a----- 1.00g
```

## LVM iSCSI and Multipath

!!! tip
    The use of iSCSI without multipath is discouraged and will lead to VMs having issues reaching attached storage during networking events.

!!! note
    This configuration will use two storage CIDRs, please make sure there are two network paths back to storage.

## Enable multipath in Nova Compute

Toggle volume_use_multipath to true in /etc/genestack/helm-configs/nova/nova-helm-overrides.yaml

``` shell
sed -i 's/volume_use_multipath: false/volume_use_multipath: true/' /etc/genestack/helm-configs/nova/nova-helm-overrides.yaml
sed -i 's/enable_iscsi: false/enable_iscsi: true/' /etc/genestack/helm-configs/nova/nova-helm-overrides.yaml
```

## Enable iSCSi and Multipath services on Compute Nodes

Add variable to your inventory file and re-run host-setup.yaml

``` yaml
storage:
  vars:
    enable_iscsi: true
```

## Enable iSCSI and Custom Mutlipath configuration

!!! note
    The included custom multipath config file uses queue-length and sends IO out all active paths when using iSCSI LVM, configure to your environment as you see fit.

Add variable to your inventory file, edit /opt/genestack/ansible/playbooks/templates/genestack-multipath.conf and re-run host-setup.yaml

``` yaml
storage:
  vars:
    enable_iscsi: true
    custom_multipath: true
```

## Enable iSCSI with LVM

There should be two networks defined on the openstack cluster: br_storage and br_storage_secondary

## Verify operations

Once a cinder volume is attach you should see on the LVM iSCSI node the following:

``` shell
root@genestack-storage1:~# tgtadm --mode target --op show
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

On Compute nodes using generic multipath configuration file.

``` shell

root@genestack-compute2:~# multipath -ll
mpathb (360000000000000000e00000000040001) dm-0 IET,VIRTUAL-DISK
size=20G features='0' hwhandler='0' wp=rw
|-+- policy='service-time 0' prio=1 status=active
| `- 2:0:0:1 sda 8:0  active ready running
`-+- policy='service-time 0' prio=1 status=enabled
  `- 4:0:0:1 sdb 8:16 active ready running
```

Using custom multipath configuration file

``` shell

root@genestack-compute1:~# multipath -ll
360000000000000000e00000000010001 dm-0 IET,VIRTUAL-DISK
size=10G features='0' hwhandler='0' wp=rw
`-+- policy='queue-length 0' prio=1 status=active
  |- 2:0:0:1 sda 8:0  active ready running
  `- 3:0:0:1 sdb 8:16 active ready running
```
