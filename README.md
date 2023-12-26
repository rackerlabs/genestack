![Genestack](assets/images/genestack.png)

# Welcome to Genestack: Where Cloud Meets You

Genestack — where Kubernetes and OpenStack tango in the cloud. Imagine a waltz between systems that deploy
what you need.


## Unveiling Genestack's Marvels

* Kubernetes:
    * Kube-OVN: The silent but reliable partner
    * K-Dashboard: Always there to take the lead
    * MetalLB: Adds the metallic charm
    * CoreDNS: The system’s melodious voice
    * Ingress-NGINX: Controls the flow, just like a boss
    * Cert-Manager: The permit distributor

* Operators:
    * MariaDB: The data maestro
    * RabbitMQ: Always 'hopping' around to deliver messages
    * Rook (Optional): The magician handling storage tricks
    * Memcached: Memory’s best friend

* OpenStack:
    * Cinder: Solid as a rock
    * Glance: Giving you the perfect 'glance' to an image
    * Heat: Adds the heat when things get chilly
    * Horizon: The futuristic seer
    * Keystone: The cornerstone of identity
    * Neutron: Always attracting the right connections
    * Nova: The cosmic powerhouse
    * Placement: Ensuring everything finds its place


### Symphony of Simplicity

Genestack conducts this orchestra of tech with style. Operators play the score, managing the complexity with
a flick of their digital batons. They unify the chaos, making scaling and management a piece of cake. Think
of it like a conductor effortlessly guiding a cacophony into a symphony.


### Hybrid Hilarity

Our hybrid capabilities aren’t your regular circus act. Picture a shared OVN fabric — a communal network
where workers multitask like pros. Whether it’s computing, storing, or networking, they wear multiple
hats in a hyperconverged circus or a grand full-scale enterprise cloud extravaganza.


### The Secret Sauce: Kustomize & Helm

