# Overview

Evaluating Kubespray in an environment for OpenStack. Deployment will include the following

* Kubernetes
* K-Dashboard
* Kube-OVN
* MetalLB
* Metric Collection
* Deploy OpenStack


## Get the code

``` shell
git clone --recurse-submodules -j4 https://github.com/cloudnull/flex-rxt /opt/flex-rxt
```


## Basic Setup

> This setup is using venv, make sure you have the required packages installed to facilitate that need.

``` shell
export LC_ALL=C.UTF-8
mkdir ~/.venvs
python3 -m venv ~/.venvs/kubespray
.venvs/kubespray/bin/pip install pip  --upgrade
source ~/.venvs/kubespray/bin/activate
pip install -r /opt/flex-rxt/submodules/kubespray/requirements.txt
```

The inventory defaults are in the root of this repo and can be symlinked into your kubspray environment.

``` shell
cd /opt/flex-rxt/submodules/kubespray/inventory
ln -s /opt/flex-rxt/openstack-flex
```


## Test Environments

If deploying in a lab environment on an OpenStack cloud, you can run the `infra-deploy.yaml` playbook
which will create all of the resources needed to operate the test environment.

Before running the `infra-deploy.yaml` playbook, be sure you have the ansible `openstack.cloud`
collection installed.

``` shell
ansible-galaxy collection install openstack.cloud --force
```

Run the test infrastructure deployment.

> This is used to deploy new infra on an existing OpenStack cloud. If you're deploying on baremetal this step can be skipped.

``` shell
ansible-playbook -i localhost, infra-deploy.yaml
```


## Deployment Kubespray

Before running the Kubernetes deployment, make sure that all hosts have a properly configured FQDN.

``` shell
ansible -m shell -a 'hostnamectl set-hostname {{ inventory_hostname }}' --become -i openstack-flex/inventory.ini all
```

> NOTE in the above command I'm assuming the use of `cluster.local` this is the default **cluster_name** as defined in the
  group_vars k8s_cluster file. If you change that option, make sure to reset your domain name on your hosts accordingly.

> NOTE before you deploy the kubernetes cluster you should define the `kube_override_hostname` option in your inventory.
  This variable will set the node name which we will want to be an FQDN. When you define the option it should have the
  same suffix defined in our `cluster_name` variable.

Run the cluster deployment

> This is used to deploy kubespray against infra on an OpenStack cloud. If you're deploying on baremetal you will need to setup an inventory that meets your environmental needs.
  Checkout the `openstack-flex/prod-inventory-example.yaml` file for an example of a production target environment.

``` shell
ansible-playbook -i inventory/openstack-flex/inventory.ini -u ubuntu -b cluster.yml
```

Install some base packages needed by OSH

``` shell
apt update
apt install jq make -y
```


## Setup OSH and make everything

The following steps will make all of our helm charts.

``` shell
# Export OSH variables
export CONTAINER_DISTRO_NAME=ubuntu
export CONTAINER_DISTRO_VERSION=jammy
export OPENSTACK_RELEASE=2023.1
export OSH_DEPLOY_MULTINODE=True

# Run make for everything.
cd /opt/flex-rxt/submodules/openstack-helm
make all

cd /opt/flex-rxt/submodules/openstack-helm-infra
make all
```


## Ensure the kube dashboard is setup

While the dashboard is installed you will have no ability to access it until we setup some basic RBAC.

``` shell
kubectl apply -f /opt/flex-rxt/manifests/k8s/dashboard-rbac-default.yaml
```

You can now retrieve a permenant token.

``` shell
kubectl get secret admin-user -n kube-system -o jsonpath={".data.token"} | base64 -d
```


## Install rook operator

Now run the basic deployment.

``` shell
# Deploy rook
kubectl apply -f /opt/flex-rxt/submodules/rook/deploy/examples/crds.yaml
kubectl apply -f /opt/flex-rxt/submodules/rook/deploy/examples/common.yaml
kubectl apply -f /opt/flex-rxt/submodules/rook/deploy/examples/operator.yaml

# Validate with readiness
kubectl --namespace rook-ceph get deployments.apps -w
```

Once the operator is online, it's time do deploy our Ceph environment. While the storage node label is used, the Ceph
cluster must be edited to name the nodes used in your deployment and set the device filter to match your hardware
layout.

