# Deployment Talos Linux





#### Minimum system requirements

* 2 Network Interfaces

!!! note

    While we would expect the environment to be running with multiple bonds in a production cloud, two network interfaces is all that's required. This can be achieved with vlan
    tagged devices, physical ethernet devices, macvlan, or anything else. Have a look at the netplan example file found
    [here](https://github.com/rackerlabs/genestack/blob/main/etc/netplan/default.yaml) for an example of how you could setup the network.



* Kernel modules


Talos boot image by default comes with very little. A typical install of Genestack will use Longhorn as the persistent storage backend. In order to use longhorn you will need the following extra packages

* siderolabs/iscsi-tools
* siderolabs/util-linux-tools

A bootable image with the extra packages installed can be found here: [Talos Linux Image Factory](https://factory.talos.dev/)

* Download The Talos Linux Image
* Boot Your Machines
* Install talosctl
 curl -sL https://talos.dev/install | sh
*  Generate cluster configs


Run this command to generate the configuration file:

    talosctl gen config $CLUSTER_NAME https://$CONTROL_PLANE_IP:6443 --install-disk /dev/$DISK_NAME
​
​* Apply Configurations
Now that you’ve created your configurations, it’s time to apply them to bring your nodes and cluster online:

    Run this command to apply the control plane configuration:

talosctl apply-config --insecure --nodes $CONTROL_PLANE_IP --file controlplane.yaml

Next, apply the worker node configuration:

    for ip in "${WORKER_IP[@]}"; do
        echo "Applying config to worker node: $ip"
        talosctl apply-config --insecure --nodes "$ip" --file worker.yaml
    done

​
* Set your endpoints
Set your endpoints with this:

talosctl --talosconfig=./talosconfig config endpoints $CONTROL_PLANE_IP

​
* Bootstrap Your Etcd Cluster
Wait for your control plane node to finish booting, then bootstrap your etcd cluster by running:

talosctl bootstrap --nodes $CONTROL_PLANE_IP --talosconfig=./talosconfig

Note: Run this command ONCE on a SINGLE control plane node. If you have multiple control plane nodes, you can choose any of them.
​
* Get Kubernetes Access
Download your kubeconfig file to start using kubectl. You have two download options: you can either merge your Kubernetes configurations OR keep them separate. Here’s how to do both:

    Merge your new cluster into your local Kubernetes configuration:

talosctl kubeconfig --nodes $CONTROL_PLANE_IP --talosconfig=./talosconfig

    Specify a filename if you prefer not to merge with your default Kubernetes configuration:

talosctl kubeconfig alternative-kubeconfig --nodes $CONTROL_PLANE_IP --talosconfig=./talosconfig
export KUBECONFIG=./alternative-kubeconfig

