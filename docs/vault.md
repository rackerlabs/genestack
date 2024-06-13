!!! Danger "This section is still underdevelopment and experimental"

    None of the vault components are required to run a Genestack environment.

# HashiCorp Vault Setup for Genestack Installation

HashiCorp Vault is a versatile tool designed for secret management and data protection. It allows you to securely store and control access to various sensitive data, such as tokens, passwords, certificates, and API keys. In this guide, we will use HashiCorp Vault to store Kubernetes Secrets for the Genestack installation.

## Prerequisites

Before starting the installation, ensure the following prerequisites are met:
- **Storage:** The Kubernetes Cluster should have available storage to create a PVC for data storage, especially when using integrated storage backend and storing audit logs. We will be using local storage located at /opt/vault on nodes labeled with `vault-storage: enabled`. Ensure that the nodes contain the `/opt/vault` directory.
- **Ingress Controller:** An Ingress Controller should be available as Vault's UI will be exposed using Ingress.
- **Sealed-secret:** If the Vault UI URL will use a domain certificate then, the Kubernetes secret should be deployed in the vault namespace. Make sure the secret manifest is encrypted using sealed-secret for secure storage in a Git repository.
- **Cert-Manager:** The installation will use end-to-end TLS generated using cert-manager. Hence, cert-manager should be available.

## Installation

``` shell
cd kustomize/vault/base
```

- Modify the `values.yaml` file with your desired configurations. Refer to the sample configuration in this directory, already updated for installation.

``` shell
vi values.yaml
```

- Specify the size of the PV and the PVC(dataStorage and auditStorage) in `kustomization.yaml`. Since we are utilizing local storage from the nodes, consider this as a placeholder. Vault will be able to utilize the available storage based on the size of /opt/vault on the nodes.

``` shell
vi kustomization.yaml
```
- Perform the installation:

``` shell
kubectl  kustomize . --enable-helm | kubectl apply -f -
```

## Configure Vault

After installing Vault, the Vault pods will initially be in a not-ready state. Initialization and unsealing are required.

``` shell
NAME                                    READY   STATUS    RESTARTS   AGE
vault-0                                 0/1     Running   0          55s
vault-1                                 0/1     Running   0          55s
vault-2                                 0/1     Running   0          55s
vault-agent-injector-7f9f668fd5-wk7tm   1/1     Running   0          55s
```

### Initialize Vault

``` shell
kubectl exec vault-0 -n vault -- vault operator init -key-shares=3 -key-threshold=2 -format=json > cluster-keys.json
```

This command provides unseal keys and a root token in cluster-keys.json. Keep this information secure.


### Unseal Vault(vault-0)

On vault-0 pod, use any of the 2 unseal keys obtained during initialization:
``` shell
kubectl exec -it vault-0 -n vault -- vault operator unseal
```
Repeat the unseal command as needed with different unseal keys.

### Join Vault Pods to Form a Cluster

``` shell
kubectl exec -it vault-1 -n vault -- vault operator raft join -leader-ca-cert=@/vault/userconfig/vault-server-tls/ca.crt https://vault-0.vault-internal:8200
```

``` shell
kubectl exec -it vault-2 -n vault -- vault operator raft join -leader-ca-cert=@/vault/userconfig/vault-server-tls/ca.crt https://vault-0.vault-internal:8200
```

### Unseal Vault(vault-1, vault-2)

On each Vault pod (vault-1, vault-2), use any of the 2 unseal keys obtained during initialization:
``` shell
kubectl exec -it vault-1 -n vault -- vault operator unseal
```
``` shell
kubectl exec -it vault-2 -n vault -- vault operator unseal
```

Repeat the unseal command as needed with different unseal keys.

### Authenticate to Vault

Use the root token obtained during initialization to authenticate:

``` shell
kubectl exec -it vault-0 -n vault -- vault login
```
### Enable audit logging
```
kubectl exec -it vault-0 -n vault -- vault audit enable file file_path=/vault/audit/audit.log
```

## Validation

Login to vault-0 and list the raft peers:

``` shell
kubectl exec vault-0 -n vault -it -- vault operator raft list-peers
Node       Address                        State       Voter
----       -------                        -----       -----
vault-0    vault-0.vault-internal:8201    leader      true
vault-1    vault-1.vault-internal:8201    follower    true
vault-2    vault-2.vault-internal:8201    follower    true
```

---

## Example to create secrets in Vault for Keystone:

- Enable Kubernetes auth method:

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- vault auth enable -path genestack kubernetes
```

- Define Kubernetes connection:

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- sh
vault write auth/genestack/config  kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443"
```

- Define secret path for keystone:

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- vault secrets enable -path=osh/keystone kv-v2
```

- Create a policy to access `osh/*` path:

``` shell
vault policy write osh - <<EOF
path "osh/*" {
   capabilities = ["read"]
}
EOF
```

- Create a role which will restrict the access as per your requirement:

``` shell
vault write auth/genestack/role/osh \
   bound_service_account_names=default \
   bound_service_account_namespaces=openstack \
   policies=osh \
   audience=vault \
   ttl=24h
```

- Create secrets for keystone:

Now, generate and store secrets for Keystone within the designated path.

- Keystone RabbitMQ Username:

``` shell
vault kv put -mount=osh/keystone keystone-rabbitmq-username username=keystone
```

- Keystone RabbitMQ Password:

``` shell
vault kv put -mount=osh/keystone keystone-rabbitmq-password password=$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-64};echo;)
```

- Keystone Database Password:

``` shell
vault kv put -mount=osh/keystone keystone-db-password password=$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)
```

- Keystone Admin Password:

``` shell
vault kv put -mount=osh/keystone keystone-admin  password=$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)
```

- Keystone Credential Key:

``` shell
vault kv put -mount=osh/keystone keystone-credential-keys  password=$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)
```

---

Once the secrets are created in Vault, we can use [vault-secrets-operator](https://github.com/rackerlabs/genestack/blob/main/docs/vault-secrets-operator.md) to populate the Kubernetes secret resources in Kubernetes cluster.
