# Magnum Kubernetes Cluster Setup Guide

You can provision kubernetes clusters made up of virtual machines or baremetal servers. Magnum service uses Cluster Templates to describe how a Cluster is constructed. In below example you will create a Cluster Template for a specific COE and then you will provision a Cluster using the corresponding Cluster Template. Then, you can use the appropriate COE client or endpoint to create containers. For more detailed information on creating clusters, refer to the [upstream magnum documentation](https://docs.openstack.org/magnum/latest/user/index.html).

## Create an image
``` shell
wget https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/40.20240728.3.0/x86_64/fedora-coreos-40.20240728.3.0-openstack.x86_64.qcow2.xz
apt-get update
apt-get install wget xz-utils
unxz fedora-coreos-40.20240728.3.0-openstack.x86_64.qcow2.xz
```

``` shell
openstack image create --disk-format=qcow2 --container-format=bare --file=fedora-coreos-40.20240728.3.0-openstack.x86_64.qcow2 --property os_distro='fedora-coreos' fedora-coreos-latest
```

## Create an external network (optional)
To create a magnum cluster, you need an external network. If there are no external networks, create one with an appropriate provider based on your cloud provider support for your case:
``` shell
openstack network create public --provider-network-type vlan --external --project service
```

``` shell
openstack subnet create public-subnet --network public --subnet-range 192.168.1.0/24 --gateway 192.168.1.1 --ip-version 4
```

## Create a keypair (Optional)
To create a magnum cluster, you need a keypair which will be passed in all compute instances of the cluster. If you don’t have a keypair in your project, create one.
``` shell
openstack keypair create --public-key ~/.ssh/id_rsa.pub mykey
```

## Provision a Kubernetes cluster
Following this example, you will provision a Kubernetes cluster with one master and one node.

Create a cluster template for a Kubernetes cluster using the fedora-coreos-latest image, m1.large as the flavor for the master and the node, public as the external network and 8.8.8.8 for the DNS nameserver, using the following command:
``` shell
openstack coe cluster template create new-cluster-template \
          --image fedora-coreos-latest  \
          --external-network public \
          --dns-nameserver 8.8.8.8 \
          --master-flavor m1.large \
          --flavor m1.large  \
          --coe "kubernetes"
```

Create a cluster with one node and one master using mykey as the keypair, using the following command:
``` shell
openstack coe cluster create new-k8s-cluster \
          --cluster-template new-cluster-template \
          --master-count 1 \
          --node-count 1 \
          --keypair mykey
```
