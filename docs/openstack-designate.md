# Deploy Designate

OpenStack Designate is a multi-tenant DNSaaS for OpenStack. auto-generate records based on
Nova and Neutron actions. Designate supports a variety of DNS servers including Bind9 and PowerDNS 4.
This will allow for record management for all multi-project VMs to their respective network dns domains.

## Secrets

!!! note

    Secrets are generated and applied automatically by the install script.

## Add a RNDC (Remote Name Daemon Control)  key as a secret

Create a rndc.key file or import it from the running dns server

```shell
kubectl create secret generic --namespace  openstack rndc-key-secret --from-file=rndc.key
```

## Run the package deployment

!!! example "Run the Designate deployment Script"

    ``` shell
    /opt/genestack/bin/install.sh --service designate
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

