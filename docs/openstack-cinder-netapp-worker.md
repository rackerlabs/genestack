# NetApp Volume Worker Configuration Documentation

The NetApp Volume Worker is a cinder-volume service that is configured to use the NetApp ONTAP driver. This service is responsible for managing the creation, deletion, and management of volumes in the OpenStack environment. The NetApp Volume Worker is a stateful service that is deployed on a baremetal node that has access to the NetApp storage system.

## Configuration

The `deploy-cinder-volumes-netapp-reference.yaml` playbook is used to deploy the NetApp Volume Worker. The playbook will deploy the cinder-volume service on the specified nodes and configure the service to use the NetApp ONTAP driver. This playbook will read from the Kubernetes environment to determine the necessary configuration parameters for the NetApp ONTAP driver. As an operator, you will need to ensure that the necessary configuration parameters are set in the Kubernetes environment before running the playbook.

!!! warning

    **Before** deploying a new backend, ensure that your volume type has been set up correctly and that you have applied QoS policies, provisioning specifications (min and max volume size), and any extra specs. See [Cinder Volume QoS Policies](openstack-cinder-volume-qos-policies.md), [Cinder Volume Provisioning Specs](openstack-cinder-volume-provisioning-specs.md), and [Cinder Volume Type Specs](openstack-cinder-volume-type-specs.md).

### Backends Configuration

The NetApp ONTAP driver requires a backend configuration to be set in the Kubernetes environment. The backend configuration specifies the storage system that the NetApp Volume Worker will use to create and manage volumes. The backend configuration is a Kubernetes secret that contains the necessary configuration parameters for the NetApp ONTAP driver. To define the backends, update the helm overrides file with the necessary configuration parameters.

!!! example "Cinder NetApp Backend Configuration in Helm"

    ``` yaml
    conf:
      backends:
        block-ha-performance-at-rest-encrypted:
          netapp_login: <LOGIN>
          netapp_password: <PASSWORD>
          netapp_server_hostname: <SERVER_NAME_OR_ADDRESS>
          netapp_server_port: <SERVER_PORT>
          netapp_storage_family: ontap_cluster
          netapp_storage_protocol: iscsi
          netapp_transport_type: http
          netapp_vserver: <VSERVER>
          netapp_dedup: True
          netapp_compression: True
          netapp_thick_provisioned: True
          netapp_lun_space_reservation: enabled
          volume_driver: cinder.volume.drivers.netapp.common.NetAppDriver
          volume_backend_name: block-ha-performance-at-rest-encrypted
        block-ha-standard-at-rest-encrypted:
          netapp_login: <LOGIN>
          netapp_password: <PASSWORD>
          netapp_server_hostname: <SERVER_NAME_OR_ADDRESS>
          netapp_server_port: <SERVER_PORT>
          netapp_storage_family: ontap_cluster
          netapp_storage_protocol: iscsi
          netapp_transport_type: http
          netapp_vserver: <VSERVER>
          netapp_dedup: True
          netapp_compression: True
          netapp_thick_provisioned: True
          netapp_lun_space_reservation: enabled
          volume_driver: cinder.volume.drivers.netapp.common.NetAppDriver
          volume_backend_name: block-ha-standard-at-rest-encrypted
    ```

### Detailed Variable Descriptions

- **`LOGIN`**: The username credential required to authenticate with the NetApp storage system.
- **`PASSWORD`**: The password credential required for authentication. Ensure this is kept secure.
- **`SERVER_NAME_OR_ADDRESS`**: The address of the NetApp storage system. This can be either an IP address or a fully qualified domain name (FQDN).
- **`SERVER_PORT`**: The port number used for communication with the NetApp storage system. Common ports are `80` for HTTP and `443` for HTTPS.
- **`VSERVER`**: Specifies the virtual storage server (Vserver) on the NetApp storage system that will serve the volumes.

## Host Setup

The cinder target hosts need to have some basic setup run on them to make them compatible with our Logical Volume Driver.

### Ensure DNS is working normally.

Assuming your storage node was also deployed as a K8S node when we did our initial Kubernetes deployment, the DNS should already be
operational for you; however, in the event you need to do some manual tweaking or if the node was note deployed as a K8S worker, then
make sure you setup the DNS resolvers correctly so that your volume service node can communicate with our cluster.

!!! note

    This is expected to be our CoreDNS IP, in my case this is `169.254.25.10`.

This is an example of my **systemd-resolved** conf found in `/etc/systemd/resolved.conf`
``` conf
[Resolve]
DNS=169.254.25.10
#FallbackDNS=
Domains=openstack.svc.cluster.local svc.cluster.local cluster.local
#LLMNR=no
#MulticastDNS=no
DNSSEC=no
Cache=no-negative
#DNSStubListener=yes
```

Restart your DNS service after changes are made.

``` shell
systemctl restart systemd-resolved.service
```

## Run the deployment

The `deploy-cinder-volumes-netapp-reference.yaml` will target the `cinder_storage_nodes` group in the inventory file. The inventory file should be updated to reflect the actual hostnames of the nodes that will be running the cinder-volume-netapp service.

``` shell
ansible-playbook -i inventory-example.yaml deploy-cinder-volumes-netapp-reference.yaml
```

Once the playbook has finished executing, check the cinder api to verify functionality.

``` shell
root@openstack-node-0:~# kubectl --namespace openstack exec -ti openstack-admin-client -- openstack volume service list
+------------------+--------------------------------------------------------------------+------+---------+-------+----------------------------+
| Binary           | Host                                                               | Zone | Status  | State | Updated At                 |
+------------------+--------------------------------------------------------------------+------+---------+-------+----------------------------+
| cinder-scheduler | cinder-volume-worker                                               | nova | enabled | up    | 2023-12-26T17:43:07.000000 |
| cinder-volume    | cinder-volume-netapp-worker@block-ha-performance-at-rest-encrypted | nova | enabled | up    | 2023-12-26T17:43:04.000000 |
+------------------+--------------------------------------------------------------------+------+---------+-------+----------------------------+
```

After the playbook has executed, the cinder-volume-netapp service should be running on the specified nodes and should be configured to use the NetApp ONTAP driver. The service should be able to create, delete, and manage volumes on the NetApp storage system. Validate the service is running by checking the cinder volume service list via the API or on the command line with `systemctl status cinder-volume-netapp`.
