# Overview

Evaluating Kubespray in an environment. Deployment will include the following

* Kubernetes
* K-Dashboard
* Kube-OVN
* MetalLB
* Metric Collection
* Deploy OpenStack

## Basic Setup

``` shell
export LC_ALL=C.UTF-8
mkdir .venvs
python3 -m venv .venvs/kubespray
.venvs/kubespray/bin/pip install pip  --upgrade
. .venvs/kubespray/bin/activate
git clone https://github.com/kubernetes-sigs/kubespray kubespray
cd kubespray
pip install -r requirements.txt
```

The inventory defaults are in the root of this repo and can be symlinked into your kubspray environment.

``` shell
cd kubespray/inventory
ln -s ../../openstack-flex
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

``` shell
ansible-playbook -i localhost, infra-deploy.yaml
```

# Deployment

Run the cluster deployment

``` shell
ansible-playbook -i inventory/openstack-flex/inventory.ini -u ubuntu -b cluster.yml
```

Copy the provided scripts to our controller

``` shell
scp -F ~/.ssh/$NETWORK_NAME-keypair.config configs/* ubuntu@$NODE_IP:/tmp/
```


Login to the first controller node in the infrastructure to begin the OSH deployment

``` shell
ssh -F ~/.ssh/$NETWORK_NAME-keypair.config ubuntu@$NODE_IP
```

While the dashboard is installed you will have no ability to access it until we setup some basic RBAC.

``` shell
kubectl apply -f /tmp/dashboard-rbac-default.yaml
```

You can now retrieve a permenant token.

``` shell
kubectl get secret admin-user -n kube-system -o jsonpath={".data.token"} | base64 -d
```

Install some base packages needed by OSH

``` shell
apt update
apt install jq make -y
```

Install the OSH repos the first infra node in our cluster.

``` shell
mkdir ~/osh
cd ~/osh
git clone https://opendev.org/openstack/openstack-helm.git
git clone https://opendev.org/openstack/openstack-helm-infra.git
git clone https://github.com/rook/rook.git
git clone https://github.com/mariadb-operator/mariadb-operator
```

#### Install the cert-manager

``` shell
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/latest/cert-manager.yaml
```

#### Install rook operator

``` shell
# Deploy the cluster, before we can deploy the cluster we need to setup the nodes and its devices.
# get a list of nodes that will participate in our cluster. If using the infra-deploy playbook,
# this will be the last three nodes in the cluster.
kubectl get nodes -o wide

# Label our storage nodes
kubectl label node openstack-flex-node-6 openstack-flex-node-7 openstack-flex-node-8 role=storage-node

# Deploy rook
cd ~/osh/rook/deploy/examples
kubectl create -f crds.yaml
kubectl create -f common.yaml
kubectl create -f operator.yaml

# Deploy our ceph cluster
kubectl create -f /tmp/rook-cluster.yaml

# Deploy our ceph toolbox
kubectl apply -f toolbox.yaml

# Create our cephfs filesystem
kubectl create -f filesystem.yaml

# Create our cephfs storage classes
kubectl create -f csi/cephfs/storageclass.yaml

# Create our rbd store classes
kubectl create -f csi/rbd/storageclass.yaml

# Create our general (rbd) store classes, which is marked default.
kubectl create -f /tmp/storageclass-general.yaml

# Wait for everything to be created. It can take a minute or two.
kubectl --namespace rook-ceph get pods -w
```

Label all of the nodes in the environment.

``` shell
# Label the openstack controllers
kubectl label node $(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o 'jsonpath={.items[*].metadata.name}') openstack-control-plane=enabled

# Label control-plane nodes as L3 agent enabled
kubectl label node $(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o 'jsonpath={.items[*].metadata.name}') l3-agent=enabled

# Label the compute nodes
kubectl label node $(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o 'jsonpath={.items[*].metadata.name}') openstack-compute-node=enabled

# Enable Openvswitch
kubectl label node $(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o 'jsonpath={.items[*].metadata.name}') openvswitch=enabled

# Disable Linuxbridge
kubectl label nodes --all linuxbridge=disabled

# Label all nodes as workers
kubectl label nodes $(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o 'jsonpath={.items[*].metadata.name}') node-role.kubernetes.io/worker=worker

# Verify the nodes are operational and labled.
kubectl get nodes -o wide
```

Create our basic openstack namespace

``` shell
kubectl apply -f /tmp/ns-openstack.yaml
```

#### Install mariadb

``` shell
# Deploy the operator
helm repo add mariadb-operator https://mariadb-operator.github.io/mariadb-operator
helm install mariadb-operator mariadb-operator/mariadb-operator --set webhook.cert.certManager.enabled=true --wait --namespace openstack

# Install our configuration and management capabilities
cd ~/osh/mariadb-operator
kubectl apply --namespace openstack -f examples/manifests/config/mariabackup-pvc.yaml
kubectl apply --namespace openstack -f examples/manifests/config/mariadb-configmap.yaml
kubectl apply --namespace openstack -f examples/manifests/config/mariadb-my-cnf-configmap.yaml

# Create secret
kubectl --namespace openstack \
        create secret generic mariadb \
        --type Opaque \
        --from-literal=root-password="$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-32};echo;)" \
        --from-literal=password="$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-32};echo;)"

# Deploy the mariadb cluster
kubectl apply --namespace openstack -f /tmp/mariadb-galera.yaml

# Verify readiness with the following command
kubectl --namespace openstack get mariadbs
```

#### Install RabbitMQ

``` shell
# Install rabbitmq
kubectl apply -f https://github.com/rabbitmq/cluster-operator/releases/latest/download/cluster-operator.yml
kubectl apply -f https://github.com/rabbitmq/messaging-topology-operator/releases/latest/download/messaging-topology-operator-with-certmanager.yaml
kubectl apply -f /tmp/rabbitmq-cluster.yaml
```

#### Install memcached

``` shell
helm install memcached oci://registry-1.docker.io/bitnamicharts/memcached \
                        --set architecture="high-availability" \
                        --set autoscaling.enabled="true" \
                        --namespace openstack \
                        --wait
```

Now that the backend is all deployed, time to deploy openstack.

#### Setup OSH and make everything

``` shell
# Export OSH variables
export CONTAINER_DISTRO_NAME=ubuntu
export CONTAINER_DISTRO_VERSION=jammy
export OPENSTACK_RELEASE=2023.1
export OSH_DEPLOY_MULTINODE=True

# Run make for everything.
cd ~/osh/openstack-helm
make all

cd ~/osh/openstack-helm-infra
make all
```

#### Deploy the ingress controllers

``` shell
cd ~/osh/openstack-helm-infra

# First the global controller
helm upgrade --install ingress-kube-system ./ingress \
  --namespace=kube-system \
  --wait \
  --timeout 900s \
  --values=/tmp/ingress-kube-system.yaml \
  $(./tools/deployment/common/get-values-overrides.sh ingress)

# Second the component openstack controller
helm upgrade --install ingress-openstack ./ingress \
  --namespace=openstack \
  --wait \
  --timeout 900s \
  --values=/tmp/ingress-component.yaml \
  --set deployment.cluster.class=nginx \
  $(./tools/deployment/common/get-values-overrides.sh ingress)
```

#### Deploy Keystone

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

kubectl apply -f /tmp/keystone-mariadb-database.yaml

kubectl apply -f /tmp/keystone-rabbitmq-queue.yaml

cd ~/osh/openstack-helm

helm upgrade --install keystone ./keystone \
    --namespace=openstack \
    --wait \
    --timeout 900s \
    -f /tmp/keystone-helm-overrides.yaml \
    $(./tools/deployment/common/get-values-overrides.sh keystone) \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.keystone.password="$(kubectl --namespace openstack get secret keystone-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.admin.password="$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.keystone.password="$(kubectl --namespace openstack get secret keystone-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set images.tags.keystone_db_sync="ghcr.io/cloudnull/keystone-rxt:${OPENSTACK_RELEASE}-ubuntu_jammy" \
    --set images.tags.keystone_fernet_setup="ghcr.io/cloudnull/keystone-rxt:${OPENSTACK_RELEASE}-ubuntu_jammy" \
    --set images.tags.keystone_fernet_rotate="ghcr.io/cloudnull/keystone-rxt:${OPENSTACK_RELEASE}-ubuntu_jammy" \
    --set images.tags.keystone_credential_setup="ghcr.io/cloudnull/keystone-rxt:${OPENSTACK_RELEASE}-ubuntu_jammy" \
    --set images.tags.keystone_credential_rotate="ghcr.io/cloudnull/keystone-rxt:${OPENSTACK_RELEASE}-ubuntu_jammy" \
    --set images.tags.keystone_api="ghcr.io/cloudnull/keystone-rxt:${OPENSTACK_RELEASE}-ubuntu_jammy"
```

> NOTE: The image used here allows the system to run with RXT global authentication federation.
  The federated plugin can be seen here, https://github.com/cloudnull/keystone-rxt

Deploy the openstack admin client pod (optional)

``` shell
kubectl --namespace openstack apply -f /tmp/utils-openstack-client-admin.yaml
```

Validate functionality

``` shell
kubectl --namespace openstack  exec -ti openstack-admin-client -- openstack user list
```


#### Deploy Glance

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

kubectl apply -f /tmp/glance-mariadb-database.yaml

kubectl apply -f /tmp/glance-rabbitmq-queue.yaml

helm upgrade --install glance ./glance \
    --namespace=openstack \
    --wait \
    --timeout 900s \
    -f /tmp/glance-helm-overrides.yaml \
    $(./tools/deployment/common/get-values-overrides.sh glance) \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.glance.password="$(kubectl --namespace openstack get secret glance-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.glance.password="$(kubectl --namespace openstack get secret glance-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.admin.password="$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.glance.password="$(kubectl --namespace openstack get secret glance-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)"
```

> Note that the defaults disable `storage_init` because we're using **pvc** as the image backend
  type. In production this should be changed to swift.

Validate functionality

``` shell
kubectl --namespace openstack  exec -ti openstack-admin-client -- openstack image list
```

#### Deploy Heat

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

kubectl apply -f /tmp/heat-mariadb-database.yaml

kubectl apply -f /tmp/heat-rabbitmq-queue.yaml

helm upgrade --install heat ./heat \
  --namespace=openstack \
    --wait \
    --timeout 900s \
    -f /tmp/heat-helm-overrides.yaml \
    $(./tools/deployment/common/get-values-overrides.sh heat) \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.heat.password="$(kubectl --namespace openstack get secret heat-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.heat_trustee.password="$(kubectl --namespace openstack get secret heat-trustee -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.heat_stack_user.password="$(kubectl --namespace openstack get secret heat-stack-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.heat.password="$(kubectl --namespace openstack get secret heat-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.admin.password="$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.heat.password="$(kubectl --namespace openstack get secret heat-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)"
```

Validate functionality

``` shell
kubectl --namespace openstack  exec -ti openstack-admin-client -- openstack --os-interface internal orchestration service list
```

#### Deploy Cinder

Before we build our storage environment, make sure to label the storage nodes.

``` shell
kubectl label node openstack-flex-node-3 openstack-storage-node=enabled
```


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

kubectl apply -f /tmp/cinder-mariadb-database.yaml

kubectl apply -f /tmp/cinder-rabbitmq-queue.yaml

helm upgrade --install cinder ./cinder \
  --namespace=openstack \
    --wait \
    --timeout 900s \
    -f /tmp/cinder-helm-overrides.yaml \
    $(./tools/deployment/common/get-values-overrides.sh cinder) \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.cinder.password="$(kubectl --namespace openstack get secret cinder-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.cinder.password="$(kubectl --namespace openstack get secret cinder-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.admin.password="$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.cinder.password="$(kubectl --namespace openstack get secret cinder-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)"
```

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
apt install build-essential python3-venv python3-dev
python3 -m venv /opt/cinder
/opt/cinder/bin/pip install pip pymysql --upgrade
/opt/cinder/bin/pip install git+https://github.com/openstack/cinder@stable/2023.1
```

``` shell
/opt/cinder/bin/cinder-volume --config-file /etc/cinder/cinder.conf --config-file /etc/cinder/conf/backends.conf --config-file /etc/cinder/internal_tenant.conf
```

After this deployment has completed the volume service will be operational, which we can see with the following command.

``` shell
kubectl --namespace openstack  exec -ti openstack-admin-client -- openstack volume service list
```

Now we can create the volume type to ensure we're able to deploy volumes with our volume driver.

``` shell
kubectl --namespace openstack  exec -ti openstack-admin-client -- openstack volume type set --public lvmdriver-1
```

Verify functionality by creating a volume

``` shell
kubectl --namespace openstack  exec -ti openstack-admin-client -- openstack volume create --size 1 test-lvm
kubectl --namespace openstack  exec -ti openstack-admin-client -- openstack volume show test-lvm
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
