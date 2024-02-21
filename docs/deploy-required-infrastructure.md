# Infrastructure Deployment Demo

[![asciicast](https://asciinema.org/a/629790.svg)](https://asciinema.org/a/629790)

# Running the infrastructure deployment

The infrastructure deployment can almost all be run in parallel. The above demo does everything serially to keep things consistent and easy to understand but if you just need to get things done, feel free to do it all at once.

## Create our basic OpenStack namespace

The following command will generate our OpenStack namespace and ensure we have everything needed to proceed with the deployment.

``` shell
kubectl apply -k /opt/genestack/kustomize/openstack
```

## Deploy the MariaDB Operator and a Galera Cluster

### Create secret

``` shell
kubectl --namespace openstack \
        create secret generic mariadb \
        --type Opaque \
        --from-literal=root-password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)" \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
```

### Deploy the mariadb operator

If you've changed your k8s cluster name from the default cluster.local, edit `clusterName` in `/opt/genestack/kustomize/mariadb-operator/kustomization.yaml` prior to deploying the mariadb operator.

``` shell
kubectl kustomize --enable-helm /opt/genestack/kustomize/mariadb-operator | kubectl --namespace mariadb-system apply --server-side --force-conflicts -f -
```

> The operator may take a minute to get ready, before deploying the Galera cluster, wait until the webhook is online.

``` shell
kubectl --namespace mariadb-system get pods -w
```

### Deploy the MariaDB Cluster

``` shell
kubectl --namespace openstack apply -k /opt/genestack/kustomize/mariadb-cluster/base
```

> NOTE MariaDB has a base configuration which is HA and production ready. If you're deploying on a small cluster the `aio` configuration may better suit the needs of the environment.

### Verify readiness with the following command

``` shell
kubectl --namespace openstack get mariadbs -w
```

## Deploy the RabbitMQ Operator and a RabbitMQ Cluster

### Deploy the RabbitMQ operator.

``` shell
kubectl apply -k /opt/genestack/kustomize/rabbitmq-operator
```
> The operator may take a minute to get ready, before deploying the RabbitMQ cluster, wait until the operator pod is online.

### Deploy the RabbitMQ topology operator.

``` shell
kubectl apply -k /opt/genestack/kustomize/rabbitmq-topology-operator
```

### Deploy the RabbitMQ cluster.

``` shell
kubectl apply -k /opt/genestack/kustomize/rabbitmq-cluster/base
```

> NOTE RabbitMQ has a base configuration which is HA and production ready. If you're deploying on a small cluster the `aio` configuration may better suit the needs of the environment.

### Validate the status with the following

``` shell
kubectl --namespace openstack get rabbitmqclusters.rabbitmq.com -w
```

## Deploy a Memcached

### Deploy the Memcached Cluster

``` shell
kubectl kustomize --enable-helm /opt/genestack/kustomize/memcached/base | kubectl apply --namespace openstack -f -
```

> NOTE Memcached has a base configuration which is HA and production ready. If you're deploying on a small cluster the `aio` configuration may better suit the needs of the environment.

### Verify readiness with the following command.

``` shell
kubectl --namespace openstack get horizontalpodautoscaler.autoscaling memcached -w
```

# Deploy the ingress controllers

We need two different Ingress controllers, one in the `openstack` namespace, the other in the `ingress-nginx` namespace. The `openstack` controller is for east-west connectivity, the `ingress-nginx` controller is for north-south.

### Deploy our ingress controller within the ingress-nginx Namespace

``` shell
kubectl kustomize --enable-helm /opt/genestack/kustomize/ingress/external | kubectl apply --namespace ingress-nginx -f -
```

### Deploy our ingress controller within the OpenStack Namespace

``` shell
kubectl kustomize --enable-helm /opt/genestack/kustomize/ingress/internal | kubectl apply --namespace openstack -f -
```

The openstack ingress controller uses the class name `nginx-openstack`.

## Setup the MetalLB Loadbalancer

The MetalLb loadbalancer can be setup by editing the following file `metallb-openstack-service-lb.yml`, You will need to add
your "external" VIP(s) to the loadbalancer so that they can be used within services. These IP addresses are unique and will
need to be customized to meet the needs of your environment.

### Example LB manifest

```yaml
metadata:
  name: openstack-external
  namespace: metallb-system
spec:
  addresses:
  - 10.74.8.99/32  # This is assumed to be the public LB vip address
  autoAssign: false
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: openstack-external-advertisement
  namespace: metallb-system
spec:
  ipAddressPools:
  - openstack-external
  nodeSelectors:  # Optional block to limit nodes for a given advertisement
  - matchLabels:
      kubernetes.io/hostname: controller01.sjc.ohthree.com
  - matchLabels:
      kubernetes.io/hostname: controller02.sjc.ohthree.com
  - matchLabels:
      kubernetes.io/hostname: controller03.sjc.ohthree.com
  interfaces:  # Optional block to limit ifaces used to advertise VIPs
  - br-mgmt
```

``` shell
kubectl apply -f /opt/genestack/manifests/metallb/metallb-openstack-service-lb.yml
```

Assuming your ingress controller is all setup and your metallb loadbalancer is operational you can patch the ingress controller to expose your external VIP address.

``` shell
kubectl --namespace openstack patch service ingress -p '{"metadata":{"annotations":{"metallb.universe.tf/allow-shared-ip": "openstack-external-svc", "metallb.universe.tf/address-pool": "openstack-external"}}}'
kubectl --namespace openstack patch service ingress -p '{"spec": {"type": "LoadBalancer"}}'
```

Once patched you can see that the controller is operational with your configured VIP address.

``` shell
kubectl --namespace openstack get services ingress
```

## Deploy Libvirt

The first part of the compute kit is Libvirt.

``` shell
kubectl kustomize --enable-helm /opt/genestack/kustomize/libvirt | kubectl apply --namespace openstack -f -
```

Once deployed you can validate functionality on your compute hosts with `virsh`

``` shell
root@openstack-flex-node-3:~# virsh
Welcome to virsh, the virtualization interactive terminal.

Type:  'help' for help with commands
       'quit' to quit

virsh # list
 Id   Name   State
--------------------

virsh #
```

## Deploy Open vSwitch OVN

Note that we're not deploying Openvswitch, however, we are using it. The implementation on Genestack is assumed to be
done with Kubespray which deploys OVN as its networking solution. Because those components are handled by our infrastructure
there's nothing for us to manage / deploy in this environment. OpenStack will leverage OVN within Kubernetes following the
scaling/maintenance/management practices of kube-ovn.

### Configure OVN for OpenStack

Post deployment we need to setup neutron to work with our integrated OVN environment. To make that work we have to annotate or nodes. Within the following commands we'll use a lookup to label all of our nodes the same way, however, the power of this system is the ability to customize how our machines are labeled and therefore what type of hardware layout our machines will have. This gives us the ability to use different hardware in different machines, in different availability zones. While this example is simple your cloud deployment doesn't have to be.

``` shell
export ALL_NODES=$(kubectl get nodes -l 'openstack-network-node=enabled' -o 'jsonpath={.items[*].metadata.name}')
```

> Set the annotations you need within your environment to meet the needs of your workloads on the hardware you have.

#### Set `ovn.openstack.org/int_bridge`

Set the name of the OVS integration bridge we'll use. In general, this should be **br-int**, and while this setting is implicitly configured we're explicitly defining what the bridge will be on these nodes.

``` shell
kubectl annotate \
        nodes \
        ${ALL_NODES} \
        ovn.openstack.org/int_bridge='br-int'
```

#### Set `ovn.openstack.org/bridges`

Set the name of the OVS bridges we'll use. These are the bridges you will use on your hosts within OVS. The option is a string and comma separated. You can define as many OVS type bridges you need or want for your environment.

> NOTE The functional example here annotates all nodes; however, not all nodes have to have the same setup.

``` shell
kubectl annotate \
        nodes \
        ${ALL_NODES} \
        ovn.openstack.org/bridges='br-ex'
```

#### Set `ovn.openstack.org/ports`

Set the port mapping for OVS interfaces to a local physical interface on a given machine. This option uses a colon between the OVS bridge and the and the physical interface, `OVS_BRIDGE:PHYSICAL_INTERFACE_NAME`. Multiple bridge mappings can be defined by separating values with a comma.

``` shell
kubectl annotate \
        nodes \
        ${ALL_NODES} \
        ovn.openstack.org/ports='br-ex:bond1'
```

#### Set `ovn.openstack.org/mappings`

Set the Neutron bridge mapping. This maps the Neutron interfaces to the ovs bridge names. These are colon delimitated between `NEUTRON_INTERFACE:OVS_BRIDGE`. Multiple bridge mappings can be defined here and are separated by commas.

> Neutron interfaces are string value and can be anything you want. The `NEUTRON_INTERFACE` value defined will be used when you create provider type networks after the cloud is online.

``` shell
kubectl annotate \
        nodes \
        ${ALL_NODES} \
        ovn.openstack.org/mappings='physnet1:br-ex'
```

#### Set `ovn.openstack.org/availability_zones`

Set the OVN availability zones which inturn creates neutron availability zones. Multiple network availability zones can be defined and are colon separated which allows us to define all of the availability zones a node will be able to provide for, `nova:az1:az2:az3`.

``` shell
kubectl annotate \
        nodes \
        ${ALL_NODES} \
        ovn.openstack.org/availability_zones='nova'
```

> Any availability zone defined here should also be defined within your **neutron.conf**. The "nova" availability zone is an assumed defined, however, because we're running in a mixed OVN environment, we should define where we're allowed to execute OpenStack workloads.

#### Set `ovn.openstack.org/gateway`

Define where the gateways nodes will reside. There are many ways to run this, some like every compute node to be a gateway, some like dedicated gateway hardware. Either way you will need at least one gateway node within your environment.

``` shell
kubectl annotate \
        nodes \
        ${ALL_NODES} \
        ovn.openstack.org/gateway='enabled'
```

### Run the OVN integration

With all of the annotations defined, we can now apply the network policy with the following command.

``` shell
kubectl apply -k /opt/genestack/kustomize/ovn
```

After running the setup, nodes will have the label `ovn.openstack.org/configured` with a date stamp when it was configured.
If there's ever a need to reconfigure a node, simply remove the label and the DaemonSet will take care of it automatically.

## Validation our infrastructure is operational

Before going any further make sure you validate that the backends are operational.

``` shell
# MariaDB
kubectl --namespace openstack get mariadbs

#RabbitMQ
kubectl --namespace openstack get rabbitmqclusters.rabbitmq.com

# Memcached
kubectl --namespace openstack get horizontalpodautoscaler.autoscaling memcached
```

Once everything is Ready and online. Continue with the installation.

