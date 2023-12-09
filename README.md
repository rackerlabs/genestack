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
```

Install rook

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

Setup OSH and make everything

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

# Generate required namespaces
kubectl apply -f /tmp/ns-openstack.yaml
kubectl apply -f /tmp/ns-osh-infra.yaml

# Run all namespace configurations
cd ~/osh/openstack-helm-infra

for NAMESPACE in kube-system openstack; do
  helm upgrade --install ${NAMESPACE}-namespace-config ./namespace-config \
    --wait \
    --timeout 900s \
    --namespace=${NAMESPACE}
done

# Deploy ingress
cd ~/osh/openstack-helm-infra

# Deploy namespace ingress-kube-system
helm upgrade --install ingress-kube-system ./ingress \
  --namespace=kube-system \
  --wait \
  --timeout 900s \
  --values=/tmp/ingress-kube-system.yaml \
  ${OSH_EXTRA_HELM_ARGS} \
  ${OSH_EXTRA_HELM_ARGS_INGRESS:="$(./tools/deployment/common/get-values-overrides.sh ingress)"} \
  ${OSH_EXTRA_HELM_ARGS_INGRESS_KUBE_SYSTEM}

# Deploy namespace ingress-openstack
helm upgrade --install ingress-openstack ./ingress \
  --namespace=openstack \
  --wait \
  --timeout 900s \
  --values=/tmp/ingress-component.yaml \
  --set deployment.cluster.class=nginx \
  ${OSH_EXTRA_HELM_ARGS} \
  ${OSH_EXTRA_HELM_ARGS_INGRESS:="$(./tools/deployment/common/get-values-overrides.sh ingress)"} \
  ${OSH_EXTRA_HELM_ARGS_INGRESS_OPENSTACK}

helm upgrade --install ingress-rook-ceph ./ingress \
  --namespace=rook-ceph \
  --wait \
  --timeout 900s \
  --values=/tmp/ingress-component.yaml \
  --set deployment.cluster.class=nginx-ceph \
  ${OSH_EXTRA_HELM_ARGS} \
  ${OSH_EXTRA_HELM_ARGS_INGRESS:="$(./tools/deployment/common/get-values-overrides.sh ingress)"} \
  ${OSH_EXTRA_HELM_ARGS_INGRESS_CEPH}
```

Install backends

``` shell
cd ~/osh/openstack-helm-infra

# Install rabbitmq
helm upgrade --install rabbitmq ./rabbitmq \
    --namespace=openstack \
    --set volume.enabled=false \
    --set pod.replicas.server=1 \
    ${OSH_EXTRA_HELM_ARGS:=} \
    ${OSH_EXTRA_HELM_ARGS_RABBITMQ:="$(./tools/deployment/common/get-values-overrides.sh rabbitmq)"}

kubectl apply --namespace openstack -f https://github.com/rabbitmq/cluster-operator/releases/latest/download/cluster-operator.yml
kubectl apply --namespace openstack -f /tmp/rabbitmq.yaml
kubectl apply --namespace openstack -f /tmp/rabbitmq-pod-disruption-budget.yaml
kubectl apply --namespace openstack -f /tmp/rabbitmq-allow-inter-node-traffic.yaml
kubectl apply --namespace openstack -f /tmp/rabbitmq-allow-operator-traffic.yaml
kubectl apply --namespace openstack -f /tmp/rabbitmq-allow-rabbitmq-traffic.yaml

# Install mariadb
helm upgrade --install mariadb ./mariadb \
    --namespace=openstack \
    --wait \
    --timeout 900s \
    --set volume.enabled=true \
    --set pod.replicas.server=1 \
    ${OSH_EXTRA_HELM_ARGS:=} \
    ${OSH_INFRA_EXTRA_HELM_ARGS_MARIADB_CLUSTER:="$(./tools/deployment/common/get-values-overrides.sh mariadb)"}

# Install memcached
helm upgrade --install memcached ./memcached \
    --namespace=openstack \
    --wait \
    --timeout 900s \
    --set volume.enabled=true \
    ${OSH_EXTRA_HELM_ARGS:=} \
    ${OSH_EXTRA_HELM_ARGS_MEMCACHED:="$(./tools/deployment/common/get-values-overrides.sh memcached)"}
```

Now that the backend is all deployed, time to deploy openstack.

First deploy Keystone

``` shell
cd ~/osh/openstack-helm

helm upgrade --install keystone ./keystone \
    --namespace=openstack \
    --wait \
    --timeout 900s \
    ${OSH_EXTRA_HELM_ARGS:=} \
    ${OSH_EXTRA_HELM_ARGS_KEYSTONE:="$(./tools/deployment/common/get-values-overrides.sh keystone)"}
```