``` shell
# Deploy our ceph cluster
kubectl apply -f /opt/flex-rxt/manifests/rook/rook-cluster.yaml
```

Once the ceph environment has been deployed, it's time to deploy some additional components ceph will use/have access to.

``` shell
# Deploy our ceph toolbox
kubectl apply -f /opt/flex-rxt/submodules/rook/deploy/examples/toolbox.yaml

# Create our cephfs filesystem
kubectl create -f /opt/flex-rxt/submodules/rook/deploy/examples/filesystem.yaml

# Create our cephfs storage classes
kubectl create -f /opt/flex-rxt/submodules/rook/deploy/examples/csi/cephfs/storageclass.yaml

# Create our rbd store classes
kubectl create -f /opt/flex-rxt/submodules/rook/deploy/examples/csi/rbd/storageclass.yaml

# Create our general (rbd) store classes, which is marked default.
kubectl create -f /opt/flex-rxt/manifests/rook/storageclass-general.yaml
```

Label all of the nodes in the environment.

``` shell
# Label the storage nodes
kubectl label node $(kubectl get nodes | awk '/storage/ {print $1}') role=storage-node

# Label the openstack controllers
kubectl label node $(kubectl get nodes -l 'node-role.kubernetes.io/control-plane' -o 'jsonpath={.items[*].metadata.name}') openstack-control-plane=enabled

# Label the compute nodes
kubectl label node $(kubectl get nodes | awk '/compute/ {print $1}') openstack-compute-node=enabled

# Label the network nodes
kubectl label node $(kubectl get nodes | awk '/network/ {print $1}') openstack-network-node=enabled

# With  OVN we need the compute nodes to be "network" nodes as well. While they will be configured for networking, they wont be gateways.
kubectl label node $(kubectl get nodes | awk '/compute/ {print $1}') openstack-network-node=enabled

# Label control-plane nodes as workers
kubectl label node $(kubectl get nodes -l 'node-role.kubernetes.io/control-plane' -o 'jsonpath={.items[*].metadata.name}') node-role.kubernetes.io/worker=worker
```

Check the node labels

``` shell
# Verify the nodes are operational and labled.
kubectl get nodes -o wide
```


### Optional - Remove taint from our contorllers

In an environment with a limited set of control plane nodes removing the NoSchedule will allow you to converge the
openstack controllers with the k8s controllers.

``` shell
# Remote taint from control-plane nodes
kubectl taint nodes $(kubectl get nodes -o 'jsonpath={.items[*].metadata.name}') node-role.kubernetes.io/control-plane:NoSchedule-
```

Create our basic openstack namespace

``` shell
kubectl apply -f /opt/flex-rxt/manifests/openstack/ns-openstack.yaml
```


## Install mariadb

Create secret

``` shell
kubectl --namespace openstack \
        create secret generic mariadb \
        --type Opaque \
        --from-literal=root-password="$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-32};echo;)" \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-32};echo;)"
```

Deploy the mariadb operator.

``` shell
kubectl kustomize --enable-helm /opt/flex-rxt/kustomize/mariadb | kubectl apply --namespace openstack -f -
```

Verify readiness with the following command.

``` shell
kubectl --namespace openstack get mariadbs -w
```


## Install RabbitMQ

Deploy the RabbitMQ operator and cluster.

``` shell
kubectl apply -k /opt/flex-rxt/kustomize/rabbitmq/
```

Validate the status with the following

``` shell
kubectl --namespace openstack get rabbitmqclusters.rabbitmq.com -w
```


## Install memcached

``` shell
kubectl kustomize --enable-helm /opt/flex-rxt/kustomize/memcached | kubectl apply --namespace openstack -f -
```

Verify readiness with the following command.

``` shell
kubectl --namespace openstack get horizontalpodautoscaler.autoscaling memcached -w
```


## Deploy the ingress controllers

``` shell
kubectl kustomize --enable-helm /opt/flex-rxt/kustomize/ingress | kubectl apply --namespace openstack -f -
```


## Setup the MetalLB Loadbalancer

The MetalLb loadbalancer can be setup by editing the following file `metallb-openstack-service-lb.yml`, You will need to add
your "external" VIPs to the loadbalancer so that they can be used within services. These IP addresses are unique and will
need to be customized to meet the needs of your environment.

