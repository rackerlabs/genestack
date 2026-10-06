# Deploy Designate

OpenStack Designate is a multi-tenant DNSaaS for OpenStack. auto-generate records based on
Nova and Neutron actions. Designate supports a variety of DNS servers including Bind9 and PowerDNS 4.
This will allow for record management for all multi-project VMs to their respective network dns domains.

## Create secrets

!!! note "Information about the secrets used"

    Service secrets are managed idempotently by this service's install script. The installer creates any missing Kubernetes secrets and reuses existing values.

## Add a RNDC (Remote Name Daemon Control) Key as a secret

!!! Note "Example rndc.key file content"

```shell
key "rndc-key" {
  algorithm hmac-sha256;
  secret "ztevgpD9oMdowVWSr1104tWC/vCVaj8/ljnK6uWiVrc=";
};
```

Create a rndc.key file or import it from the running DNS server

```shell
kubectl create secret generic --namespace  openstack rndc-key-secret --from-file=<PATH_TO_RNDC.KEY_FILE>
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

### Check service API

``` shell
kubectl --namespace openstack exec -ti openstack-admin-client -- openstack dns service list
```

### Create a test zone

```shell
kubectl --namespace openstack exec -ti openstack-admin-client -- openstack zone create --email noreply@example.net example.net.

kubectl --namespace openstack exec -ti openstack-admin-client -- openstack zone list
```

!!! Wait for zone to go 'ACTIVE' state, also watch logs on DNS server logs to see if zone serial is logging on Nameserver
