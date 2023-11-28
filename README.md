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

While the dashboard is installed you will have no ability to access it until we setup some basic RBAC.

``` shell
kubectl apply -f dashboard-rbac-default.yaml
```

You can generate temporary tokens

``` shell
kubectl -n kube-system create token admin-user
```

You can also retrieve a permenant token.

``` shell
kubectl get secret admin-user -n kube-system -o jsonpath={".data.token"} | base64 -d
```
