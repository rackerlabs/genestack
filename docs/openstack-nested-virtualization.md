# Nested Virtualization

Genestack now enables the libvirt chart's `conf.init_modules` workflow by
default in the base libvirt overrides. On supported compute hosts, this writes
the host modprobe configuration for `kvm_intel` or `kvm_amd` and reloads the
KVM module with nested virtualization enabled.

This change prepares compute nodes to run guest workloads that need access to
hardware virtualization extensions, such as nested KVM inside an instance.

## What Changed

The libvirt `libvirt-init-modules` init container now runs by default as part of
the libvirt DaemonSet. During startup it:

1. Checks whether the compute host supports Intel `vmx` or AMD `svm`.
1. Writes `/etc/modprobe.d/qemu-system-x86.conf` on the compute host when
   needed.
1. Reloads the relevant KVM kernel module with nested virtualization enabled.

On Intel systems, the resulting host configuration typically looks like:

``` shell
options kvm_intel nested=1
options kvm_intel enable_apicv=1
options kvm_intel ept=1
```

On AMD systems, the configuration typically looks like:

``` shell
options kvm_amd nested=1
```

## What This Enables

With this change in place, compute hosts can expose nested virtualization
capability to instances when all of the following are true:

1. The CPU supports nested virtualization.
1. The host KVM module is loaded with nested mode enabled.
1. Nova/libvirt is configured to expose virtualization extensions to the guest
   CPU definition.

This host-side change enables the first two conditions. Guest workloads will
still need Nova/libvirt CPU settings that pass through the required `vmx` or
`svm` flags to the instance.

## Validation

Validate nested virtualization on the compute host:

``` shell
cat /sys/module/kvm_intel/parameters/nested
```

or on AMD:

``` shell
cat /sys/module/kvm_amd/parameters/nested
```

Expected output is `Y` or `1` depending on the platform and kernel.

Validate that the host configuration file exists:

``` shell
ls -l /etc/modprobe.d/qemu-system-x86.conf
cat /etc/modprobe.d/qemu-system-x86.conf
```

Validate that a guest sees virtualization extensions:

``` shell
egrep '(vmx|svm)' /proc/cpuinfo
```

If the host reports nested KVM as enabled but the guest does not see `vmx` or
`svm`, review Nova/libvirt CPU mode and model configuration for that workload.
