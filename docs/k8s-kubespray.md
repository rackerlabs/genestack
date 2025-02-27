# Deployment Kubespray

Currently only the k8s provider kubespray is supported and included as submodule into the code base.

### Before you Deploy

Kubespray will be using OVN for all of the network functions, as such, you will need to ensure your hosts are ready to receive the deployment at a low level.
While the Kubespray tooling will do a lot of prep and setup work to ensure success,
you will need to prepare your networking infrastructure and basic storage layout before running the playbooks.

#### Minimum system requirements

* 2 Network Interfaces

!!! note

    While we would expect the environment to be running with multiple bonds in a production cloud, two network interfaces is all that's required. This can be achieved with vlan
    tagged devices, physical ethernet devices, macvlan, or anything else. Have a look at the netplan example file found
    [here](https://github.com/rackerlabs/genestack/blob/main/etc/netplan/default-DHCP.yaml) for an example of how you could setup the network.

* Ensure we're running kernel 5.17+

!!! tip

    While the default kernel on most modern operating systems will work, we recommend running with Kernel 6.2+.

* Kernel modules

!!! warning

    The Kubespray tool chain will attempt to deploy a lot of things, one thing is a set of `sysctl` options which will include bridge tunings. Given the tooling will assume bridging is functional, you will need to ensure the `br_netfilter` module is loaded or you're using a kernel that includes that functionality as a built-in.

* Executable `/tmp`

!!! warning

    The `/tmp` directory is used as a download and staging location within the environment. You will need to make sure that the `/tmp` is executable. By default, some kick-systems set the mount option **noexec**, if that is defined you should remove it before running the deployment.

### Create your Inventory

A default inventory file for kubespray is provided at `/etc/genestack/inventory` and must be modified.

Checkout the [inventory.yaml.example](https://github.com/rackerlabs/genestack/blob/main/ansible/inventory/genestack/inventory.yaml.example) file for an example of a target environment.

!!! note

    Before you deploy the kubernetes cluster you should define the `kube_override_hostname` option in your inventory. This variable will set the node name which we will want to be an FQDN. When you define the option, it should have the same suffix defined in our `cluster_name` variable.

However, any Kubespray compatible inventory will work with this deployment tooling. The official [Kubespray documentation](https://kubespray.io) can be used to better understand the inventory options and requirements.

### Ensure systems have a proper FQDN Hostname

Before running the Kubernetes deployment, make sure that all hosts have a properly configured FQDN.

``` shell
source /opt/genestack/scripts/genestack.rc
ansible -m shell -a 'hostnamectl set-hostname {{ inventory_hostname }}' --become all
ansible -m shell -a "grep 127.0.0.1 /etc/hosts | grep -q {{ inventory_hostname }} || sed -i 's/^127.0.0.1.*/127.0.0.1 {{ inventory_hostname }} localhost.localdomain localhost/' /etc/hosts" --become all
```

!!! note

    In the above command I'm assuming the use of `cluster.local` this is the default **cluster_name** as defined in the group_vars k8s_cluster file. If you change that option, make sure to reset your domain name on your hosts accordingly.


The ansible inventory is expected at `/etc/genestack/inventory` and automatically loaded once `genestack.rc` is sourced.

### Prepare hosts for installation

The `host-setup.yml` playbook draws some values from `group_vars`. Before running the `host-setup.yml` playbook, take a look at default values
provided in `/etc/genestack/inventory/group_vars/all/all.yml` to ensure they are properly defined for your environment. Values can be set as
`host_vars` if appropriate. Then, run the following:

``` shell
source /opt/genestack/scripts/genestack.rc
cd /opt/genestack/ansible/playbooks
```

!!! note

    The rc file sets a number of environment variables that help ansible to run in a more easily to understand way.

While the `ansible-playbook` command should work as-is with the sourced environment variables, sometimes it's necessary to set some overrides on the command line.
The following example highlights a couple of overrides that are generally useful.

#### Example host setup playbook

``` shell
ansible-playbook host-setup.yml
```

#### Example host setup playbook with overrides

Confirm `inventory.yaml` matches what is in `/etc/genestack/inventory`. If it does not match update the command to match the file names.

``` shell
source /opt/genestack/scripts/genestack.rc
# Example overriding things on the CLI
ansible-playbook host-setup.yml
```

!!! note
    The RC file sets a number of environment variables that help ansible to run in a more easy to understand way.

### Run the cluster deployment

=== "Kubespray Direct _(Recommended)_"

    This is used to deploy kubespray against infra on an OpenStack cloud. If you're deploying on baremetal you will need to setup an inventory that meets your environmental needs.
    Change the directory to the kubespray submodule.

    The cluster deployment playbook can also have overrides defined to augment how the playbook is executed.
    Confirm openstack-flex-inventory.yaml matches what is in /etc/genestack/inventory. If it does not match update the command to match the file names.

    ``` shell
    cd /opt/genestack/submodules/kubespray
    ansible-playbook cluster.yml --become
    ```

!!! tip

    Given the use of a venv, when running with `sudo` be sure to use the full path and pass through your environment variables; `sudo -E /home/ubuntu/.venvs/genestack/bin/ansible-playbook`.

Once the cluster is online, you can run `kubectl` to interact with the environment.
