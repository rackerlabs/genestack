# Create Compute Kit Secrets

[![asciicast](https://asciinema.org/a/629813.svg)](https://asciinema.org/a/629813)

## Pre-requsites

- Vault should be installed by following the instructions in [vault documentation](https://docs.rackspacecloud.com/vault/)
- User has access to following paths in the Vault:
  - `osh/nova/`
  - `osh/ironic/`
  - `osh/designate/`
  - `osh/neutron/`

## Creating the Compute Kit Secrets

Part of running Nova is also running placement. Setup all credentials now so we can use them across the nova and placement services.

### Create the secrets - Placement

- Login to the vault:

``` shell
kubectl  exec -it vault-0 -n vault -- \
    vault login -method userpass username=nova
```

- List the existing secrets from `osh/placement/`:

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv list osh/placement
```

- Placement Database Password:

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv put -mount=osh/placement placement-db-password \
    password=$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)
```

- Placement Admin Password:

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv put -mount=osh/placement placement-admin \
    password=$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)
```

#### Validate the secrets

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv list osh/placement
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv get -mount=osh/placement  placement-admin
```

### Create the secrets - Nova

- List the existing secrets from `osh/nova/`:

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv list osh/nova
```

- Metadata-shared-secret Password:

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv put -mount=osh/nova metadata-shared-secret \
    password=$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)
```

- Nova Database Password:

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv put -mount=osh/nova nova-db-password \
    password=$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)
```

- Nova Admin Password:

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv put -mount=osh/nova nova-admin \
    password=$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)
```

- Nova RabbitMQ Username and Password:

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv put osh/nova/nova-rabbitmq-password username=nova

kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv patch -mount=osh/nova nova-rabbitmq-password \
    password=$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-64};echo;)
```

#### Validate the secrets

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv list osh/nova
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv get -mount=osh/nova  nova-admin
```

### Create the secrets - Ironic(NOT IMPLEMENTED YET)

- Login to the vault:

``` shell
kubectl  exec -it vault-0 -n vault -- \
    vault login -method userpass username=ironic
```

- List the existing secrets from `osh/ironic/`:

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv list osh/ironic
```

- Ironic Admin Password:

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv put -mount=osh/ironic ironic-admin \
    password=$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)
```

#### Validate the secrets

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv list osh/ironic
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv get -mount=osh/ironic  ironic-admin
```

### Create the secrets - Designate(NOT IMPLEMENTED YET)

- Login to the vault:

``` shell
kubectl  exec -it vault-0 -n vault -- \
    vault login -method userpass username=designate
```

- List the existing secrets from `osh/designate/`:

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv list osh/designate
```

- Designate Admin Password:

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv put -mount=osh/designate designate-admin \
    password=$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)
```

#### Validate the secrets

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv list osh/designate
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv get -mount=osh/designate  designate-admin
```

### Create the secrets - Neutron

- Login to the vault:

``` shell
kubectl  exec -it vault-0 -n vault -- \
    vault login -method userpass username=neutron
```

- List the existing secrets from `osh/neutron/`:

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv list osh/neutron
```

- Neutron Database Password:

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv put -mount=osh/neutron neutron-db-password \
    password=$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)
```

- Neutron Admin Password:

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv put -mount=osh/neutron neutron-admin \
    password=$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)
```

- Neutron RabbitMQ Username and Password:

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv put osh/neutron/neutron-rabbitmq-password username=neutron

kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv patch -mount=osh/neutron neutron-rabbitmq-password \
    password=$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-64};echo;)
```

#### Validate the secrets

``` shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv list osh/neutron
kubectl exec --stdin=true --tty=true vault-0 -n vault -- \
    vault kv get -mount=osh/neutron  neutron-admin
```

## Deploy vault-secret-operator resources

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

- Deploy the necessary Vault resources to create Kubernetes secrets required by the placement installation:

``` shell
kubectl apply -k /opt/genestack/kustomize/placement/base/vault/
```

- Deploy the necessary Vault resources to create Kubernetes secrets required by the nova installation:

``` shell
kubectl apply -k /opt/genestack/kustomize/nova/base/vault/
```

- Deploy the necessary Vault resources to create Kubernetes secrets required by the ironic installation:

``` shell
kubectl apply -k /opt/genestack/kustomize/ironic/base/vault/
```

- Deploy the necessary Vault resources to create Kubernetes secrets required by the designate installation:

``` shell
kubectl apply -k /opt/genestack/kustomize/designate/base/vault/
```

- Deploy the necessary Vault resources to create Kubernetes secrets required by the neutron installation:

``` shell
kubectl apply -k /opt/genestack/kustomize/neutron/base/vault/
```

- Validate whether the required Kubernetes secrets from Vault are populated:

``` shell
kubectl get secrets -n openstack
```

## Deploy Placement helm chart

