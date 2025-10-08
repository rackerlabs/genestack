# Fernet Key Synchronization in Keystone

## Overview
With Genestack's multi region support, administrators might want to run multiple keystone servcies that can all validate the user token. In order to
do this we can sync Fernet Keys between keystone nodes. Keystone uses fernet keys to generate tokens. These keys are rotated using the `keystone-manage` command to generate a new set of keys.
When the keys are rotated, the primary key is relegated to secondary, and a new primary key is issued. Secondary keys can only be used to decrypt tokens that were created with previous primary keys, and cannot issue new ones.

Lets take a look at what each key type does:

**Primary Key** is used to encrypt and decrypt tokens. There is only one primary key at any given moment. Primary key is delegated into secondary key.

**Secondary Key** was at some point the primary but is not demoted to a secondary state. It can only decrypt tokens.

**Staged Keys** is a special key staged to become the next primary. They can also decrypt tokens, and will become the next primary.

In deployments where multiple Keystone instances exist, these keys need to be distributed across all instances to ensure consistent authentication.

For **Genestack-based OpenStack** deployments, these keys can be distributed across multiple clusters by syncing the **Kubernetes Secret** that holds these keys.

## Purpose
A deployment is created with python app that  reads the primary key from one main Keystone deployment and synchronizes it to the same secret name across multiple Remote clusters.

## Architecture


```
                        / ──> API ──> | Remote K8s Cluster |
                       /
                      /
                     /
Main K8s Cluster | ──> API ──> | Remote K8s Cluster |
                     \
                      \
                       \
                        \ ──> API ──> | Remote K8s Cluster |
```

## How It Works
1. The main Keystone cluster stores **Fernet keys** in a Kubernetes Secret.
2. The application retrieves the keys from the primary cluster.
3. The retrieved keys are synchronized to multiple remote clusters via the **Kubernetes API**.

## How can we sync keys?
- Ensure that each cluster has the correct permissions to read and write Kubernetes Secrets.
- We are using [fernet-sync](https://github.com/rackerlabs/fernet-sync) to sync the keystone-ferent-keys.
- Make sure to have service account token by reading the above secret.

## Setup fernet-sync deploymet

Lets look at how we can setup to sync fernet keys between two or more clusters.

First, in order for secrets to sync, we will use a serviceaccount token with access only to a particular secret.
So, in the target cluster create a new service account and give it appropriate permissions
```
apiVersion: v1
kind: ServiceAccount
metadata:
  name: keystone-sync-external
  namespace: openstack
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: openstack
  name: keystone-sync-external-role
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get", "list", "create", "update", "patch"]
    resourceNames: ["keystone-fernet-keys"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: keystone-sync-external-rolebinding
  namespace: openstack
subjects:
  - kind: ServiceAccount
    name: keystone-sync-external
    namespace: openstack
roleRef:
  kind: Role
  name: keystone-sync-external-role
  apiGroup: rbac.authorization.k8s.io
```

Here, we create a new role keystone-sync-external and bind it to role that allows access to our secret `keystone-fernet-keys`

Next, create a new token associated with this account

```
apiVersion: v1
kind: Secret
type: kubernetes.io/service-account-token
metadata:
  name: keystone-sync-external-secret
  annotations:
    kubernetes.io/service-account.name: keystone-sync-external
```

then get the token assoicated with this by running

```
kubectl get secret keystone-sync-external-secret -o yaml -n openstack
```

next, on the source cluster create credentials for the target

```
git clone https://github.com/rackerlabs/fernet-sync.git
cd fernet-sync
vim create-secret.sh

then make sure to have your cluser and token defined in the format
TOKENS = {"https://cluster1.example.com": "token for cluster1", "https://cluster2.example.com": "token for cluster2"}
```

next, create the secret

```
cd fernet-sync
./create-secret.sh

```

Now, you can create a deployment to sync secret


```shell
kubectl apply -f deployment.yaml
```

This will create a deployment that will listen to any change in `keystone-fernet-keys` secret and sync it to the
clusters defined the create-secret.sh script.
