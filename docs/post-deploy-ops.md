After deploying the cloud operating environment, you're cloud will be ready to do work. While so what's next? Within this page we've a series of steps you can take to further build your cloud environment.

## Create an OpenStack Cloud Config

There are a lot of ways you can go to connect to your cluster. This example will use your cluster internals to generate a cloud config compatible with your environment using the Admin user.

### Create the needed directories

``` shell
mkdir -p ~/.config/openstack
```

### Generate the cloud config file

``` shell
cat >  ~/.config/openstack/clouds.yaml <<EOF
cache:
  auth: true
  expiration_time: 3600
clouds:
  default:
    auth:
      auth_url: $(kubectl --namespace openstack get secret keystone-keystone-admin -o jsonpath='{.data.OS_AUTH_URL}' | base64 -d)
      project_name: $(kubectl --namespace openstack get secret keystone-keystone-admin -o jsonpath='{.data.OS_PROJECT_NAME}' | base64 -d)
      tenant_name: $(kubectl --namespace openstack get secret keystone-keystone-admin -o jsonpath='{.data.OS_USER_DOMAIN_NAME}' | base64 -d)
      project_domain_name: $(kubectl --namespace openstack get secret keystone-keystone-admin -o jsonpath='{.data.OS_PROJECT_DOMAIN_NAME}' | base64 -d)
      username: $(kubectl --namespace openstack get secret keystone-keystone-admin -o jsonpath='{.data.OS_USERNAME}' | base64 -d)
      password: $(kubectl --namespace openstack get secret keystone-keystone-admin -o jsonpath='{.data.OS_PASSWORD}' | base64 -d)
      user_domain_name: $(kubectl --namespace openstack get secret keystone-keystone-admin -o jsonpath='{.data.OS_USER_DOMAIN_NAME}' | base64 -d)
    region_name: $(kubectl --namespace openstack get secret keystone-keystone-admin -o jsonpath='{.data.OS_REGION_NAME}' | base64 -d)
    interface: $(kubectl --namespace openstack get secret keystone-keystone-admin -o jsonpath='{.data.OS_INTERFACE}' | base64 -d)
    identity_api_version: "3"
EOF
```

## Setup the Keystone Federation Plugin

### Create the domain

``` shell
openstack --os-cloud default domain create rackspace_cloud_domain
```

### Create the identity provider

``` shell
openstack --os-cloud default identity provider create --remote-id rackspace --domain rackspace_cloud_domain rackspace
```

#### Create the mapping for our identity provider

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

> Save the mapping to a local file before uploading it to keystone. In the examples, the mapping is stored at `/tmp/mapping.json`.

Now register the mapping within Keystone.

``` shell
openstack --os-cloud default mapping create --rules /tmp/mapping.json rackspace_mapping
```

### Create the federation protocol

``` shell
openstack --os-cloud default federation protocol create rackspace --mapping rackspace_mapping --identity-provider rackspace
```

## Create Flavors