``` shell
cd /opt/genestack/submodules/openstack-helm

helm upgrade --install placement ./placement --namespace=openstack \
  --namespace=openstack \
    --timeout 120m \
    -f /opt/genestack/helm-configs/placement/placement-helm-overrides.yaml \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.placement.password="$(kubectl --namespace openstack get secret placement-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.placement.password="$(kubectl --namespace openstack get secret placement-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.nova_api.password="$(kubectl --namespace openstack get secret nova-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --post-renderer /opt/genestack/kustomize/kustomize.sh \
    --post-renderer-args placement/base
```

## Deploy Nova helm chart

``` shell
cd /opt/genestack/submodules/openstack-helm

helm upgrade --install nova ./nova \
  --namespace=openstack \
    --timeout 120m \
    -f /opt/genestack/helm-configs/nova/nova-helm-overrides.yaml \
    --set conf.nova.neutron.metadata_proxy_shared_secret="$(kubectl --namespace openstack get secret metadata-shared-secret -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.nova.password="$(kubectl --namespace openstack get secret nova-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.neutron.password="$(kubectl --namespace openstack get secret neutron-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.ironic.password="$(kubectl --namespace openstack get secret ironic-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.placement.password="$(kubectl --namespace openstack get secret placement-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.cinder.password="$(kubectl --namespace openstack get secret cinder-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.nova.password="$(kubectl --namespace openstack get secret nova-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db_api.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db_api.auth.nova.password="$(kubectl --namespace openstack get secret nova-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db_cell0.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db_cell0.auth.nova.password="$(kubectl --namespace openstack get secret nova-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.admin.password="$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.nova.password="$(kubectl --namespace openstack get secret nova-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)" \
    --post-renderer /opt/genestack/kustomize/kustomize.sh \
    --post-renderer-args nova/base
```

!!! tip

    In a production like environment you may need to include production specific files like the example variable file found in `helm-configs/prod-example-openstack-overrides.yaml`.

!!! note

    The above command is setting the ceph as disabled. While the K8S infrastructure has Ceph, we're not exposing ceph to our openstack environment.

If running in an environment that doesn't have hardware virtualization extensions add the following two `set` switches to the install command.

``` shell
--set conf.nova.libvirt.virt_type=qemu --set conf.nova.libvirt.cpu_mode=none
```

!!! tip

    In a production like environment you may need to include production specific files like the example variable file found in `helm-configs/prod-example-openstack-overrides.yaml`.


## Deploy Neutron helm chart

``` shell
cd /opt/genestack/submodules/openstack-helm

helm upgrade --install neutron ./neutron \
  --namespace=openstack \
    --timeout 120m \
    -f /opt/genestack/helm-configs/neutron/neutron-helm-overrides.yaml \
    --set conf.metadata_agent.DEFAULT.metadata_proxy_shared_secret="$(kubectl --namespace openstack get secret metadata-shared-secret -o jsonpath='{.data.password}' | base64 -d)" \
    --set conf.ovn_metadata_agent.DEFAULT.metadata_proxy_shared_secret="$(kubectl --namespace openstack get secret metadata-shared-secret -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.neutron.password="$(kubectl --namespace openstack get secret neutron-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.nova.password="$(kubectl --namespace openstack get secret nova-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.placement.password="$(kubectl --namespace openstack get secret placement-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.designate.password="$(kubectl --namespace openstack get secret designate-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.ironic.password="$(kubectl --namespace openstack get secret ironic-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.neutron.password="$(kubectl --namespace openstack get secret neutron-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.admin.password="$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.neutron.password="$(kubectl --namespace openstack get secret neutron-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set conf.neutron.ovn.ovn_nb_connection="tcp:$(kubectl --namespace kube-system get service ovn-nb -o jsonpath='{.spec.clusterIP}:{.spec.ports[0].port}')" \
    --set conf.neutron.ovn.ovn_sb_connection="tcp:$(kubectl --namespace kube-system get service ovn-sb -o jsonpath='{.spec.clusterIP}:{.spec.ports[0].port}')" \
    --set conf.plugins.ml2_conf.ovn.ovn_nb_connection="tcp:$(kubectl --namespace kube-system get service ovn-nb -o jsonpath='{.spec.clusterIP}:{.spec.ports[0].port}')" \
    --set conf.plugins.ml2_conf.ovn.ovn_sb_connection="tcp:$(kubectl --namespace kube-system get service ovn-sb -o jsonpath='{.spec.clusterIP}:{.spec.ports[0].port}')" \
    --post-renderer /opt/genestack/kustomize/kustomize.sh \
    --post-renderer-args neutron/base
```

!!! tip

    In a production like environment you may need to include production specific files like the example variable file found in `helm-configs/prod-example-openstack-overrides.yaml`.

!!! info

    The above command derives the OVN north/south bound database from our K8S environment. The insert `set` is making the assumption we're using **tcp** to connect.