#### Example

``` shell
kubectl apply -f /opt/flex-rxt/manifests/metallb/metallb-openstack-service-lb.yml
```

Assuming your ingress controller is all setup and your metallb loadbalancer is operational you can patch the ingress
controller to expose your external VIP address

``` shell
kubectl --namespace openstack patch service ingress -p '{"metadata":{"annotations":{"metallb.universe.tf/allow-shared-ip": "openstack-external-svc", "metallb.universe.tf/address-pool": "openstack-external"}}}'
kubectl --namespace openstack patch service ingress -p '{"spec": {"type": "LoadBalancer"}}'
```

Once patched you can see that the controller is operational with your configured VIP address

``` shell
kubectl --namespace openstack get services ingress
```


## OpenStack

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

> The OpenStack commands install the environment with `helm`. We're using Kustomize with helm to configure services,
  create databases, and setup queues; however, the process is driven by `helm` at this time.


### Deploy Keystone

Create secrets.

``` shell
kubectl --namespace openstack \
        create secret generic keystone-rabbitmq-password \
        --type Opaque \
        --from-literal=username="keystone" \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-64};echo;)"
kubectl --namespace openstack \
        create secret generic keystone-db-password \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-32};echo;)"
kubectl --namespace openstack \
        create secret generic keystone-admin \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-32};echo;)"
kubectl --namespace openstack \
        create secret generic keystone-credential-keys \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-32};echo;)"
```

Run the package deployment.

``` shell
cd /opt/flex-rxt/submodules/openstack-helm

helm upgrade --install keystone ./keystone \
    --namespace=openstack \
    --wait \
    --timeout 120m \
    -f /opt/flex-rxt/helm-configs/keystone/keystone-helm-overrides.yaml \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.keystone.password="$(kubectl --namespace openstack get secret keystone-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.admin.password="$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.keystone.password="$(kubectl --namespace openstack get secret keystone-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)" \
    --post-renderer /opt/flex-rxt/kustomize/keystone/kustomize.sh
```

> In a production like environment you may need to include production specific files like the example variable file found in
  `helm-configs/prod-example-openstack-overrides.yaml`.

> NOTE: The image used here allows the system to run with RXT global authentication federation.
  The federated plugin can be seen here, https://github.com/cloudnull/keystone-rxt

Deploy the openstack admin client pod (optional)

``` shell
kubectl --namespace openstack apply -f /opt/flex-rxt/manifests/utils/utils-openstack-client-admin.yaml
```

Validate functionality

``` shell
kubectl --namespace openstack exec -ti openstack-admin-client -- openstack user list
```


### Deploy Glance

Create secrets.

``` shell
kubectl --namespace openstack \
        create secret generic glance-rabbitmq-password \
        --type Opaque \
        --from-literal=username="glance" \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-64};echo;)"
kubectl --namespace openstack \
        create secret generic glance-db-password \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-32};echo;)"
kubectl --namespace openstack \
        create secret generic glance-admin \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-32};echo;)"
```

Run the package deployment.

``` shell
cd /opt/flex-rxt/submodules/openstack-helm

helm upgrade --install glance ./glance \
    --namespace=openstack \
    --wait \
    --timeout 120m \
    -f /opt/flex-rxt/helm-configs/glance/glance-helm-overrides.yaml \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.glance.password="$(kubectl --namespace openstack get secret glance-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.glance.password="$(kubectl --namespace openstack get secret glance-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.admin.password="$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.glance.password="$(kubectl --namespace openstack get secret glance-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)" \
    --post-renderer /opt/flex-rxt/kustomize/glance/kustomize.sh
```

> In a production like environment you may need to include production specific files like the example variable file found in
  `helm-configs/prod-example-openstack-overrides.yaml`.

> Note that the defaults disable `storage_init` because we're using **pvc** as the image backend
  type. In production this should be changed to swift.

Validate functionality

``` shell
kubectl --namespace openstack exec -ti openstack-admin-client -- openstack image list
```


### Deploy Heat

Create secrets.

