# Deploy Designate

OpenStack Designate is a multi-tenant DNSaaS for OpenStack. auto-generate records based on
Nova and Neutron actions. Designate supports a variety of DNS servers including Bind9 and PowerDNS 4.
This will allow for record management for all multi-project VMs to their respective network dns domains.

## Create secrets

!!! note "Information about the secrets used"

    Manual secret generation is only required if you haven't run the
    `create-secrets.sh` script located in `/opt/genestack/bin`.

    ??? example "Example secret generation"

        ``` shell
        kubectl --namespace openstack \
                create secret generic designate-rabbitmq-password \
                --type Opaque \
                --from-literal=username="designate" \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-64};echo;)"
        kubectl --namespace openstack \
                create secret generic designate-db-password \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        kubectl --namespace openstack \
                create secret generic designate-admin \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        ```

## Add a RNDC (Remote Name Daemon Control)  key as a secret

Create a rndc.key file or import it from the running dns server

```shell
kubectl create secret generic --namespace  openstack rndc-key-secret --from-file=rndc.key
```

## Run the package deployment

!!! example "Run the Designate deployment Script `/opt/genestack/bin/install-designate.sh`"

    ``` shell
    --8<-- "bin/install-designate.sh"
    ```

!!! tip

    You may need to provide custom values to configure your OpenStack services.
    For a simple single region or lab deployment you can supply an additional
    overrides flag using the example found at
    `base-helm-configs/aio-example-openstack-overrides.yaml`.

## Validate functionality

``` shell
kubectl --namespace openstack exec -ti openstack-admin-client -- openstack dns service list
```

