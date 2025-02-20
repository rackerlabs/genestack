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
- Use tools such as [External Secret](https://external-secrets.io/latest/api/pushsecret/) to sync the keystone-ferent-keys.
- Make sure to have service account token by reading the above secret.

## Using PushSecret (external-secrets) to sync secrets

Lets look at how we can setup pushsecrets to sync fernet keys between two or more clusters.
First, install external-secrets operator

```shell
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace
```

Now, in order for secrets to sync, we will use a serviceaccount token with access only to a particular secret.
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
apiVersion: v1
kind: Secret
metadata:
  name: target-credentials
  namespace: openstack
data:
  token: <this is the token you got from the above step>
```

next, create a secret store for pushsecret to use

```
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: target-store
  namespace: openstack
spec:
  provider:
    kubernetes:
      remoteNamespace: openstack
      server:
        url: <k8s API URL for target>
        caBundle: <CA Bundle of target>
      auth:
        token:
          bearerToken:
            name: target-credentials
            key: token
```

Now, you can create a pushsecret to sync (any secret but in our case we have restricted to) keystone-fernet-keys.

Lets create that pushsecret definition

```
apiVersion: external-secrets.io/v1alpha1
kind: PushSecret
metadata:
  name: pushsecret-target-store
  namespace: openstack
spec:
  # Replace existing secrets in provider
  updatePolicy: Replace
  # Resync interval
  refreshInterval: 300s
  # SecretStore to push secrets to
  secretStoreRefs:
    - name: target-store
      kind: SecretStore
  # Target Secret
  selector:
    secret:
      name: keystone-fernet-keys  # Source cluster Secret name
  data:
    - match:
        remoteRef:
          remoteKey: keystone-fernet-keys  # Target cluster Secret name
```

This will sync keystone-fernet-keys from source to destination and refresh it every 300sec.