``` shell
kubectl --namespace openstack \
        create secret generic heat-rabbitmq-password \
        --type Opaque \
        --from-literal=username="heat" \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-64};echo;)"
kubectl --namespace openstack \
        create secret generic heat-db-password \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-32};echo;)"
kubectl --namespace openstack \
        create secret generic heat-admin \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-32};echo;)"
kubectl --namespace openstack \
        create secret generic heat-trustee \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-32};echo;)"
kubectl --namespace openstack \
        create secret generic heat-stack-user \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-32};echo;)"
```

Run the package deployment.

``` shell
cd /opt/flex-rxt/submodules/openstack-helm

helm upgrade --install heat ./heat \
  --namespace=openstack \
    --timeout 120m \
    -f /opt/flex-rxt/helm-configs/heat/heat-helm-overrides.yaml \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.heat.password="$(kubectl --namespace openstack get secret heat-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.heat_trustee.password="$(kubectl --namespace openstack get secret heat-trustee -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.heat_stack_user.password="$(kubectl --namespace openstack get secret heat-stack-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.heat.password="$(kubectl --namespace openstack get secret heat-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.admin.password="$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.heat.password="$(kubectl --namespace openstack get secret heat-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)" \
    --post-renderer /opt/flex-rxt/kustomize/heat/kustomize.sh
```

> In a production like environment you may need to include production specific files like the example variable file found in
  `helm-configs/prod-example-openstack-overrides.yaml`.

Validate functionality

``` shell
kubectl --namespace openstack exec -ti openstack-admin-client -- openstack --os-interface internal orchestration service list
```


### Deploy Cinder

Create secrets.

``` shell
kubectl --namespace openstack \
        create secret generic cinder-rabbitmq-password \
        --type Opaque \
        --from-literal=username="cinder" \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-64};echo;)"
kubectl --namespace openstack \
        create secret generic cinder-db-password \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-32};echo;)"
kubectl --namespace openstack \
        create secret generic cinder-admin \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-32};echo;)"
```

Run the package deployment.

``` shell
cd /opt/flex-rxt/submodules/openstack-helm

helm upgrade --install cinder ./cinder \
  --namespace=openstack \
    --wait \
    --timeout 120m \
    -f /opt/flex-rxt/helm-configs/cinder/cinder-helm-overrides.yaml \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.cinder.password="$(kubectl --namespace openstack get secret cinder-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.cinder.password="$(kubectl --namespace openstack get secret cinder-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.admin.password="$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.cinder.password="$(kubectl --namespace openstack get secret cinder-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)" \
    --post-renderer /opt/flex-rxt/kustomize/cinder/kustomize.sh
```

> In a production like environment you may need to include production specific files like the example variable file found in
  `helm-configs/prod-example-openstack-overrides.yaml`.

Once the helm deployment is complete cinder and all of it's API services will be online. However, using this setup there will be no volume node at this point.
The reason volume deployments have been disabled is because I didn't expose ceph to the openstack environment and OSH makes a lot of ceph related assumptions.
For testing purposes we're wanting to run with the logical volume driver (reference) and manage the deployment of that driver in a hybrid way. As such there's
a deployment outside of our normal K8S workflow will be needed on our volume host.

> The LVM volume makes the assumption that the storage node has the required volume group setup `lvmdriver-1` on the node. This is not something that K8S is
  handling at this time.

The hybrid volume node needs a couple things to be able to communicate back to our K8S environment.

1. DNS server, this is expected to be our coredns IP, in my case this is `169.254.25.10`.
2. To find our service domains, make sure to add a domain search for `openstack.svc.cluster.local svc.cluster.local cluster.local`

This is an example of my **systemd-resolved** conf found in `/etc/systemd/resolved.conf`
``` conf
[Resolve]
DNS=169.254.25.10
#FallbackDNS=
Domains=openstack.svc.cluster.local svc.cluster.local cluster.local
#LLMNR=no
#MulticastDNS=no
DNSSEC=no
Cache=no-negative
#DNSStubListener=yes
```

Restart your DNS service after changes are made.

``` shell
systemctl restart systemd-resolved.service
```

For ease of operation I've included my entire cinder configuration in this repo. Copy these files to your target node(s) at `/etc/cinder`.

> This is not intended to work as is, you will need to change the files to use information from your cluster. This is just a POC which
  highlights how we can get to a hybrid solution; this should be an automated deliverable.

With the files in place, install your desired version of the cinder service.

