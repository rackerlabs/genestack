# Magnum Kubernetes Cluster Setup Guide

!!! note

    Octavia and Barbican are mandatory components for OpenStack Magnum. Octavia provides advanced load balancing capabilities, which can enhance the availability and distribution of network traffic across your containerized applications. Barbican offers secure management of encryption keys and secrets, which is valuable for maintaining the security of your applications and data. Ensuring these services are integrated into your OpenStack environment is necessary for optimizing the functionality and security of your Magnum-based deployments.

This document is intended for users who use Magnum to deploy and manage clusters of hosts for a Container Orchestration Engine. It describes the infrastructure that Magnum creates and how to work with them. You can provision clusters made up of virtual machines or baremetal servers. Magnum service uses Cluster Templates to describe how a Cluster is constructed. The process involves creating a Cluster Template for a specific COE and then you will provision a Cluster using the corresponding Cluster Template.  Once the cluster is provisioned, you can use the appropriate COE client or endpoint to manage and deploy containers. For more detailed information on cluster creation and management, please refer to the [Magnum User Guide](https://docs.openstack.org/magnum/latest/user/index.html).

## Create an image

To create an image required by Magnum, please refer to the [Glance Image Creation Guide](https://docs.rackspacecloud.com/openstack-glance-images/#fedora-coreos-image-required-by-magnum) for detailed instructions on how to set up a Fedora CoreOS image.

## Create an external network (optional)

To create a Magnum cluster, you need an external network. If there are no external networks, create one with an appropriate provider based on your usecase. Here is an example command:

``` shell
openstack network create public --provider-network-type vlan --external --project service
```

``` shell
openstack subnet create public-subnet --network public --subnet-range 192.168.1.0/24 --gateway 192.168.1.1 --ip-version 4
```

## Create a keypair (Optional)

To create a magnum cluster, you need a keypair which will be passed in all compute instances of the cluster. If you don’t have a keypair in your project, create one.

``` shell
openstack keypair create mykey > mykey.pem
```

## ClusterTemplate

A ClusterTemplate is a collection of parameters to describe how a cluster can be constructed. Some parameters are relevant to the infrastructure of the cluster, while others are for the particular COE. In a typical workflow, a user would create a ClusterTemplate, then create one or more clusters using the ClusterTemplate. A ClusterTemplate cannot be updated or deleted if a cluster using this ClusterTemplate still exists.

!!! note "Information about the Default Public ClusterTemplate"

    A default ClusterTemplate, named default-cluster-template, can be created in the environment and used by anyone to deploy new Kubernetes clusters. To use this template, pass the --cluster-template default-cluster-template parameter during cluster creation.

    ??? example "Default Public ClusterTemplate Creation"

        ``` shell
        openstack coe cluster template create default-cluster-template \
                  --image magnum-fedora-coreos-40 \
                  --external-network  PUBLICNET \
                  --dns-nameserver 8.8.8.8 \
                  --master-flavor gp.0.4.8 \
                  --flavor gp.0.4.8 \
                  --network-driver calico \
                  --volume-driver cinder \
                  --docker-volume-size 10 \
                  --coe kubernetes \
                  --public
        ```

### Create a ClusterTemplate

Create a Kubernetes cluster template using the `magnum-fedora-coreos-40` image with the following configuration: `m1.large` flavor for both master and nodes, `public` as the external network, `8.8.8.8` for the DNS nameserver, `calico` for the network driver, and `cinder` for the volume driver. Below is the example command to create the clustertemplate. For more detailed information about the parameters and labels used in the ClusterTemplate, please refer to the [ClusterTemplate](https://docs.openstack.org/magnum/latest/user/index.html#clustertemplate).

``` shell
openstack coe cluster template create new-cluster-template \
          --image magnum-fedora-coreos-40  \
          --external-network public \
          --dns-nameserver 8.8.8.8 \
          --master-flavor m1.large \
          --flavor m1.large  \
          --network-driver calico \
          --volume-driver cinder \
          --docker-volume-size 10 \
          --coe kubernetes
```

## Cluster

A cluster is an instance of the ClusterTemplate of a COE. Magnum deploys a cluster by referring to the attributes defined in the particular ClusterTemplate as well as a few additional parameters for the cluster. Magnum deploys the orchestration templates provided by the cluster driver to create and configure all the necessary infrastructure. When ready, the cluster is a fully operational COE that can host containers. For details on parameters and labels used in cluster creation, see the [Cluster](https://docs.openstack.org/magnum/latest/user/index.html#cluster) documentation.

### Provision a Kubernetes cluster

Create a cluster with `4` nodes and `3` masters using `mykey` as the keypair, using the following command:

``` shell
openstack coe cluster create new-k8s-cluster \
          --cluster-template new-cluster-template \
          --master-count 3 \
          --node-count 4 \
          --keypair mykey \
          --labels kube_tag=v1.27.8-rancher2,container_runtime=containerd,containerd_version=1.6.28,containerd_tarball_sha256=f70736e52d61e5ad225f4fd21643b5ca1220013ab8b6c380434caeefb572da9b,cloud_provider_tag=v1.27.3,cinder_csi_plugin_tag=v1.27.3,k8s_keystone_auth_tag=v1.27.3,magnum_auto_healer_tag=v1.27.3,octavia_ingress_controller_tag=v1.27.3,calico_tag=v3.26.4,auto_healing_enabled=True,auto_healing_controller=magnum-auto-healer
```
