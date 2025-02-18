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