``` shell
apt install build-essential python3-venv python3-dev -y
python3 -m venv /opt/cinder
/opt/cinder/bin/pip install pip pymysql --upgrade
/opt/cinder/bin/pip install git+https://github.com/openstack/cinder@stable/2023.1
```

Run cinder the Cinder volume service.

``` shell
systemd-run /opt/cinder/bin/cinder-volume --config-file /etc/cinder/cinder.conf --config-file /etc/cinder/conf/backends.conf
```

> NOTE: The above command will run the `cinder-volume` service with systemd, but it won't survive a reboot.

After this deployment has completed the volume service will be operational, which we can see with the following command.

``` shell
kubectl --namespace openstack exec -ti openstack-admin-client -- openstack volume service list
```

Now we can create the volume type to ensure we're able to deploy volumes with our volume driver.

``` shell
kubectl --namespace openstack exec -ti openstack-admin-client -- openstack volume type create --public lvmdriver-1
```

Verify functionality by creating a volume

``` shell
kubectl --namespace openstack exec -ti openstack-admin-client -- openstack volume create --size 1 test-lvm
kubectl --namespace openstack exec -ti openstack-admin-client -- openstack volume show test-lvm
+--------------------------------+--------------------------------------+
| Field                          | Value                                |
+--------------------------------+--------------------------------------+
| attachments                    | []                                   |
| availability_zone              | nova                                 |
| bootable                       | false                                |
| consistencygroup_id            | None                                 |
| created_at                     | 2023-12-12T04:40:41.000000           |
| description                    | None                                 |
| encrypted                      | False                                |
| id                             | 70a07aa6-8cf1-4b74-9623-eefbf0bf6e2e |
| migration_status               | None                                 |
| multiattach                    | False                                |
| name                           | test-lvm                             |
| os-vol-host-attr:host          | cinder-volume-worker@lvmdriver-1#LVM |
| os-vol-mig-status-attr:migstat | None                                 |
| os-vol-mig-status-attr:name_id | None                                 |
| os-vol-tenant-attr:tenant_id   | 7abed12be0ce4a828a35f400cd8e6f1e     |
| properties                     |                                      |
| replication_status             | None                                 |
| size                           | 1                                    |
| snapshot_id                    | None                                 |
| source_volid                   | None                                 |
| status                         | available                            |
| type                           | lvmdriver-1                          |
| updated_at                     | 2023-12-12T04:40:42.000000           |
| user_id                        | 68718fb353c7446f9b7d3b3ca8c7ae28     |
+--------------------------------+--------------------------------------+
```


### Deploy Open vSwitch / OVN

Note that we'er not deploying Openvswitch, however, we are using it. The implementation of this POC was
done with Kubespray which deploys OVN as it's networking solution. Because those components are handled
by our infrastructure there's nothing for us to manage / deploy in this environment. OpenStack will
leverage OVN within Kubernetes following the scaling/maintenance/management practices of kube-ovn.


#### Configure OVN for OpenStack

Post deployment we need to setup neutron to work with our integrated OVN environment. To make that work we have to annotate or nodes.

Set the name of the OVS integration bridge we'll use. In general this should be **br-int**.

``` shell
kubectl annotate nodes $(kubectl get nodes -l 'openstack-network-node=enabled' -o 'jsonpath={.items[*].metadata.name}') ovn.openstack.org/int_bridge='br-int'
```

Set the name of the OVS bridges we'll use. These are the bridges you will use on your hosts.

> NOTE The functional example here annotates all nodes; however, not all nodes have to have the same setup.

``` shell
kubectl annotate nodes $(kubectl get nodes -l 'openstack-network-node=enabled' -o 'jsonpath={.items[*].metadata.name}') ovn.openstack.org/bridges='br-ex'
```

Set the bridge mapping. These are colon delimitated between `OVS_BRIDGE:PHYSICAL_INTERFACE_NAME`. Multiple bridge mappings can be defined here and are separated by commas.

``` shell
kubectl annotate nodes $(kubectl get nodes -l 'openstack-network-node=enabled' -o 'jsonpath={.items[*].metadata.name}') ovn.openstack.org/ports='br-ex:bond1'
```

Set the OVN bridge mapping. This maps the Neutron interfaces to the ovs bridge names. These are colon delimitated between `OVS_BRIDGE:PHYSICAL_INTERFACE_NAME`. Multiple bridge mappings can be defined here and are separated by commas.

