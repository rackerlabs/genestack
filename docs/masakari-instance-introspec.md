# Instance & Intropsection Monitor

## Instance Monitor (Basic)

Acts as a basic self heal if in case the Virtualization Engine, this being KVM/Libvirt process suddenly dies without prior initiation by NOVA api.
There is no need of action by the user, the masakari instance service will automatically kick in and attempt a HARD reboot of the VM to restart its respective KMV process on the hypervisor.

## Introspection Monitor

Detection VM system-level failure events via QEMU Guest Agent. If the hypervisor libvirt service detects VM heartbeat failures, it will send a notification to the Masakari API, once the configured check timeout has been reached. Masakari will initiate a recovery workflow to hard power-off the instance, then start the instance via NOVA API calls.

## Enable in Genestack

Add into /etc/genestack/helm-configs/masakari/masakari-helm-overrides.yaml

```bash
conf:
  masakarimonitors:
    libvirt:
      connection_uri: qemu:///system
    introspectiveinstancemonitor:
      guest_monitor_interval: 10
      guest_monitor_timeout: 5
      # add this explicitly if your environment needs it
      qemu_guest_agent_sock_path: /var/lib/libvirt/qemu/org\.qemu\.guest_agent\..*\.instance-.*\.sock
```

**NOTE** There are a few assumptions before Instrospection can work as intended.

* Tunings will be required to allow this operation to be optimal for a production use case, this includes intropspection config adjustments for sample rates and timeout values to allow masakri to determine if a VM is actually lost connectivity or having a lockup issue.

Glance Image property:

```bash
openstack image set --property hw_qemu_guest_agent=yes <image_name_or_uuid>
```
During VM boot please add the following metadata property either at boot or post boot

```bash
openstack server set --property HA_Enabled=True <server_id_or_name>
```

## Install QEMU Guest Agent on Running Linux & Windows VMs

Debian
```bash
sudo apt install -y qemu-guest-agent
```

RHEL / CentOS / Rocky / AlmaLinux
```bash
sudo dnf install -y qemu-guest-agent
```

## Build images

LINUX (Please follow your respective distro guides on how to build images with QEMU Guest Agent)

WINDOWS IMAGE BUILD: https://pve.proxmox.com/wiki/Qemu-guest-agent
