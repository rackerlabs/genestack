!!! banner "TECH PREVIEW"

# Deploy Manila

Manila is the Shared File Systems service for OpenStack. Manila provides
coordinated access to shared or distributed file systems.

This document outlines the deployment of OpenStack Manila using Genestack.

The method in which the share is provisioned and consumed is determined
by the Shared File Systems driver, or drivers in the case of a multi-backend
configuration. A variety of available Shared File Systems drivers work with
proprietary backend storage arrays and appliances, open source distributed
file systems, as well as Linux NFS or Samba server.

This tech preview will focus predominantly on the NetApp Clustered
Data ONTAP driver with share server management enabled. The driver interfaces
between OpenStack Manila to NetApp Clustered Data ONTAP storage controllers to
create new storage virtual machines (SVMs) for each tenant share server that is
requested by the Manila service. The driver also creates new data logical interfaces
(LIFs) that provide access for OpenStack tenants on a specific share network to
their shared file systems exported from the share server.

Reference the full online [OpenStack Manila documentation](https://docs.openstack.org/manila/latest/) 

## Create secrets

!!! note "Information about the secrets used"
!!! note "manila-service-keypair is only required for Generic share driver"

    Manual secret generation is only required if you haven't run the
    `create-secrets.sh` script located in `/opt/genestack/bin`.

    ??? example "Example secret generation"

        ``` shell
        kubectl --namespace openstack \
                create secret generic manila-admin \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        kubectl --namespace openstack \
                create secret generic manila-db-password \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        kubectl --namespace openstack \
                create secret generic manila-rabbitmq-password \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        ssh-keygen -qt ed25519 -N '' -C "manila_ssh" -f manila_ssh_key && \
        kubectl --namespace openstack \
                create secret generic manila-service-keypair \
                --type Opaque \
                --from-literal=public_key="$(cat manila_ssh_key.pub)" \
                --from-literal=private_key="$(cat manila_ssh_key)"
        rm -f manila_ssh_key manila_ssh_key.pub
        ```

## NetApp Clustered Data ONTAP driver configuration

Manila configuration values for the NetApp ONTAP driver should be edited
for the specific values relevant to the NetApp cluster and the Genestack
environment.

``` yaml
bootstrap:
  enabled: false

conf:
  manila:
    DEFAULT:
      default_share_type: default
      default_share_group_type: default
      enabled_share_backends: netapp_aff_nfs
      enabled_share_protocols: NFS
      osapi_max_limit: 1000
      osapi_share_use_ssl: true
      share_name_template: share-%s
      storage_availability_zone: az1
    netapp_aff_nfs:
      share_backend_name: netapp_aff_nfs
      share_driver: manila.share.drivers.netapp.common.NetAppDriver
      driver_handles_share_servers: true
      driver_ssl_cert_verify: false
      netapp_storage_family: ontap_cluster
      netapp_transport_type: https
      netapp_server_hostname: <cluster_FQDN>
      netapp_server_port: 443
      netapp_login: <admin_user>
      netapp_password: <admin_pass>
      netapp_aggregate_name_search_pattern: ^aggr01_n01_SSD$
      netapp_root_volume_aggregate: aggr01_n01_SSD
      netapp_root_volume: root
      netapp_port_name_search_pattern: ^(a0e-402|a0f-403)$
      netapp_vserver_name_template: mnl_%s
      netapp_lif_name_template: mnl_%(net_allocation_id)s
      netapp_volume_name_template: manila_%(share_id)s
      netapp_enabled_share_protocols: nfs4.1
      netapp_volume_snapshot_reserve_percent: 5
  manila_api_uwsgi:
    uwsgi:
      processes: 4

manifests:
  deployment_share: false
```


## Run the package deployment

!!! example "Run the Manila deployment Script `/opt/genestack/bin/install-manila.sh`"

    ``` shell
    --8<-- "bin/install-manila.sh"
    ```

!!! tip

    You may need to provide custom values to configure your OpenStack services.
    For a simple single region or lab deployment you can supply an additional
    overrides flag using the example found at
    `base-helm-configs/aio-example-openstack-overrides.yaml`.

## Validate functionality

``` shell
kubectl --namespace openstack exec -ti openstack-admin-client -- openstack share service list
```