Genestack’s inner workings are a blend dark magic — crafted with [Kustomize](https://kustomize.io) and
[Helm](https://helm.sh). It’s like cooking with cloud. Want to spice things up? Tweak the
`kustomization.yaml` files or add those extra 'toppings' using Helm's style overrides. However, the
platform is ready to go with batteries included.

Genestack is making use of some homegrown solutions, community operators, and OpenStack-Helm. Everything
in Genestack comes together to form cloud in a new and exciting way; all built with opensource solutions
to manage cloud infrastructure in the way you need it.

#### Dependencies

Yes there are dependencies. This project is made up of several submodules which are the component
architecture of the Genestack ecosystem.

* Kubespray: The bit delivery mechanism for Kubernetes. While we're using Kubespray to deliver a production
  grade Kubernetes baremetal solution, we don't really care how Kubernetes gets there.
* MariaDB-Operator: Used to deliver MariaBD clusters
* OpenStack-Helm: The helm charts used to create an OpenStack cluster.
* OpenStack-Helm-Infra: The helm charts used to create infrastructure components for OpenStack.
* Rook: The Ceph storage solution du jour. This is optional component and only needed to manage Ceph
  when you want Ceph.

### Environment Architecture

They say a picture is worth 1000 words, so here's a picture.

![Genestack Architecture Diagram](assets/images/diagram-genestack.svg)

----

## Get the code

Because we've sold our soul to the submodule devil you're going to need to recursively clone the repo.

``` shell
git clone --recurse-submodules -j4 https://github.com/cloudnull/genestack /opt/genestack
```


## Basic Setup

Install some base packages needed by OSH

``` shell
apt update
apt install jq make python3-venv -y
```

The basic setup is using venv, make sure you have the required packages installed to facilitate that need.

``` shell
export LC_ALL=C.UTF-8
mkdir ~/.venvs
python3 -m venv ~/.venvs/kubespray
.venvs/kubespray/bin/pip install pip  --upgrade
source ~/.venvs/kubespray/bin/activate
pip install -r /opt/genestack/submodules/kubespray/requirements.txt
```

The inventory defaults are in the root of this repo and can be symlinked into your kubspray environment.

``` shell
cd /opt/genestack/submodules/kubespray/inventory
ln -s /opt/genestack/openstack-flex
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

The test infrastructure will create the following OpenStack resources

* Neutron Network/Subnet
  * Assign a floating IP
* Cinder Volumes
* Nova Servers


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
cd /opt/genestack/submodules/kubespray
ansible-playbook -i inventory/openstack-flex/inventory.ini -u ubuntu -b cluster.yml
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
cd /opt/genestack/submodules/openstack-helm
make all

cd /opt/genestack/submodules/openstack-helm-infra
make all
```


## Ensure the kube dashboard is setup

While the dashboard is installed you will have no ability to access it until we setup some basic RBAC.

``` shell
kubectl apply -f /opt/genestack/manifests/k8s/dashboard-rbac-default.yaml
```

You can now retrieve a permenant token.

``` shell
kubectl get secret admin-user -n kube-system -o jsonpath={".data.token"} | base64 -d
```

Label all of the nodes in the environment.

> The following example assumes the node names can be used to identify their purpose within our environment. That
  may not be the case in reality. Adapt the following commands to meet your needs.

``` shell
# Label the storage nodes
kubectl label node $(kubectl get nodes | awk '/storage/ {print $1}') role=storage-node

# Label the openstack controllers
kubectl label node $(kubectl get nodes -l 'node-role.kubernetes.io/control-plane' -o 'jsonpath={.items[*].metadata.name}') openstack-control-plane=enabled

# Label the compute nodes
kubectl label node $(kubectl get nodes | awk '/compute/ {print $1}') openstack-compute-node=enabled

# Label the network nodes
kubectl label node $(kubectl get nodes | awk '/network/ {print $1}') openstack-network-node=enabled

# With OVN we need the compute nodes to be "network" nodes as well. While they will be configured for networking, they wont be gateways.
kubectl label node $(kubectl get nodes | awk '/compute/ {print $1}') openstack-network-node=enabled

# Label control-plane nodes as workers
kubectl label node $(kubectl get nodes -l 'node-role.kubernetes.io/control-plane' -o 'jsonpath={.items[*].metadata.name}') node-role.kubernetes.io/worker=worker
```

Check the node labels

``` shell
# Verify the nodes are operational and labled.
kubectl get nodes -o wide
```


### Optional - Remove taint from our Controllers

In an environment with a limited set of control plane nodes removing the NoSchedule will allow you to converge the
openstack controllers with the k8s controllers.

``` shell
# Remote taint from control-plane nodes
kubectl taint nodes $(kubectl get nodes -o 'jsonpath={.items[*].metadata.name}') node-role.kubernetes.io/control-plane:NoSchedule-
```

Create our basic openstack namespace

``` shell
kubectl apply -f /opt/genestack/manifests/openstack/ns-openstack.yaml
```


## Create Persistent Storage

For the basic needs of our Kubernetes environment, we need some basic persistent storage. By default
we're running with Ceph, via Rook. However, storage is a choose your own adventure ecosystem, so feel
free to ignore this section if you have something else that satisfies the need.


### Deploy Rook

Deploy the Rook operator

``` shell
kubectl apply -k /opt/genestack/kustomize/rook-operator/
```

Rook will deploy against nodes labeled `role=storage-node`. Make sure to have a look at the `kustomize/rook/rook-cluster.yaml` file to ensure it's setup to your liking, pay special attention to your `deviceFilter`
settings, especially if different devices have different device layouts.

``` shell
kubectl apply -k /opt/genestack/kustomize/rook-cluster/
```

Validate the cluster is operational

``` shell
kubectl --namespace rook-ceph get cephclusters.ceph.rook.io
```

> You can track the deployment with the following command `kubectl --namespace rook-ceph get pods -w`.

Once the rook cluster is online with a HEALTH status of `HEALTH_OK`, deploy the filesystem, storage-class, and pool defaults.

``` shell
kubectl apply -k /opt/genestack/kustomize/rook-defaults
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

Deploy the mariadb config defaults.

``` shell
kubectl --namespace openstack apply -k /opt/genestack/kustomize/mariadb-defaults
```

Deploy the mariadb operator.

``` shell
kubectl kustomize --enable-helm /opt/genestack/kustomize/mariadb-operator | kubectl apply --namespace openstack -f -
```

Now deploy the MariaDB Cluster

``` shell
kubectl --namespace openstack apply -k /opt/genestack/kustomize/mariadb-cluster
```

Verify readiness with the following command.

``` shell
kubectl --namespace openstack get mariadbs -w
```


## Install RabbitMQ

Deploy the RabbitMQ operator.

``` shell
kubectl apply -k /opt/genestack/kustomize/rabbitmq-operator
```

Deploy the RabbitMQ topology operator.

``` shell
kubectl apply -k /opt/genestack/kustomize/rabbitmq-topology-operator
```

Deploy the RabbitMQ cluster.

``` shell
kubectl apply -k /opt/genestack/kustomize/rabbitmq-cluster
```

Validate the status with the following

``` shell
kubectl --namespace openstack get rabbitmqclusters.rabbitmq.com -w
```


## Install memcached

``` shell
kubectl kustomize --enable-helm /opt/genestack/kustomize/memcached | kubectl apply --namespace openstack -f -
```

Verify readiness with the following command.

``` shell
kubectl --namespace openstack get horizontalpodautoscaler.autoscaling memcached -w
```


## Deploy the ingress controllers

``` shell
kubectl kustomize --enable-helm /opt/genestack/kustomize/ingress | kubectl apply --namespace openstack -f -
```


## Setup the MetalLB Loadbalancer

The MetalLb loadbalancer can be setup by editing the following file `metallb-openstack-service-lb.yml`, You will need to add
your "external" VIPs to the loadbalancer so that they can be used within services. These IP addresses are unique and will
need to be customized to meet the needs of your environment.

#### Example

``` shell
kubectl apply -f /opt/genestack/manifests/metallb/metallb-openstack-service-lb.yml
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
cd /opt/genestack/submodules/openstack-helm

helm upgrade --install keystone ./keystone \
    --namespace=openstack \
    --wait \
    --timeout 120m \
    -f /opt/genestack/helm-configs/keystone/keystone-helm-overrides.yaml \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.keystone.password="$(kubectl --namespace openstack get secret keystone-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.admin.password="$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.keystone.password="$(kubectl --namespace openstack get secret keystone-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)" \
    --post-renderer /opt/genestack/kustomize/keystone/kustomize.sh
```

> In a production like environment you may need to include production specific files like the example variable file found in
  `helm-configs/prod-example-openstack-overrides.yaml`.

> NOTE: The image used here allows the system to run with RXT global authentication federation.
  The federated plugin can be seen here, https://github.com/cloudnull/keystone-rxt

Deploy the openstack admin client pod (optional)

``` shell
kubectl --namespace openstack apply -f /opt/genestack/manifests/utils/utils-openstack-client-admin.yaml
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

> Before running the Glance deployment you should configure the backend which is defined in the
  `helm-configs/glance/glance-helm-overrides.yaml` file. The default is a making the assumption we're running with Ceph deployed by
  Rook so the backend is configured to be cephfs with multi-attach functionality. While this works great, you should consider all of
  the available storage backends and make the right decision for your environment.

Run the package deployment.

``` shell
cd /opt/genestack/submodules/openstack-helm

helm upgrade --install glance ./glance \
    --namespace=openstack \
    --wait \
    --timeout 120m \
    -f /opt/genestack/helm-configs/glance/glance-helm-overrides.yaml \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.glance.password="$(kubectl --namespace openstack get secret glance-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.glance.password="$(kubectl --namespace openstack get secret glance-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.admin.password="$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.glance.password="$(kubectl --namespace openstack get secret glance-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)" \
    --post-renderer /opt/genestack/kustomize/glance/kustomize.sh
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
cd /opt/genestack/submodules/openstack-helm

helm upgrade --install heat ./heat \
  --namespace=openstack \
    --timeout 120m \
    -f /opt/genestack/helm-configs/heat/heat-helm-overrides.yaml \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.heat.password="$(kubectl --namespace openstack get secret heat-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.heat_trustee.password="$(kubectl --namespace openstack get secret heat-trustee -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.heat_stack_user.password="$(kubectl --namespace openstack get secret heat-stack-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.heat.password="$(kubectl --namespace openstack get secret heat-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.admin.password="$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.heat.password="$(kubectl --namespace openstack get secret heat-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)" \
    --post-renderer /opt/genestack/kustomize/heat/kustomize.sh
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
cd /opt/genestack/submodules/openstack-helm

helm upgrade --install cinder ./cinder \
  --namespace=openstack \
    --wait \
    --timeout 120m \
    -f /opt/genestack/helm-configs/cinder/cinder-helm-overrides.yaml \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.cinder.password="$(kubectl --namespace openstack get secret cinder-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.cinder.password="$(kubectl --namespace openstack get secret cinder-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.admin.password="$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.cinder.password="$(kubectl --namespace openstack get secret cinder-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)" \
    --post-renderer /opt/genestack/kustomize/cinder/kustomize.sh
```

> In a production like environment you may need to include production specific files like the example variable file found in
  `helm-configs/prod-example-openstack-overrides.yaml`.

Once the helm deployment is complete cinder and all of it's API services will be online. However, using this setup there will be
no volume node at this point. The reason volume deployments have been disabled is because we didn't expose ceph to the openstack
environment and OSH makes a lot of ceph related assumptions. For testing purposes we're wanting to run with the logical volume
driver (reference) and manage the deployment of that driver in a hybrid way. As such there's a deployment outside of our normal
K8S workflow will be needed on our volume host.

> The LVM volume makes the assumption that the storage node has the required volume group setup `lvmdriver-1` on the node
  This is not something that K8S is handling at this time.

While cinder can run with a great many different storage backends, for the simple case we want to run with the Cinder reference
driver, which makes use of Logical Volumes. Because this driver is incompatible with a containerized work environment, we need
to run the services on our baremetal targets. Genestack has a playbook which will facilitate the installation of our services
and ensure that we've deployed everything in a working order. The playbook can be found at `playbooks/deploy-cinder-volumes-reference.yaml`.
Included in the playbooks directory is an example inventory for our cinder hosts; however, any inventory should work fine.

#### Host Setup

The cinder target hosts need to have some basic setup run on them to make them compatible with our Logical Volume Driver.

1. Ensure DNS is working normally.

Assuming your storage node was also deployed as a K8S node when we did our initial Kubernetes deployment, the DNS should already be
operational for you; however, in the event you need to do some manual tweaking or if the node was note deployed as a K8S worker, then
make sure you setup the DNS resolvers correctly so that your volume service node can communicate with our cluster.

> This is expected to be our CoreDNS IP, in my case this is `169.254.25.10`.

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

2. Volume Group `lvmdriver-1` needs to be created which can be done in two simple commands.

Create the physical volume

``` shell
pvcreate /dev/vdf
```

Create the volume group

``` shell
vgcreate lvmdriver-1 /dev/vdf
```

It shoold be noted that this setup can be tweaked and tuned to your hearts desire, additionally, you can further extend a
volume group with multiple disks. The example above is just that, an example. Checkout more from the upstream docs on how
to best operate your volume groups for your specific needs.

#### Hybrid Cinder Volume deployment

With the volume groups and DNS setup on your target hosts, it is now time to deploy the volume services. The playbook `playbooks/deploy-cinder-volumes-reference.yaml` will be used to create a release target for our python code-base and deploy systemd services
units to run the cinder-volume process.

``` shell
ansible-playbook -i inventory-example.yaml deploy-cinder-volumes-reference.yaml
```

Once the playbook has finished executing, check the cinder api to verify functionality.

``` shell
root@openstack-flex-node-0:~# kubectl --namespace openstack exec -ti openstack-admin-client -- openstack volume service list
+------------------+-------------------------------------------------+------+---------+-------+----------------------------+
| Binary           | Host                                            | Zone | Status  | State | Updated At                 |
+------------------+-------------------------------------------------+------+---------+-------+----------------------------+
| cinder-scheduler | cinder-volume-worker                            | nova | enabled | up    | 2023-12-26T17:43:07.000000 |
| cinder-volume    | openstack-flex-node-4.cluster.local@lvmdriver-1 | nova | enabled | up    | 2023-12-26T17:43:04.000000 |
+------------------+-------------------------------------------------+------+---------+-------+----------------------------+
```

> Notice the volume service is up and running with our `lvmdriver-1` target.

At this point it would be a good time to define your types within cinder. For our example purposes we need to define the `lvmdriver-1`
type so that we can schedule volumes to our environment.

``` shell
root@openstack-flex-node-0:~# kubectl --namespace openstack exec -ti openstack-admin-client -- openstack volume type create lvmdriver-1
+-------------+--------------------------------------+
| Field       | Value                                |
+-------------+--------------------------------------+
| description | None                                 |
| id          | 6af6ade2-53ca-4260-8b79-1ba2f208c91d |
| is_public   | True                                 |
| name        | lvmdriver-1                          |
+-------------+--------------------------------------+
```

If wanted, create a test volume to tinker with

``` shell
root@openstack-flex-node-0:~# kubectl --namespace openstack exec -ti openstack-admin-client -- openstack volume create --size 1 test
+---------------------+--------------------------------------+
| Field               | Value                                |
+---------------------+--------------------------------------+
| attachments         | []                                   |
| availability_zone   | nova                                 |
| bootable            | false                                |
| consistencygroup_id | None                                 |
| created_at          | 2023-12-26T17:46:15.639697           |
| description         | None                                 |
| encrypted           | False                                |
| id                  | c744af27-fb40-4ffa-8a84-b9f44cb19b2b |
| migration_status    | None                                 |
| multiattach         | False                                |
| name                | test                                 |
| properties          |                                      |
| replication_status  | None                                 |
| size                | 1                                    |
| snapshot_id         | None                                 |
| source_volid        | None                                 |
| status              | creating                             |
| type                | lvmdriver-1                          |
| updated_at          | None                                 |
| user_id             | 2ddf90575e1846368253474789964074     |
+---------------------+--------------------------------------+

root@openstack-flex-node-0:~# kubectl --namespace openstack exec -ti openstack-admin-client -- openstack volume list
+--------------------------------------+------+-----------+------+-------------+
| ID                                   | Name | Status    | Size | Attached to |
+--------------------------------------+------+-----------+------+-------------+
| c744af27-fb40-4ffa-8a84-b9f44cb19b2b | test | available |    1 |             |
+--------------------------------------+------+-----------+------+-------------+
```

You can validate the environment is operational by logging into the storage nodes to validate the LVM targets are being created.

``` shell
root@openstack-flex-node-4:~# lvs
  LV                                   VG               Attr       LSize Pool Origin Data%  Meta%  Move Log Cpy%Sync Convert
  c744af27-fb40-4ffa-8a84-b9f44cb19b2b cinder-volumes-1 -wi-a----- 1.00g
```

### Deploy Open vSwitch / OVN

Note that we'er not deploying Openvswitch, however, we are using it. The implementation on Genestack is assumed to be
done with Kubespray which deploys OVN as it's networking solution. Because those components are handled by our infrastructure
there's nothing for us to manage / deploy in this environment. OpenStack will leverage OVN within Kubernetes following the
scaling/maintenance/management practices of kube-ovn.


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
kubectl --namespace openstack apply -f /opt/genestack/manifests/ovn/ovn-setup.yaml
```

After running the setup, nodes will have the label `ovn.openstack.org/configured` with a date stamp when it was configured.
If there's ever a need to reconfigure a node simply remove the label and the DaemonSet will take care of it automatically.


### Deploy the Compute Kit

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
cd /opt/genestack/submodules/openstack-helm

helm upgrade --install neutron ./neutron \
  --namespace=openstack \
    --timeout 120m \
    -f /opt/genestack/helm-configs/neutron/neutron-helm-overrides.yaml \
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
    --post-renderer /opt/genestack/kustomize/neutron/kustomize.sh
```

> In a production like environment you may need to include production specific files like the example variable file found in
  `helm-configs/prod-example-openstack-overrides.yaml`.

> The above command derives the OVN north/south bound database from our K8S environment. The insert `set` is making the assumption we're using **tcp** to connect.

#### Deploy Nova

``` shell
cd /opt/genestack/submodules/openstack-helm

helm upgrade --install nova ./nova \
  --namespace=openstack \
    --timeout 120m \
    -f /opt/genestack/helm-configs/nova/nova-helm-overrides.yaml \
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
    --post-renderer /opt/genestack/kustomize/nova/kustomize.sh
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
cd /opt/genestack/submodules/openstack-helm

helm upgrade --install placement ./placement --namespace=openstack \
  --namespace=openstack \
    --timeout 120m \
    -f /opt/genestack/helm-configs/placement/placement-helm-overrides.yaml \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.placement.password="$(kubectl --namespace openstack get secret placement-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.placement.password="$(kubectl --namespace openstack get secret placement-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.nova_api.password="$(kubectl --namespace openstack get secret nova-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --post-renderer /opt/genestack/kustomize/placement/kustomize.sh
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
cd /opt/genestack/submodules/openstack-helm

helm upgrade --install horizon ./horizon \
    --namespace=openstack \
    --wait \
    --timeout 120m \
    -f /opt/genestack/helm-configs/horizon/horizon-helm-overrides.yaml \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set conf.horizon.local_settings.config.horizon_secret_key="$(kubectl --namespace openstack get secret horizon-secrete-key -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.horizon.password="$(kubectl --namespace openstack get secret horizon-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --post-renderer /opt/genestack/kustomize/horizon/kustomize.sh
```

> In a production like environment you may need to include production specific files like the example variable file found in
  `helm-configs/prod-example-openstack-overrides.yaml`.