``` shell
kubectl annotate nodes $(kubectl get nodes -l 'openstack-network-node=enabled' -o 'jsonpath={.items[*].metadata.name}') ovn.openstack.org/mappings='physnet1:br-ex'
```

Set the OVN availability zones. Multiple network availability zones can be defined and are colon separated.

``` shell
kubectl annotate nodes $(kubectl get nodes -l 'openstack-network-node=enabled' -o 'jsonpath={.items[*].metadata.name}') ovn.openstack.org/availability_zones='nova'
```

> Note the "nova" availability zone is an assumed default.

Set the OVN gateway nodes.

``` shell
kubectl annotate nodes $(kubectl get nodes -l 'openstack-network-node=enabled' -o 'jsonpath={.items[*].metadata.name}') ovn.openstack.org/gateway='enabled'
```

> Note while all compute nodes could be a gateway, not all nodes should be a gateway.

With all of the node networks defined, we can now apply the network policy with the following command

``` shell
kubectl --namespace openstack apply -f /opt/flex-rxt/manifests/ovn/ovn-setup.yaml
```

After running the setup, nodes will have the label `ovn.openstack.org/configured` with a date stamp when it was configured.
If there's ever a need to reconfigure a node simply remove the label and the DaemonSet will take care of it automatically.


### Deploy the Compute Kit

The first part of the compute kit is Libvirt.

``` shell
kubectl kustomize --enable-helm /opt/flex-rxt/kustomize/libvirt | kubectl apply --namespace openstack -f -
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

Part of running Nova is also running placement. Setup all credentials now so we can use them across the nova and placement services.

``` shell
# Placement
kubectl --namespace openstack \
        create secret generic placement-db-password \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-32};echo;)"
kubectl --namespace openstack \
        create secret generic placement-admin \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-32};echo;)"
```

``` shell
# Nova
kubectl --namespace openstack \
        create secret generic nova-db-password \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-32};echo;)"
kubectl --namespace openstack \
        create secret generic nova-admin \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-32};echo;)"
kubectl --namespace openstack \
        create secret generic nova-rabbitmq-password \
        --type Opaque \
        --from-literal=username="nova" \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-64};echo;)"
```

``` shell
# Ironic (NOT IMPLEMENTED YET)
kubectl --namespace openstack \
        create secret generic ironic-admin \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-32};echo;)"
```

``` shell
# Designate (NOT IMPLEMENTED YET)
kubectl --namespace openstack \
        create secret generic designate-admin \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-32};echo;)"
```

``` shell
# Neutron
kubectl --namespace openstack \
        create secret generic neutron-rabbitmq-password \
        --type Opaque \
        --from-literal=username="neutron" \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-64};echo;)"
kubectl --namespace openstack \
        create secret generic neutron-db-password \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-32};echo;)"
kubectl --namespace openstack \
        create secret generic neutron-admin \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-32};echo;)"
```

#### Deploy Neutron

``` shell
cd /opt/flex-rxt/submodules/openstack-helm