These are the default flavors expected in an OpenStack cloud. Customize these flavors based on your needs. See the upstream admin [docs](https://docs.openstack.org/nova/latest/admin/flavors.html) for more information on managing flavors.

``` shell
openstack --os-cloud default flavor create --public m1.extra_tiny --ram 512 --disk 0 --vcpus 1 --ephemeral 0 --swap 0
openstack --os-cloud default flavor create --public m1.tiny --ram 1024 --disk 10 --vcpus 1 --ephemeral 0 --swap 0
openstack --os-cloud default flavor create --public m1.small --ram 2048 --disk 20 --vcpus 2 --ephemeral 0 --swap 0
openstack --os-cloud default flavor create --public m1.medium --ram 4096 --disk 40 --vcpus 4 --ephemeral 8 --swap 2048
openstack --os-cloud default flavor create --public m1.large --ram 8192 --disk 80 --vcpus 6 --ephemeral 16 --swap 4096
openstack --os-cloud default flavor create --public m1.extra_large --ram 16384 --disk 160 --vcpus 8 --ephemeral 32 --swap 8192
```

## Download Images

### Get Ubuntu

#### Ubuntu 22.04 (Jammy)

``` shell
wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
openstack --os-cloud default image create \
          --progress \
          --disk-format qcow2 \
          --container-format bare \
          --public \
          --file jammy-server-cloudimg-amd64.img \
          --property hw_scsi_model=virtio-scsi \
          --property hw_disk_bus=scsi \
          --property hw_vif_multiqueue_enabled=true \
          --property hw_qemu_guest_agent=yes \
          --property hypervisor_type=kvm \
          --property img_config_drive=optional \
          --property hw_machine_type=q35 \
          --property hw_firmware_type=uefi \
          --property os_require_quiesce=yes \
          --property os_type=linux \
          --property os_admin_user=ubuntu \
          --property os_distro=ubuntu \
          --property os_version=22.04 \
          Ubuntu-22.04
```

#### Ubuntu 20.04 (Focal)

``` shell
wget https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img
openstack --os-cloud default image create \
          --progress \
          --disk-format qcow2 \
          --container-format bare \
          --public \
          --file focal-server-cloudimg-amd64.img \
          --property hw_scsi_model=virtio-scsi \
          --property hw_disk_bus=scsi \
          --property hw_vif_multiqueue_enabled=true \
          --property hw_qemu_guest_agent=yes \
          --property hypervisor_type=kvm \
          --property img_config_drive=optional \
          --property hw_machine_type=q35 \
          --property hw_firmware_type=uefi \
          --property os_require_quiesce=yes \
          --property os_type=linux \
          --property os_admin_user=ubuntu \
          --property os_distro=ubuntu \
          --property os_version=20.04 \
          Ubuntu-20.04
```

### Get Debian

#### Debian 12

``` shell
wget https://cloud.debian.org/cdimage/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2
openstack --os-cloud default image create \
          --progress \
          --disk-format qcow2 \
          --container-format bare \
          --public \
          --file debian-12-genericcloud-amd64.qcow2 \
          --property hw_scsi_model=virtio-scsi \
          --property hw_disk_bus=scsi \
          --property hw_vif_multiqueue_enabled=true \
          --property hw_qemu_guest_agent=yes \
          --property hypervisor_type=kvm \
          --property img_config_drive=optional \
          --property hw_machine_type=q35 \
          --property hw_firmware_type=uefi \
          --property os_require_quiesce=yes \
          --property os_type=linux \
          --property os_admin_user=debian \
          --property os_distro=debian \
          --property os_version=12 \
          Debian-12
```

#### Debian 11

``` shell
wget https://cloud.debian.org/cdimage/cloud/bullseye/latest/debian-11-genericcloud-amd64.qcow2
openstack --os-cloud default image create \
          --progress \
          --disk-format qcow2 \
          --container-format bare \
          --public \
          --file debian-11-genericcloud-amd64.qcow2 \
          --property hw_scsi_model=virtio-scsi \
          --property hw_disk_bus=scsi \
          --property hw_vif_multiqueue_enabled=true \
          --property hw_qemu_guest_agent=yes \
          --property hypervisor_type=kvm \
          --property img_config_drive=optional \
          --property hw_machine_type=q35 \
          --property hw_firmware_type=uefi \
          --property os_require_quiesce=yes \
          --property os_type=linux \
          --property os_admin_user=debian \
          --property os_distro=debian \
          --property os_version=11 \
          Debian-11
```

### Get CentOS

#### Centos Stream 9

``` shell
wget http://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2
openstack --os-cloud default image create \
          --progress \
          --disk-format qcow2 \
          --container-format bare \
          --public \
          --file CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2 \
          --property hw_scsi_model=virtio-scsi \
          --property hw_disk_bus=scsi \
          --property hw_vif_multiqueue_enabled=true \
          --property hw_qemu_guest_agent=yes \
          --property hypervisor_type=kvm \
          --property img_config_drive=optional \
          --property hw_machine_type=q35 \
          --property os_require_quiesce=yes \
          --property os_type=linux \
          --property os_admin_user=centos \
          --property os_distro=centos \
          --property os_version=9 \
          CentOS-Stream-9
```

#### Centos Stream 8

``` shell
wget http://cloud.centos.org/centos/8-stream/x86_64/images/CentOS-Stream-GenericCloud-8-latest.x86_64.qcow2
openstack --os-cloud default image create \
          --progress \
          --disk-format qcow2 \
          --container-format bare \
          --public \
          --file CentOS-Stream-GenericCloud-8-latest.x86_64.qcow2 \
          --property hw_scsi_model=virtio-scsi \
          --property hw_disk_bus=scsi \
          --property hw_vif_multiqueue_enabled=true \
          --property hw_qemu_guest_agent=yes \
          --property hypervisor_type=kvm \
          --property img_config_drive=optional \
          --property hw_machine_type=q35 \
          --property hw_firmware_type=uefi \
          --property os_require_quiesce=yes \
          --property os_type=linux \
          --property os_admin_user=centos \
          --property os_distro=centos \
          --property os_version=8 \
          CentOS-Stream-8
```

### Get openSUSE Leap

#### Leap 15

``` shell
wget https://download.opensuse.org/distribution/leap/15.5/appliances/openSUSE-Leap-15.5-Minimal-VM.x86_64-kvm-and-xen.qcow2
openstack --os-cloud default image create \
          --progress \
          --disk-format qcow2 \
          --container-format bare \
          --public \
          --file openSUSE-Leap-15.5-Minimal-VM.x86_64-kvm-and-xen.qcow2 \
          --property hw_scsi_model=virtio-scsi \
          --property hw_disk_bus=scsi \
          --property hw_vif_multiqueue_enabled=true \
          --property hw_qemu_guest_agent=yes \
          --property hypervisor_type=kvm \
          --property img_config_drive=optional \
          --property hw_machine_type=q35 \
          --property os_require_quiesce=yes \
          --property os_type=linux \
          --property os_admin_user=opensuse \
          --property os_distro=suse \
          --property os_version=15 \
          openSUSE-Leap-15
```
 
## Create Shared Provider Networks

The following commands are examples of creating several different network types.

### Flat Network

``` shell
openstack --os-cloud default network create --share \
                                            --availability-zone-hint nova \
                                            --external \
                                            --provider-network-type flat \
                                            --provider-physical-network physnet1 \
                                            flat
```

### Flat Subnet

``` shell
openstack --os-cloud default subnet create --subnet-range 172.16.24.0/22 \
                                           --gateway 172.16.24.2 \
                                           --dns-nameserver 172.16.24.2 \
                                           --allocation-pool start=172.16.25.150,end=172.16.25.200 \
                                           --dhcp \
                                           --network flat \
                                           flat_subnet
```

### VLAN Network

``` shell
openstack --os-cloud default network create --share \
                                            --availability-zone-hint nova \
                                            --external \
                                            --provider-segment 404 \
                                            --provider-network-type vlan \
                                            --provider-physical-network physnet1 \
                                            vlan404
```

### VLAN Subnet

``` shell
openstack --os-cloud default subnet create --subnet-range 10.10.10.0/23 \
                                           --gateway 10.10.10.1 \
                                           --dns-nameserver 10.10.10.1 \
                                           --allocation-pool start=10.10.11.10,end=10.10.11.254 \
                                           --dhcp \
                                           --network vlan404 \
                                           vlan404_subnet
```

### L3 (Tenant) Network

``` shell
openstack --os-cloud default network create l3
```

### L3 (Tenant) Subnet

``` shell
openstack --os-cloud default subnet create --subnet-range 10.0.10.0/24 \
                                           --gateway 10.0.10.1 \
                                           --dns-nameserver 1.1.1.1 \
                                           --allocation-pool start=10.0.10.2,end=10.0.10.254 \
                                           --dhcp \
                                           --network l3 \
                                           l3_subnet
```

> You can validate that the role has been assigned to the group and domain using the `openstack role assignment list`

# Third Party Integration

## OSIE Deployment

``` shell
helm upgrade --install osie osie/osie \
             --namespace=osie \
             --create-namespace \
             --wait \
             --timeout 120m \
             -f /opt/genestack/helm-configs/osie/osie-helm-overrides.yaml
```

# Connect to the database

Sometimes an operator may need to connect to the database to troubleshoot things or otherwise make modifications to the databases in place. The following command can be used to connect to the database from a node within the cluster.

``` shell
mysql -h $(kubectl -n openstack get service mariadb-galera-primary -o jsonpath='{.spec.clusterIP}') \
      -p$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d) \
      -u root
```

> The following command will leverage your kube configuration and dynamically source the needed information to connect to the MySQL cluster. You will need to ensure you have installed the mysql client tools on the system you're attempting to connect from.
