# Configuring PCI Passthrough in OpenStack

PCI Passthrough in OpenStack allows you to assign physical PCI devices directly to virtual machine instances, enabling high-performance access to hardware resources such as GPUs and network cards. This guide walks you through the basic steps to configure PCI Passthrough.

## Enable IOMMU on Compute Nodes

An Input-Output Memory Management Unit (IOMMU) is essential in computing for connecting a Direct Memory Access (DMA)-capable I/O bus to the main memory. Like a traditional Memory Management Unit (MMU), which translates CPU-visible virtual addresses to physical addresses, the IOMMU maps device-visible virtual addresses (also called device addresses or memory-mapped I/O addresses) to physical addresses. Additionally, IOMMUs provide memory protection, preventing issues caused by faulty or malicious devices. This functionality is critical for enabling secure and efficient PCI Passthrough in OpenStack environments.

### For Intel CPUs

1. Edit the GRUB configuration file:

``` shell
sudo vi /etc/default/grub
```

2. Add `intel_iommu=on` to the `GRUB_CMDLINE_LINUX_DEFAULT` line:

``` shell
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash intel_iommu=on"
```

### For AMD CPUs

1. Edit the GRUB configuration file:

``` shell
sudo vi /etc/default/grub
```

2. Add `amd_iommu=on` to the `GRUB_CMDLINE_LINUX_DEFAULT` line:

``` shell
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash amd_iommu=on"
```

## Identify PCI Devices

Identify the PCI devices you want to passthrough using the `lspci` command:

``` shell
lspci -knn | grep NVIDIA
```

!!! example "lspci output"

    ``` shell
    0b:00.0 VGA compatible controller [0300]: NVIDIA Corporation GP106GL [Quadro P2000] [10de:1c30] (rev a1)
    0b:00.1 Audio device [0403]: NVIDIA Corporation GP106 High Definition Audio Controller [10de:10f1] (rev a1)
    ```

From the example output, we can see that we have two devices that we'll want to be able to pass through to our instances; we'll need to note `10de:1c30` and `10de:10f1` for use in the host configuration.

### Add VFIO Configuration


1. Edit the GRUB configuration file:

``` shell
sudo vi /etc/default/grub
```

2. Modify the `GRUB_CMDLINE_LINUX_DEFAULT` once again, extending it for `vfio-pci.ids`.

``` shell
GRUB_CMDLINE_LINUX_DEFAULT="... vfio-pci.ids=10de:1c30,10de:10f1"
```

!!! note

    The value of `vfio-pci.ids` is the same as the noted from the *lspci output*.


### Update GRUB and reboot

``` shell
sudo update-grub
sudo reboot
```

## Validate the setup

Once the node has been rebooted, check the `lspci` output to ensure that the device being used as passthrough is using the `vfio-pci` driver.

Re-identify the PCI devices you want to passthrough using the `lspci` command

``` shell
lspci -knn | grep NVIDIA
```

!!! example "lspci output"

    ``` shell
    ...
    0b:00.0 VGA compatible controller: NVIDIA Corporation GP106GL [Quadro P2000] (rev a1)
            Subsystem: Dell GP106GL [Quadro P2000]
            Kernel driver in use: vfio-pci
            Kernel modules: nouveau
    0b:00.1 Audio device: NVIDIA Corporation GP106 High Definition Audio Controller (rev a1)
            Subsystem: Dell GP106 High Definition Audio Controller
            Kernel driver in use: vfio-pci
            Kernel modules: snd_hda_intel
    ...
    ```

