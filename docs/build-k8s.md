# Kubernetes Deployment Demo

[![asciicast](https://asciinema.org/a/629780.svg)](https://asciinema.org/a/629780)

# Run The Genestack Kubernetes Deployment

Genestack assumes Kubernetes is present and available to run workloads on. We don't really care how your Kubernetes was deployed or what flavor of Kubernetes you're running.
For our purposes we're using Kubespray, but you do you. We just need the following systems in your environment.

* Kube-OVN
* Persistent Storage
* MetalLB
* Ingress Controller

If you have those three things in your environment, you should be fully compatible with Genestack.

## Deployment Kubespray

Currently only the k8s provider kubespray is supported and included as submodule into the code base.

> Existing OpenStack Ansible inventory can be converted using the `/opt/genestack/scripts/convert_osa_inventory.py`
  script which provides a `hosts.yml`

### Before you Deploy

Kubespray will be using OVN for all of the network functions, as such, you will need to ensure your hosts are ready to receive the deployment at a low level.
While the Kubespray tooling will do a lot of prep and setup work to ensure success,
you will need to prepare your networking infrastructure and basic storage layout before running the playbooks.

### SSH Config

The deploy has created a openstack-flex-keypair.config copy this into the config file in .ssh, if one is not there create it.

#### Minimum system requirements

* 2 Network Interfaces

> While we would expect the environment to be running with multiple bonds in a production cloud, two network interfaces is all that's required.
> This can be achieved with vlan tagged devices, physical ethernet devices, macvlan, or anything else.
> Have a look at the netplan example file found [here](https://github.com/rackerlabs/genestack/blob/main/etc/netplan/default-DHCP.yaml) for an example of how you could setup the network.

* Ensure we're running kernel 5.17+

> While the default kernel on most modern operating systems will work, we recommend running with Kernel 6.2+.

* Kernel modules

> The Kubespray tool chain will attempt to deploy a lot of things, one thing is a set of `sysctl` options which will include bridge tunings.
> Given the tooling will assume bridging is functional, you will need to ensure the `br_netfilter` module is loaded or you're using a kernel that includes that functionality as a built-in.

* Executable `/tmp`

> The `/tmp` directory is used as a download and staging location within the environment. You will need to make sure that the `/tmp` is executable.
> By default, some kick-systems set the mount option **noexec**, if that is defined you should remove it before running the deployment.

### Create your Inventory

A default inventory file for kubespray is provided at `/etc/genestack/inventory` and must be modified.

Checkout the [openstack-flex/prod-inventory-example.yaml](https://github.com/rackerlabs/genestack/blob/main/ansible/inventory/openstack-flex/inventory.yaml.example) file for an example of a target environment.

> NOTE before you deploy the kubernetes cluster you should define the `kube_override_hostname` option in your inventory.
  This variable will set the node name which we will want to be an FQDN. When you define the option, it should have the
  same suffix defined in our `cluster_name` variable.

However, any Kubespray compatible inventory will work with this deployment tooling. The official [Kubespray documentation](https://kubespray.io) can be used to better understand the inventory options and requirements. Within the `ansible/playbooks/inventory` directory there is a directory named `openstack-flex` and `openstack-enterprise`. These directories provide everything we need to run a successful Kubernetes environment for genestack at scale. The difference between **enterprise** and **flex** are just target environment types.

### Ensure systems have a proper FQDN Hostname

Before running the Kubernetes deployment, make sure that all hosts have a properly configured FQDN.

``` shell
source /opt/genestack/scripts/genestack.rc
ansible -m shell -a 'hostnamectl set-hostname {{ inventory_hostname }}' --become all
```

> NOTE in the above command I'm assuming the use of `cluster.local` this is the default **cluster_name** as defined in the
  group_vars k8s_cluster file. If you change that option, make sure to reset your domain name on your hosts accordingly.


The ansible inventory is expected at `/etc/genestack/inventory`

### Prepare hosts for installation

``` shell
source /opt/genestack/scripts/genestack.rc
cd /opt/genestack/ansible/playbooks
```

> The RC file sets a number of environment variables that help ansible to run in a more easily to understand way.

While the `ansible-playbook` command should work as is with the sourced environment variables, sometimes it's necessary to set some overrides on the command line.
The following example highlights a couple of overrides that are generally useful.

#### Example host setup playbook

``` shell
ansible-playbook host-setup.yml
```

#### Example host setup playbook with overrides

Confirm openstack-flex-inventory.yaml matches what is in /etc/genestack/inventory. If it does not match update the command to match the file names.

``` shell
# Example overriding things on the CLI
ansible-playbook host-setup.yml --inventory /etc/genestack/inventory/openstack-flex-inventory.yaml \
                                --private-key ${HOME}/.ssh/openstack-flex-keypair.key
```

### Run the cluster deployment

This is used to deploy kubespray against infra on an OpenStack cloud. If you're deploying on baremetal you will need to setup an inventory that meets your environmental needs.

Change the directory to the kubespray submodule.

``` shell
cd /opt/genestack/submodules/kubespray
```

Source your environment variables

``` shell
source /opt/genestack/scripts/genestack.rc
```

> The RC file sets a number of environment variables that help ansible to run in a more easy to understand way.

Once the inventory is updated and configuration altered (networking etc), the Kubernetes cluster can be initialized with

``` shell
ansible-playbook cluster.yml
```

The cluster deployment playbook can also have overrides defined to augment how the playbook is executed.
Confirm openstack-flex-inventory.yaml matches what is in /etc/genestack/inventory. If it does not match update the command to match the file names.


``` shell
ansible-playbook --inventory /etc/genestack/inventory/openstack-flex-inventory.yaml \
                 --private-key /home/ubuntu/.ssh/openstack-flex-keypair.key \
                 --user ubuntu \
                 --become \
                 cluster.yml
```

> Given the use of a venv, when running with `sudo` be sure to use the full path and pass through your environment variables; `sudo -E /home/ubuntu/.venvs/genestack/bin/ansible-playbook`.

Once the cluster is online, you can run `kubectl` to interact with the environment.

### Retrieve Kube Config

The instructions can be found here [Kube Config](https://rackerlabs.github.io/genestack/kube-config/)


### Remove taint from our Controllers

In an environment with a limited set of control plane nodes removing the NoSchedule will allow you to converge the
openstack controllers with the k8s controllers.

``` shell
# Remote taint from control-plane nodes
kubectl taint nodes $(kubectl get nodes -o 'jsonpath={.items[*].metadata.name}') node-role.kubernetes.io/control-plane:NoSchedule-
```

### Optional - Deploy K8S Dashboard RBAC

While the dashboard is installed you will have no ability to access it until we setup some basic RBAC.

``` shell
kubectl apply -k /opt/genestack/kustomize/k8s-dashboard
```

You can now retrieve a permanent token.

``` shell
kubectl get secret admin-user -n kube-system -o jsonpath={".data.token"} | base64 -d
```


## Label all of the nodes in the environment

> The following example assumes the node names can be used to identify their purpose within our environment. That
  may not be the case in reality. Adapt the following commands to meet your needs.

``` shell
# Label the storage nodes - optional and only used when deploying ceph for K8S infrastructure shared storage
kubectl label node $(kubectl get nodes | awk '/ceph/ {print $1}') role=storage-node

# Label the openstack controllers
kubectl label node $(kubectl get nodes | awk '/controller/ {print $1}') openstack-control-plane=enabled

# Label the openstack compute nodes
kubectl label node $(kubectl get nodes | awk '/compute/ {print $1}') openstack-compute-node=enabled

# Label the openstack network nodes
kubectl label node $(kubectl get nodes | awk '/network/ {print $1}') openstack-network-node=enabled

# Label the openstack storage nodes
kubectl label node $(kubectl get nodes | awk '/storage/ {print $1}') openstack-storage-node=enabled

# With OVN we need the compute nodes to be "network" nodes as well. While they will be configured for networking, they wont be gateways.
kubectl label node $(kubectl get nodes | awk '/compute/ {print $1}') openstack-network-node=enabled

# Label all workers - Recommended and used when deploying Kubernetes specific services
kubectl label node $(kubectl get nodes | awk '/worker/ {print $1}')  node-role.kubernetes.io/worker=worker
```

Check the node labels

``` shell
# Verify the nodes are operational and labled.
kubectl get nodes -o wide --show-labels=true
```
``` shell
# Here is a way to make it look a little nicer:
kubectl get nodes -o json | jq '[.items[] | {"NAME": .metadata.name, "LABELS": .metadata.labels}]'
```

## Install Helm

While `helm` should already be installed with the **host-setup** playbook, you will need to install helm manually on nodes. There are lots of ways to install helm, check the upstream [docs](https://helm.sh/docs/intro/install/) to learn more about installing helm.

### Run `make` for our helm components

``` shell
cd /opt/genestack/submodules/openstack-helm &&
make all

cd /opt/genestack/submodules/openstack-helm-infra &&
make all
```
