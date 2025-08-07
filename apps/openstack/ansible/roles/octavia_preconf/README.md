## octavia_preconf

This is a role for performing the pre-requisite tasks to enable amphora provider for octavia for example creating a network and a subnet for amphorae, uploading the image to glance, creating ssh keys etc. This is mainly intended for running octavia in a k8s environment

## Requirements

These are the requirements to run this role:
1. This role needs to be run on any of the nodes which has access to the openstack public endpoints
2. This role also needs access to the k8s cluster as it tries to create "octavia-certs" secret in the openstack namespace to it needs access to kubectl utility
3. It is recommended to create a virtual environment to run this role; steps will be shared below

## Creating a virtual environment

1. Install the required packages for creating the virutal environment with python:
```
root@saturn-c1:~# apt-get install python3-venv python3-pip
```
2. Create the virtual environment:
```
root@saturn-c1:~# mkdir -p ~/.venvs
root@saturn-c1:~# python3 -m venv --system-site-packages ~/.venvs/octavia_preconf
```
3. Install the required dependencies for the virtual environment:
```
root@saturn-c1:~# source .venvs/octavia_preconf/bin/activate
(octavia_preconf) root@saturn-c1:~#
(octavia_preconf) root@saturn-c1:~# pip install --upgrade pip
(octavia_preconf) root@saturn-c1:~# pip install "ansible>=2.9" "openstacksdk>=1.0.0" "python-openstackclient==6.2.0"
```
4. Download the kubectl binary and copy the kubeconfig from one of the k8s master nodes:
```
(octavia_preconf) root@saturn-c1:~# curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
(octavia_preconf) root@saturn-c1:~# install -o root -g root -m 0755 kubectl /root/.venvs/octavia_preconf/bin
(octavia_preconf) root@saturn-c1:~# mkdir ~/.kube
(octavia_preconf) root@saturn-c1:~# mv config ~/.kube/
```
note that the kubeconfig in this step has been copied from the master node and it should be modified accordingly

## Role Variables

+ The available variables can be found in the defaults/main.yml file
+ The role variables can be used to modify
    + quota values for cores, RAM, security groups, security group rules, server groups and others
    + lb-mgmt-subet cidr, pool and gateway
    + whether ssh should be enabled for amphora
    + Validity and other certificate parameters \
Refer to the role defaults for more detail

## Dependencies

The role has no external dependencies; only the steps shared above for creating the virutal environment are required

## Example Playbook

The role needs keystone admin credentials; they can be provided as environment variables \
This is an example playbook for running the role:

```
(octavia_preconf) root@saturn-c1:~# cat octavia-preconf-main.yaml

- name: Pre-requisites for enabling amphora provider in octavia
  hosts: localhost
  environment:
    OS_ENDPOINT_TYPE: publicURL
    OS_INTERFACE: publicURL
    OS_USERNAME: 'admin'
    OS_PASSWORD: 'XXXXX'
    OS_PROJECT_NAME: 'admin'
    OS_TENANT_NAME: 'admin'
    OS_AUTH_TYPE: password
    OS_AUTH_URL: 'https://keystone.lab.local/v3'
    OS_USER_DOMAIN_NAME: 'default'
    OS_PROJECT_DOMAIN_NAME: 'default'
    OS_REGION_NAME: 'RegionOne'
    OS_IDENTITY_API_VERSION: 3
    OS_AUTH_VERSION: 3
    NOVA_ENDPOINT_TYPE: publicURL
  roles:
    - /root/octavia_preconf
```

These are the required environment variables for the role; must be modified accordingly. The keystone admin password can be obtained from k8s as below:
```
(octavia_preconf) root@saturn-c1:~# kubectl get secret -n openstack keystone-admin -o jsonpath='{ .data.password }' | base64 -d
```
