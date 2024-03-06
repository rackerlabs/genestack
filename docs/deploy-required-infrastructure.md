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

### Alternative - Deploy the Memcached Cluster With Monitoring Enabled

``` shell
kubectl kustomize --enable-helm /opt/genestack/kustomize/memcached/base-monitoring | kubectl apply --namespace openstack -f -
```

> NOTE Memcached has a base-monitoring configuration which is HA and production ready that also includes a metrics exporter for prometheus metrics collection. If you'd like to have monitoring enabled for your memcached cluster ensure the prometheus operator is installed first ([Deploy Prometheus](prometheus.md)).


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

## Deploy PostgreSQL

### Create Secrets

```shell
kubectl --namespace openstack create secret generic postgresql-identity-admin \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
kubectl --namespace openstack create secret generic postgresql-db-admin \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
kubectl --namespace openstack create secret generic postgresql-db-exporter \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
kubectl --namespace openstack create secret generic postgresql-db-audit \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
```

### Run the package deployment

> Consider the PVC size you will need for the environment you're deploying in.
  Make adjustments as needed near `storage.[pvc|archive_pvc].size` and
  `volume.backup.size` to your helm overrides.

```shell
cd /opt/genestack/submodules/openstack-helm-infra
helm upgrade --install postgresql ./postgresql \
    --namespace=openstack \
    --wait \
    --timeout 10m \
    -f /opt/genestack/helm-configs/postgresql/postgresql-helm-overrides.yaml \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.postgresql.password="$(kubectl --namespace openstack get secret postgresql-identity-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.postgresql.auth.admin.password="$(kubectl --namespace openstack get secret postgresql-db-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.postgresql.auth.exporter.password="$(kubectl --namespace openstack get secret postgresql-db-exporter -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.postgresql.auth.audit.password="$(kubectl --namespace openstack get secret postgresql-db-audit -o jsonpath='{.data.password}' | base64 -d)"
```

> In a production like environment you may need to include production specific files like the example variable file found in
  `helm-configs/prod-example-openstack-overrides.yaml`.

## Deploy Gnocchi

### Create Secrets

```shell
kubectl --namespace openstack create secret generic gnocchi-admin \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
kubectl --namespace openstack create secret generic gnocchi-db-password \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
kubectl --namespace openstack create secret generic gnocchi-pgsql-password \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
```

### Create ceph-etc configmap

While the below example should work fine for most environments, depending
on the use case it may be necessary to provide additional client configuration
options for ceph. The below simply creates the expected `ceph-etc`
ConfigMap with the ceph.conf needed by Gnocchi to establish a connection
to the mon host(s) via the rados client.

```shell
kubectl apply -n openstack -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ceph-etc
  namespace: openstack
data:
  ceph.conf: |
    [global]
    mon_host = $(for pod in $(kubectl get pods -n rook-ceph | grep rook-ceph-mon | awk '{print $1}'); do \
    	echo -n "$(kubectl get pod $pod -n rook-ceph -o go-template --template='{{.status.podIP}}'):6789,"; done \
    	| sed 's/,$//')
EOF
```

### Verify the ceph-etc configmap is sane

Below is an example of what you're looking for to verify the configmap was
created as expected - a CSV of the mon hosts, colon seperated with default
mon port, 6789.

```shell
(genestack) root@openstack-flex-launcher:/opt/genestack# kubectl get configmap -n openstack ceph-etc -o "jsonpath={.data['ceph\.conf']}"
[global]
mon_host = 172.31.3.7:6789,172.31.1.112:6789,172.31.0.46:6789
```

### Run the package deployment

```shell
cd /opt/genestack/submodules/openstack-helm-infra
helm upgrade --install gnocchi ./gnocchi \
    --namespace=openstack \
    --wait \
    --timeout 10m \
    -f /opt/genestack/helm-configs/gnocchi/gnocchi-helm-overrides.yaml \
    --set conf.ceph.admin_keyring="$(kubectl get secret --namespace rook-ceph rook-ceph-admin-keyring -o jsonpath='{.data.keyring}' | base64 -d)" \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.gnocchi.password="$(kubectl --namespace openstack get secret gnocchi-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.gnocchi.password="$(kubectl --namespace openstack get secret gnocchi-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db_postgresql.auth.admin.password="$(kubectl --namespace openstack get secret postgresql-db-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db_postgresql.auth.gnocchi.password="$(kubectl --namespace openstack get secret gnocchi-pgsql-password -o jsonpath='{.data.password}' | base64 -d)" \
    --post-renderer /opt/genestack/kustomize/kustomize.sh \
    --post-renderer-args gnocchi/base
```

> In a production like environment you may need to include production specific files like the example variable file found in
  `helm-configs/prod-example-openstack-overrides.yaml`.

### Validate the metric endpoint

#### Pip install gnocchiclient and python-ceilometerclient

```shell
kubectl exec -it openstack-admin-client -n openstack -- /var/lib/openstack/bin/pip install python-ceilometerclient gnocchiclient
```

#### Verify metric list functionality

```shell
kubectl exec -it openstack-admin-client -n openstack -- openstack metric list
```

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
