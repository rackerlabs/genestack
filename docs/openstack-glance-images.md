# Glance Images Overview

The following page highlights how to retrieve various images and upload them into Glance.

## Image Properties Breakdown

Throughout the various examples you'll notice the images have a number of properties defined.
All of these properties enhance the user experience and usability of the images being provided
in these examples.

The properties of note are the following.

| Property                                                                                                 | Value  | Notes                |
|----------------------------------------------------------------------------------------------------------|--------|----------------------|
| [hw_scsi_model](https://docs.openstack.org/glance/latest/admin/useful-image-properties.html)             | STRING | Needed for multipath |
| [hw_disk_bus](https://docs.openstack.org/glance/latest/admin/useful-image-properties.html)               | STRING | Needed for multipath |
| [hw_vif_multiqueue_enabled](https://docs.openstack.org/glance/latest/admin/useful-image-properties.html) | BOOL   |
| [hw_qemu_guest_agent](https://docs.openstack.org/glance/latest/admin/useful-image-properties.html)       | BOOL   |
| [hw_machine_type](https://docs.openstack.org/glance/latest/admin/useful-image-properties.html)           | STRING |
| [hw_firmware_type](https://docs.openstack.org/glance/latest/admin/useful-image-properties.html)          | STRING |
| [os_require_quiesce](https://docs.openstack.org/glance/latest/admin/useful-image-properties.html)        | BOOL   |
| [os_type](https://docs.openstack.org/openstacksdk/latest/user/resources/image/v2/image.html)             | STRING |
| [os_admin_user](https://docs.openstack.org/openstacksdk/latest/user/resources/image/v2/image.html)       | STRING | [See Default Usernames for Images](#default-usernames-for-images) |
| [os_distro](https://docs.openstack.org/openstacksdk/latest/user/resources/image/v2/image.html)           | STRING |
| [os_version](https://docs.openstack.org/openstacksdk/latest/user/resources/image/v2/image.html)          | STRING |

### Default Usernames for Images

All of the images that Rackspace provides have properties that define the default username for the image. This property can be seen discovered using the `openstack image show` command and referencing the `os_admin_user` property.

``` shell
openstack --os-cloud default image show Ubuntu-22.04 -f json
```

!!! example "Output in JSON format"

    ``` json
    {
        "checksum": "84e36c4cc4182757b34d2dc578708f7c",
        "container_format": "bare",
        "created_at": "2024-06-21T17:02:35Z",
        "disk_format": "qcow2",
        "file": "/v2/images/5cdcb4a2-0fa9-4af0-ad90-85e70bf38c0c/file",
        "id": "5cdcb4a2-0fa9-4af0-ad90-85e70bf38c0c",
        "min_disk": 0,
        "min_ram": 0,
        "name": "Ubuntu-20.04",
        "owner": "8fb86e74be8d49f3befde1f647d9f2ef",
        "properties": {
            "os_hidden": false,
            "os_hash_algo": "sha512",
            "os_hash_value": "2e3417e9d63a40b8521a1dceb52cdffcbe6f5f738e0027193b7863f4b3de09ccf7bc78f000de4dbe4f91a867d0c4a75dc19c78960cc0d715fe575336fb297f01",
            "hw_firmware_type": "uefi",
            "owner_specified.openstack.md5": "",
            "owner_specified.openstack.sha256": "",
            "owner_specified.openstack.object": "images/Ubuntu-20.04",
            "hypervisor_type": "kvm",
            "img_config_drive": "optional",
            "os_distro": "ubuntu",
            "os_version": "20.04",
            "hw_machine_type": "q35",
            "hw_vif_multiqueue_enabled": true,
            "os_type": "linux",
            "os_admin_user": "ubuntu",
            "hw_qemu_guest_agent": "yes",
            "os_require_quiesce": true
        },
        "protected": false,
        "schema": "/v2/schemas/image",
        "size": 625475584,
        "status": "active",
        "tags": [],
        "updated_at": "2024-09-24T22:31:37Z",
        "virtual_size": 2361393152,
        "visibility": "public"
    }
    ```

Using this value operators can easily determine the default username for the image.

## Get Ubuntu

### Ubuntu 24.04 (Noble)

``` shell
wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
openstack --os-cloud default image create \
          --progress \
          --disk-format qcow2 \
          --container-format bare \
          --public \
          --file noble-server-cloudimg-amd64.img \
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
          --property os_version=24.04 \
          Ubuntu-24.04
```

### Ubuntu 22.04 (Jammy)

``` shell
wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
openstack --os-cloud default image create \
          --progress \
          --disk-format qcow2 \
          --container-format bare \
          --public \
          --file jammy-server-cloudimg-amd64.img \
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

## Get Fedora CoreOS

### CoreOS 40

!!! note

    Make sure you get the most up to date image URL from the [upstream documentation](https://fedoraproject.org/coreos/download).

Download the image.

``` shell
# NOTE: CoreOS provides a compressed image.
wget https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/40.20240616.3.0/x86_64/fedora-coreos-40.20240616.3.0-openstack.x86_64.qcow2.xz
xz -d fedora-coreos-40.20240616.3.0-openstack.x86_64.qcow2.xz
```

Upload the image to glance.

``` shell
openstack --os-cloud default image create \
          --progress \
          --disk-format qcow2 \
          --container-format bare \
          --public \
          --file fedora-coreos-40.20240616.3.0-openstack.x86_64.qcow2 \
          --property hw_vif_multiqueue_enabled=true \
          --property hw_qemu_guest_agent=yes \
          --property hypervisor_type=kvm \
          --property img_config_drive=optional \
          --property hw_machine_type=q35 \
          --property hw_firmware_type=uefi \
          --property os_require_quiesce=yes \
          --property os_type=linux \
          --property os_admin_user=coreos \
          --property os_distro=coreos \
          --property os_version=40 \
          fedora-coreos-40
```

#### Fedora CoreOS Image Required by Magnum

!!! note

    When configuring the ClusterTemplate, you must specify the image used to boot the servers. To do this, register the image with OpenStack Glance and ensure that the os_distro property is set to fedora-coreos. The os_distro attribute must be defined and accurately reflect the distribution used by the cluster driver. This parameter is mandatory and does not have a default value, so it must be specified explicitly. Note that the os_distro attribute is case-sensitive. Currently, only Fedora CoreOS is supported. For more detailed information, refer to the [upstream magnum documentation](https://docs.openstack.org/magnum/latest/user/index.html).

``` shell
openstack --os-cloud default image create \
          --progress \
          --disk-format qcow2 \
          --container-format bare \
          --public \
          --file fedora-coreos-40.20240616.3.0-openstack.x86_64.qcow2 \
          --property hw_vif_multiqueue_enabled=true \
          --property hw_qemu_guest_agent=yes \
          --property hypervisor_type=kvm \
          --property img_config_drive=optional \
          --property hw_machine_type=q35 \
          --property hw_firmware_type=uefi \
          --property os_require_quiesce=yes \
          --property os_type=linux \
          --property os_admin_user=coreos \
          --property os_distro=fedora-coreos \
          --property os_version=40 \
          magnum-fedora-coreos-40
```

## Get openSUSE Leap

### Leap 15

``` shell
wget https://download.opensuse.org/repositories/Cloud:/Images:/Leap_15.2/images/openSUSE-Leap-15.2-OpenStack.x86_64-0.0.4-Build8.25.qcow2
openstack --os-cloud default image create \
          --progress \
          --disk-format qcow2 \
          --container-format bare \
          --public \
          --file openSUSE-Leap-15.2-OpenStack.x86_64-0.0.4-Build8.25.qcow2 \
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

## Get SUSE

!!! note

    Make sure you get the most up to date image from [here](https://www.suse.com/download/sles/). We downloaded the SLES15-SP6-Minimal-VM.x86_64-kvm-and-xen-QU1.qcow2 image.

``` shell
openstack --os-cloud default image create \
          --progress \
          --disk-format qcow2 \
          --container-format bare \
          --public \
          --file SLES15-SP6-Minimal-VM.x86_64-kvm-and-xen-QU1.qcow2 \
          --property hw_vif_multiqueue_enabled=true \
          --property hw_qemu_guest_agent=yes \
          --property hypervisor_type=kvm \
          --property img_config_drive=optional \
          --property hw_machine_type=q35 \
          --property hw_firmware_type=uefi \
          --property os_require_quiesce=yes \
          --property os_type=linux \
          --property os_admin_user=sles \
          --property os_distro=sles \
          --property os_version=15-SP6 \
          SLES15-SP6
```

## Get RHEL

!!! note

    Make sure you download the latest available image from [here](https://access.redhat.com/downloads/content/479/ver=/rhel---9/9.4/x86_64/product-software). We used the rhel-9.4-x86_64-kvm.qcow2 image.

``` shell
openstack --os-cloud default image create \
          --progress \
          --disk-format qcow2 \
          --container-format bare \
          --public \
          --file rhel-9.4-x86_64-kvm.qcow2 \
          --property hw_vif_multiqueue_enabled=true \
          --property hw_qemu_guest_agent=yes \
          --property hypervisor_type=kvm \
          --property img_config_drive=optional \
          --property hw_machine_type=q35 \
          --property hw_firmware_type=uefi \
          --property os_require_quiesce=yes \
          --property os_type=linux \
          --property os_admin_user=cloud-user \
          --property os_distro=rhel \
          --property os_version=9.4 \
          RHEL-9.4
```

## Get Windows

!!! note

    You will need to create a virtual disk image from your own licensed media and convert to .qcow2 format.  This example uses a Windows 2022 Standard Edition installation generalized with cloud-init and sysprep, then converted the image to .qcow2 format using qemu-img.  For additional information on creating a Windows image, please see the [upstream documentation](https://docs.openstack.org/image-guide/create-images-manually-example-windows-image.html).

``` shell
openstack --os-cloud default image create \
          --progress \
          --disk-format qcow2 \
          --min-disk 50 \
          --min-ram 2048 \
          --container-format bare \
          --file Windows2022StdEd.qcow2 \
          --public \
          --property hypervisor_type=kvm \
          --property os_type=windows \
          --property os_admin_user=administrator \
          --property os_distro=windows \
          --property os_version=2022 \
          Windows-2022-Standard
```
