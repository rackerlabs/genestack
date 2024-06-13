!!! Danger "This section is still underdevelopment and experimental"

    None of the vault components are required to run a Genestack environment.

# HashiCorp Vault Secret Operators for Genestack Installation

The Vault Secrets Operator (VSO) enables Pods to seamlessly consume Vault secrets from Kubernetes Secrets. This guide outlines the process of consuming secrets stored in Vault for Genestack installation. This is continuation of [vault.md](https://docs.rackspacecloud.com/vault/) where we have created few secrets in the Vault

## Prerequisites

!!! note

    Before starting the installation, ensure HashiCorp Vault is installed in the cluster. You can refer [vault.md](https://docs.rackspacecloud.com/vault/) for more details.

## Installation

Navigate to the Vault Secrets Operator base directory:

``` shell
cd kustomize/vault-secrets-operator/base
```

Modify the `values.yaml` file with your desired configurations. Refer to the sample configuration in this directory, already updated for installation.

``` shell
vi values.yaml
```

Perform the installation.

``` shell
kubectl kustomize . --enable-helm | kubectl apply -f -
```

Validate if all the pods are up.
``` shell
kubectl get pods -n vault-secrets-operator
```

## Consume secrets from the Vault

After installing the `vault-secrets-operator`, create the necessary resources to consume secrets stored in Vault.

### Connect to the vault

Create a `VaultConnection` resource to establish a connection to Vault.

``` yaml
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultConnection
metadata:
namespace: openstack
name: vault-connection
spec:
# required configuration
# address to the Vault server.
address: https://vault.vault.svc.cluster.local:8200

# optional configuration
# HTTP headers to be included in all Vault requests.
# headers: []
# TLS server name to use as the SNI host for TLS connections.
# tlsServerName: ""
# skip TLS verification for TLS connections to Vault.
skipTLSVerify: false
# the trusted PEM encoded CA certificate chain stored in a Kubernetes Secret
caCertSecretRef: "vault-ca-secret"
```

`vault-ca-secret`: CA certificate used to sign the Vault certificate for internal communication.

### Authenticate with vault:

Create a `VaultAuth` resource to authenticate with Vault and access secrets.

``` yaml
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
name: keystone-auth
namespace: openstack
spec:
method: kubernetes
mount: genestack
kubernetes:
   role: osh
   serviceAccount: default
   audiences:
     - vault
vaultConnectionRef: vault-connection
```

### Create Vault static:

Define a `VaultStaticSecret` resource to fetch a secret from Vault and create a Kubernetes Secret resource.

``` yaml
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
name: keystone-rabbitmq-password
namespace: openstack
spec:
type: kv-v2

# mount path
mount: 'osh/keystone'

# path of the secret
path: keystone-rabbitmq-password

# dest k8s secret
destination:
   name: keystone-rabbitmq-password
   create: true

# static secret refresh interval
refreshAfter: 30s

# Name of the CRD to authenticate to Vault
vaultAuthRef: keystone-auth
```

This `VaultStaticSecret` resource fetches the `keystone-rabbitmq-password` secret from Vault and creates a Kubernetes Secret named `keystone-rabbitmq-password` in the openstack namespace which you can further use in the Genestack running on Kubernetes.

!!! example "Example usage workflow"

    ``` shell
    # From Vault:
    vault kv get osh/keystone/keystone-rabbitmq-password
    ================ Secret Path ================
    osh/keystone/data/keystone-rabbitmq-password

    ======= Metadata =======
    Key                Value
    ---                -----
    created_time       2024-02-21T12:13:20.961200482Z
    custom_metadata    <nil>
    deletion_time      n/a
    destroyed          false
    version            1

    ====== Data ======
    Key         Value
    ---         -----
    password    EENF1SfKOVkILTGVzftJhdj5A6mwnbcCLgdttahhKsQVxCWHrIrhc0theCG3Tzrr
    ```

    Apply the reuired configuration files.

    ``` shell
    # From Kubernetes:
    kubectl apply -f vaultconnection.yaml
    kubectl apply -f vault-auth.yaml
    kubectl apply -f keystone-rabbitmq-password-vault.yaml
    ```

    Return the secret in YAML

    ``` shell
    kubectl get secret keystone-rabbitmq-password -n openstack -o yaml
    apiVersion: v1
    data:
    _raw:  eyJkYXRhIjp7InBhc3N3b3JkIjoiRUVORjFTZktPVmtJTFRHVnpmdEpoZGo1QTZtd25iY0NMZ2R0dGFoaEtzUVZ4Q1dIcklyaGMwdGhlQ0czVHpyciJ9LCJtZXRhZGF0YSI6eyJjcmVhdGVkX3 RpbWUiOiIyMDI0LTAyLTIxVDEyOjEzOjIwLjk2MTIwMDQ4MloiLCJjdXN0b21fbWV0YWRhdGEiOm51bGwsImRlbGV0aW9uX3RpbWUiOiIiLCJkZXN0cm95ZWQiOmZhbHNlLCJ2ZXJzaW9uIjox fX0=
    password: RUVORjFTZktPVmtJTFRHVnpmdEpoZGo1QTZtd25iY0NMZ2R0dGFoaEtzUVZ4Q1dIcklyaGMwdGhlQ0czVHpycg==
    kind: Secret
    [...]
    ```

    Check the return password.

    ``` shell
    echo "RUVORjFTZktPVmtJTFRHVnpmdEpoZGo1QTZtd25iY0NMZ2R0dGFoaEtzUVZ4Q1dIcklyaGMwdGhlQ0czVHpycg==" | base64 -d
    EENF1SfKOVkILTGVzftJhdj5A6mwnbcCLgdttahhKsQVxCWHrIrhc0theCG3Tzrr
    ```
