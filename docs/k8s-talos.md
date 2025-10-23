# Deployment Talos Linux

## Minimum system requirements

You will need a minimum of 2 Network Interfaces

!!! tip

    While we would expect the environment to be running with multiple bonds in a production cloud, two network interfaces is all that's required. This can be achieved with vlan
    tagged devices, physical ethernet devices, macvlan, or anything else. Have a look at the netplan example file found
    [here](https://github.com/rackerlabs/genestack/blob/main/etc/netplan/default.yaml) for an example of how you could setup the network.

!!! note

    You will also want to update the /etc/genestack/helm-chart-versions.yaml file. You will want to set the kube-ovn version to:
    kube-ovn: v1.14.10

## Kernel modules

Talos boot image by default comes with very little. A typical install of Genestack will use Longhorn as the persistent storage backend. In order to use longhorn you will need the following extra packages

* siderolabs/iscsi-tools
* siderolabs/util-linux-tools

A bootable image with the extra packages installed can be found here: [Talos Linux Image Factory](https://factory.talos.dev/)

* Download The Talos Linux Image
* Boot Your Machines
* Install talosctl

``` shell
curl -sL <https://talos.dev/install> | sh
```

* Generate cluster configs

Run this command to generate the configuration file

``` shell
talosctl gen config $CLUSTER_NAME https://$CONTROL_PLANE_IP:6443 --install-disk /dev/$DISK_NAME
```

## Apply Configurations

Now that you’ve created your configurations, it’s time to apply them to bring your nodes and cluster online.

Run this command to apply the control plane configuration:

``` shell
talosctl apply-config --insecure --nodes $CONTROL_PLANE_IP --file controlplane.yaml
```

Next, apply the worker node configuration

``` shell
for ip in "${WORKER_IP[@]}"; do
    echo "Applying config to worker node: $ip"
    talosctl apply-config --insecure --nodes "$ip" --file worker.yaml
done
```

## Set your endpoints

Set your endpoints with this

``` shell
talosctl --talosconfig=./talosconfig config endpoints $CONTROL_PLANE_IP
```

## Bootstrap Your Etcd Cluster

Wait for your control plane node to finish booting, then bootstrap your etcd cluster by running.

``` shell
talosctl bootstrap --nodes $CONTROL_PLANE_IP --talosconfig=./talosconfig
```

!!! note

    Run this command ONCE on a SINGLE control plane node. If you have multiple control plane nodes, you can choose any of them.
​

## Get Kubernetes Access

Download your kubeconfig file to start using kubectl. You have two download options: you can either merge your Kubernetes configurations OR keep them separate. Here’s how to do both:

Merge your new cluster into your local Kubernetes configuration

``` shell
talosctl kubeconfig --nodes $CONTROL_PLANE_IP --talosconfig=./talosconfig
```

Specify a filename if you prefer not to merge with your default Kubernetes configuration

``` shell
talosctl kubeconfig alternative-kubeconfig --nodes $CONTROL_PLANE_IP --talosconfig=./talosconfig
export KUBECONFIG=./alternative-kubeconfig
```

!!! tip

    You will need to keep in mind that kubespray installs cert-manager as part of its installation process.
    So you will need to install it manually. Here is a helm chart that will provide it for you:
    https://github.com/cert-manager/cert-manager