Note the "Kernel driver in use: vfio-pci" section. If the kernel driver is anything other than `vfio-pci` you many need to blacklist the referenced driver before you continue. See the following docs on how to [blacklist a kernel module](https://wiki.debian.org/KernelModuleBlacklisting).

!!! tip
        You can verify that IOMMU is loaded once the server is rebooted by running:

        sudo dmesg | grep -e IOMMU


!!! example "example config that uses iommu and also disables nvidia modules in favor of vfio"

    ``` shell
    GRUB_CMDLINE_LINUX_DEFAULT="quiet splash intel_iommu=on iommu=pt mitigations=off vfio-pci.ids=10de:1b38 vfio_iommu_type1.allow_unsafe_interrupts=1 modprobe.blacklist=nvidiafb,nouveau,nvidia,nvidia_drm rs.driver.blacklist=nouveau,nvidia,nvidia_drm,nvidiafb kvm.ignore_msrs=1"
    ```

## Configure Nova Compute

With the same `lspci` information used in the `vfio` setup, create a `device_spec` and `alias` in JSON string format. The `device_spec` needs the **vendor_id** and **product_id** which are within our known PCI information. For `10de:1c30` and `10de:10f1`, the left side of the `:` is the **vendor_id** and the right side is the **product_id**.

| vendor_id | product_id |
| --------- | ---------- |
|   10de    |    1c30    |
|   10de    |    10f1    |

### Example `device_spec`

``` json
{"vendor_id": "10de", "product_id": "1c30"}
```

### Example `alias`

``` json
{"vendor_id": "10de", "product_id": "1c30", "device_type": "type-PCI", "name": "p2000"}
```

If you are configuring a PCI passthrough for say a GPU compute follow the instruction in the Node Overrides Explanation section of the service override documentation.

1. See the [Genestack service override documentation](openstack-service-overrides.md) on how update your compute infrastructure to use the `device_spec` and `alias`.

1. Create a custom flavor which has your alias name as a property. See the [Genestack flavor documentation](openstack-flavors.md) on how to craft custom flavors.

## Launch an Instance with PCI Passthrough

1. Verify that the instance has the PCI device assigned. SSH into the instance and use the `lspci` command:

``` shell
lspci | grep -i nvidia
```

!!! example "lspci output"

    ``` shell
    06:00.0 VGA compatible controller: NVIDIA Corporation GP106GL [Quadro P2000] (rev a1)
    ```

Assuming this is running an NVIDIA GPU, you can run install the relevant drivers and run the `nvidia-smi` command to validate everything is running normally.

!!! example "Example nvidia GPU running in a VM"

    ``` shell
    +-----------------------------------------------------------------------------+
    | NVIDIA-SMI 525.147.05   Driver Version: 525.147.05   CUDA Version: 12.0     |
    |-------------------------------+----------------------+----------------------+
    | GPU  Name        Persistence-M| Bus-Id        Disp.A | Volatile Uncorr. ECC |
    | Fan  Temp  Perf  Pwr:Usage/Cap|         Memory-Usage | GPU-Util  Compute M. |
    |                               |                      |               MIG M. |
    |===============================+======================+======================|
    |   0  Quadro P2000        On   | 00000000:06:00.0 Off |                  N/A |
    | 50%   40C    P8     6W /  75W |      1MiB /  5120MiB |      0%      Default |
    |                               |                      |                  N/A |
    +-------------------------------+----------------------+----------------------+

    +-----------------------------------------------------------------------------+
    | Processes:                                                                  |
    |  GPU   GI   CI        PID   Type   Process name                  GPU Memory |
    |        ID   ID                                                   Usage      |
    |=============================================================================|
    |  No running processes found                                                 |
    +-----------------------------------------------------------------------------+
    ```

## Common Issues

- **Device Not Found:** Ensure the PCI device is available and not used by the host.
- **Configuration Errors:** Check `nova-compute` logs.
- **IOMMU Not Enabled:** Confirm that IOMMU is enabled in the BIOS/UEFI and in the GRUB configuration.
- **Scheduler Error:** Example errors like `Dropped device(s) due to mismatched PCI attribute(s)` or `allocation_candidate: doesn't have the required PCI devices` This and scheduler removing all compute nodes during pci filter is a sign that your **device_type** attribute on nova.conf does not correctly match the PCI device installed on the sytem.

!!! tip
	The device_type attribute must match one of type-PCI, type-PF or type-VF. If you have a SR-IOV capable device, you must set your device_type to type-PF even if you do not use the SR-IOV functionality.

## Conclusion

Configuring PCI Passthrough in OpenStack enhances the performance of virtual machines by providing direct access to physical hardware. This guide is aimed to be helpful on getting up and running with PCI Passthrough but it is by no means exhaustive, refer to the [OpenStack documentation](https://docs.openstack.org/nova/latest/admin/pci-passthrough.html) for more.
