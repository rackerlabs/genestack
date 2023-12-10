# Overview

Evaluating Kubespray in an environment. Deployment will include the following

* Kubernetes
* K-Dashboard
* Kube-OVN
* MetalLB
* Metric Collection

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
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.keystone.password="$(kubectl --namespace openstack get secret keystone-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.admin.password="$(kubectl --namespace rabbitmq-service get secret openstack-default-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.keystone.password="$(kubectl --namespace openstack get secret keystone-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)" \
    $(./tools/deployment/common/get-values-overrides.sh keystone)
```

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
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.glance.password="$(kubectl --namespace openstack get secret glance-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.glance.password="$(kubectl --namespace openstack get secret glance-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.admin.password="$(kubectl --namespace rabbitmq-service get secret openstack-default-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.glance.password="$(kubectl --namespace openstack get secret glance-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)" \
    $(./tools/deployment/common/get-values-overrides.sh glance)
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
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.heat.password="$(kubectl --namespace openstack get secret heat-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.heat_trustee.password="$(kubectl --namespace openstack get secret heat-trustee -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.heat_stack_user.password="$(kubectl --namespace openstack get secret heat-stack-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.heat.password="$(kubectl --namespace openstack get secret heat-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.admin.password="$(kubectl --namespace rabbitmq-service get secret openstack-default-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.heat.password="$(kubectl --namespace openstack get secret heat-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)" \
  $(./tools/deployment/common/get-values-overrides.sh heat)
```

Validate functionality

``` shell
kubectl --namespace openstack  exec -ti openstack-admin-client -- openstack --os-interface internal orchestration service list
```