helm upgrade --install neutron ./neutron \
  --namespace=openstack \
    --timeout 120m \
    -f /opt/flex-rxt/helm-configs/neutron/neutron-helm-overrides.yaml \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.neutron.password="$(kubectl --namespace openstack get secret neutron-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.nova.password="$(kubectl --namespace openstack get secret nova-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.placement.password="$(kubectl --namespace openstack get secret placement-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.designate.password="$(kubectl --namespace openstack get secret designate-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.ironic.password="$(kubectl --namespace openstack get secret ironic-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.neutron.password="$(kubectl --namespace openstack get secret neutron-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.admin.password="$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.neutron.password="$(kubectl --namespace openstack get secret neutron-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set conf.neutron.ovn.ovn_nb_connection="tcp:$(kubectl --namespace kube-system get endpoints ovn-nb -o jsonpath='{.subsets[0].addresses[0].ip}:{.subsets[0].ports[0].port}')" \
    --set conf.neutron.ovn.ovn_sb_connection="tcp:$(kubectl --namespace kube-system get endpoints ovn-sb -o jsonpath='{.subsets[0].addresses[0].ip}:{.subsets[0].ports[0].port}')" \
    --set conf.plugins.ml2_conf.ovn.ovn_nb_connection="tcp:$(kubectl --namespace kube-system get endpoints ovn-nb -o jsonpath='{.subsets[0].addresses[0].ip}:{.subsets[0].ports[0].port}')" \
    --set conf.plugins.ml2_conf.ovn.ovn_sb_connection="tcp:$(kubectl --namespace kube-system get endpoints ovn-sb -o jsonpath='{.subsets[0].addresses[0].ip}:{.subsets[0].ports[0].port}')" \
    --post-renderer /opt/flex-rxt/kustomize/neutron/kustomize.sh
```

> In a production like environment you may need to include production specific files like the example variable file found in
  `helm-configs/prod-example-openstack-overrides.yaml`.

> The above command derives the OVN north/south bound database from our K8S environment. The insert `set` is making the assumption we're using **tcp** to connect.

#### Deploy Nova

``` shell
cd /opt/flex-rxt/submodules/openstack-helm

helm upgrade --install nova ./nova \
  --namespace=openstack \
    --timeout 120m \
    -f /opt/flex-rxt/helm-configs/nova/nova-helm-overrides.yaml \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.nova.password="$(kubectl --namespace openstack get secret nova-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.neutron.password="$(kubectl --namespace openstack get secret neutron-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.ironic.password="$(kubectl --namespace openstack get secret ironic-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.placement.password="$(kubectl --namespace openstack get secret placement-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.cinder.password="$(kubectl --namespace openstack get secret cinder-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.nova.password="$(kubectl --namespace openstack get secret nova-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db_api.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db_api.auth.nova.password="$(kubectl --namespace openstack get secret nova-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db_cell0.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db_cell0.auth.nova.password="$(kubectl --namespace openstack get secret nova-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.admin.password="$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.nova.password="$(kubectl --namespace openstack get secret nova-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)" \
    --post-renderer /opt/flex-rxt/kustomize/nova/kustomize.sh
```

> In a production like environment you may need to include production specific files like the example variable file found in
  `helm-configs/prod-example-openstack-overrides.yaml`.

> NOTE: The above command is setting the ceph as disabled. While the K8S infrastructure has Ceph,
  we're not exposing ceph to our openstack environment.

If running in an environment that doesn't have hardware virtualization extensions add the following two `set` switches to the install command.

``` shell
--set conf.nova.libvirt.virt_type=qemu --set conf.nova.libvirt.cpu_mode=none
```

#### Deploy Placement

``` shell
cd /opt/flex-rxt/submodules/openstack-helm

helm upgrade --install placement ./placement --namespace=openstack \
  --namespace=openstack \
    --timeout 120m \
    -f /opt/flex-rxt/helm-configs/placement/placement-helm-overrides.yaml \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.placement.password="$(kubectl --namespace openstack get secret placement-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.placement.password="$(kubectl --namespace openstack get secret placement-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.nova_api.password="$(kubectl --namespace openstack get secret nova-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --post-renderer /opt/flex-rxt/kustomize/placement/kustomize.sh
```

> In a production like environment you may need to include production specific files like the example variable file found in
  `helm-configs/prod-example-openstack-overrides.yaml`.


### Deploy Horizon

Create secrets.

``` shell
kubectl --namespace openstack \
        create secret generic horizon-secrete-key \
        --type Opaque \
        --from-literal=username="horizon" \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-64};echo;)"
kubectl --namespace openstack \
        create secret generic horizon-db-password \
        --type Opaque \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-32};echo;)"
```

Run the package deployment.

``` shell
cd /opt/flex-rxt/submodules/openstack-helm

helm upgrade --install horizon ./horizon \
    --namespace=openstack \
    --wait \
    --timeout 120m \
    -f /opt/flex-rxt/helm-configs/horizon/horizon-helm-overrides.yaml \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set conf.horizon.local_settings.config.horizon_secret_key="$(kubectl --namespace openstack get secret horizon-secrete-key -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.horizon.password="$(kubectl --namespace openstack get secret horizon-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --post-renderer /opt/flex-rxt/kustomize/horizon/kustomize.sh
```

> In a production like environment you may need to include production specific files like the example variable file found in
  `helm-configs/prod-example-openstack-overrides.yaml`.
