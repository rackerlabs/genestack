# Deploy Skyline

[![asciicast](https://asciinema.org/a/629816.svg)](https://asciinema.org/a/629816)

Skyline is an alternative Web UI for OpenStack. If you deploy horizon there's no need for Skyline.

## Pre-requsites

- Vault should be installed by following the instructions in [vault documentation](https://docs.rackspacecloud.com/vault/)
- User has access to `osh/skyline/` path in the Vault

## Create secrets in the vault

### Login to the vault

``` shell
kubectl  exec -it vault-0 -n vault -- \
    vault login -method userpass username=skyline
```

### List the existing secrets from `osh/skyline/`

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv list osh/skyline
```

### Create the secrets

Skyline is a little different because there's no helm integration. Given this difference the deployment is far simpler, and all secrets can be managed in one object.

- Skyline-apiserver-secrets:

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv put -mount=osh/skyline skyline-apiserver-secrets \
    service-username=skyline \
    service-password=$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;) \
    service-domain=service \
    service-project=service \
    service-project-domain=service \
    db-endpoint=maxscale-galera.openstack.svc.cluster.local \
    db-name=skyline \
    db-username=skyline \
    db-password=$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;) \
    secret-key=$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;) \
    keystone-endpoint="$(kubectl --namespace openstack get secret keystone-keystone-admin -o jsonpath='{.data.OS_AUTH_URL}' | base64 -d)" \
    keystone-username=skyline \
    default-region=RegionOne \
    prometheus_basic_auth_password="" \
    prometheus_basic_auth_user="" \
    prometheus_enable_basic_auth=false \
    prometheus_endpoint=http://kube-prometheus-stack-prometheus.prometheus.svc.cluster.local:9090
```

### Validate the secrets

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv list osh/skyline
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv get -mount=osh/skyline skyline-apiserver-secrets
```

## Install Skyline

- Ensure that the `vault-ca-secret` Kubernetes Secret exists in the OpenStack namespace containing the Vault CA certificate:

```shell
kubectl get secret vault-ca-secret -o yaml -n openstack
```

- If it is absent, create one using the following command:

``` shell
kubectl create secret generic vault-ca-secret \
    --from-literal=ca.crt="$(kubectl get secret vault-tls-secret \
    -o jsonpath='{.data.ca\.crt}' -n vault | base64 -d -)" -n openstack
```

- Deploy the necessary Vault resources to create Kubernetes secrets required by the Skyline installation:

``` shell
kubectl apply -k /opt/genestack/kustomize/skyline/base/vault/
```

- Validate whether the required Kubernetes secrets from Vault are populated:

``` shell
kubectl get secrets -n openstack
```

!!! note

    All the configuration is in this one secret, so be sure to set your entries accordingly.

### Deploy Skyline

!!! tip

    Pause for a moment to consider if you will be wanting to access Skyline via your ingress controller over a specific FQDN. If so, modify `/opt/genestack/kustomize/skyline/fqdn/kustomization.yaml` to suit your needs then use `fqdn` below in lieu of `base`...

``` shell
kubectl --namespace openstack apply -k /opt/genestack/kustomize/skyline/base
```
