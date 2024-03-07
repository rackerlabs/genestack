
# Download Images

## Get Ubuntu

### Ubuntu 22.04 (Jammy)

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

### Ubuntu 20.04 (Focal)

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

## Get Debian

### Debian 12

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

### Debian 11

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

## Get CentOS

### Centos Stream 9

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

### Centos Stream 8

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

## Get openSUSE Leap

### Leap 15

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
 
