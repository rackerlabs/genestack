# NetApp Volume Worker Configuration Documentation

This document provides information on configuring NetApp backends for the isolated Cinder volume worker. Each backend is defined by a set of
11 comma-separated options, and multiple backends can be specified by separating them with semicolons.


!!! warning "The NetApp container is incompatible with iSCSI workloads"

    The NetApp container is incompatible with iSCSI workloads. If the environment requires iSCSI support, review the [Cinder NetApp Worker ](openstack-cinder-netapp-worker.md) documentation instead.

## Backend Options

Below is a table detailing each option, its position in the backend configuration, a description, and the expected data type.

| Option Index | Option Name                   | Description                                                                  | Type    |
|--------------|-------------------------------|------------------------------------------------------------------------------|---------|
| 0            | `backend_name`                | The name of the backend configuration section. Used as `volume_backend_name`.| String  |
| 1            | `netapp_login`                | Username for authenticating with the NetApp storage system.                  | String  |
| 2            | `netapp_password`             | Password for authenticating with the NetApp storage system.                  | String  |
| 3            | `netapp_server_hostname`      | Hostname or IP address of the NetApp storage system.                         | String  |
| 4            | `netapp_server_port`          | Port number to communicate with the NetApp storage system.                   | Integer |
| 5            | `netapp_vserver`              | The name of the Vserver on the NetApp storage system.                        | String  |
| 6            | `netapp_dedup`                | Enable (`True`) or disable (`False`) deduplication.                          | Boolean |
| 7            | `netapp_compression`          | Enable (`True`) or disable (`False`) compression.                            | Boolean |
| 8            | `netapp_thick_provisioned`    | Use thick (`True`) or thin (`False`) provisioning.                           | Boolean |
| 9            | `netapp_lun_space_reservation`| Enable (`enabled`) or disable (`disabled`) LUN space reservation.            | String  |

### Detailed Option Descriptions

- **`backend_name`**: A unique identifier for the backend configuration. This name is used internally by Cinder to distinguish between different backends.
- **`netapp_login`**: The username credential required to authenticate with the NetApp storage system.
- **`netapp_password`**: The password credential required for authentication. Ensure this is kept secure.
- **`netapp_server_hostname`**: The address of the NetApp storage system. This can be either an IP address or a fully qualified domain name (FQDN).
- **`netapp_server_port`**: The port number used for communication with the NetApp storage system. Common ports are `80` for HTTP and `443` for HTTPS.
- **`netapp_vserver`**: Specifies the virtual storage server (Vserver) on the NetApp storage system that will serve the volumes.
- **`netapp_dedup`**: A boolean value to enable or disable deduplication on the storage volumes. Acceptable values are `True` or `False`.
- **`netapp_compression`**: A boolean value to enable or disable compression on the storage volumes. Acceptable values are `True` or `False`.
- **`netapp_thick_provisioned`**: Determines whether volumes are thick (`True`) or thin (`False`) provisioned.
- **`netapp_lun_space_reservation`**: A String indicating whether to enable space reservation for LUNs. If `enabled`, space is reserved for the entire LUN size at creation time.

## Example opaque Configuration

Before deploying the NetApp volume worker, create the necessary Kubernetes secret with the `BACKENDS` environment variable:

```shell
kubectl --namespace openstack create secret generic cinder-netapp \
        --type Opaque \
        --from-literal=BACKENDS="backend1,user1,password1,host1,80,vserver1,qos1,True,True,False,enabled"
```

### `BACKENDS` Environment Variable Structure

The `BACKENDS` environment variable is used to pass backend configurations to the NetApp volume worker. Each backend configuration consists of 11 options
in a specific order.

!!! Example "Replace the placeholder values with your actual backend configuration details"

    ```shell
    BACKENDS="backend1,user1,password1,host1,80,vserver1,qos1,True,True,False,disabled;backend2,user2,password2,host2,443,vserver2,qos2,False,True,True,enabled"
    ```

## Run the deployment

!!! warning

    **Before** deploying a new backend, ensure that your volume type has been set up correctly and that you have applied QoS policies, provisioning specifications (min and max volume size), and any extra specs. See [Cinder Volume QoS Policies](openstack-cinder-volume-qos-policies.md), [Cinder Volume Provisioning Specs](openstack-cinder-volume-provisioning-specs.md), and [Cinder Volume Type Specs](openstack-cinder-volume-type-specs.md).

With your configuration defined, run the deployment with a standard `kubectl apply` command.

``` shell
kubectl --namespace openstack apply -k /etc/genestack/kustomize/cinder/netapp
```
