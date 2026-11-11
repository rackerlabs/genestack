CAPI CLUSTER
=========

This is the ansible role for creating the infra for installing CAPI mgmt cluster on a genestack cloud

Requirements
------------

These are the infra level requirements for the role to create the required infra for the CAPI mgmt cluster:
* cinder-volume service enabled: Currently the role only supports bfv instances; so cinder-volume should be enabled
* external network: A pre-created shared external Neutron network (either flat or vlan) to be used for the role
* Keystone admin credentials: when running the role; Keystone admin user credentials would be required
* octavia service enabled: role creates loadbalancer for the CAPI mgmt cluster; so octavia should be enabled

These are the network level requirements for the role to create the CAPI mgmt cluster:
* dns server: At least one dns server to be defined:
  - dns server should be reachable from the external Neutron network used with the role
  - dns server should be able resolve external endpoints for the openstack services on genestack cloud
* external network reachability:
  - the external network should be reachable from the ansible control node from where the playbook is run
  - the external network should be able reach the public endpoints for openstack services

There are a few other requirements for this role as well:
* openstack sdk installed: On the ansible control node openstack-sdk should be installed (generally genestack venv is sufficient)
* sufficient storage space on glance: the role will upload a ubuntu-24 image; should the backend for glance should have sufficient space
* currently there is no provision to include custom tls certs; so if the openstack endpoints are behind a tls gateway then the certs should be
  signed by a well-known CA like verisign etc; self signed certs will cause failures with magnum after the mgmt cluster is deployed

Role Variables
--------------

These are the role variables:
* Required role variables:
  - ext_net_id: External Neutron network ID (should already exist)
  - os_auth_url: Public URL to the Keystone service
  - os_admin_password: Keystone admin password (retrieved from the keystone-admin secret)
  - os_user_password: Password for the new user to be created for capi-mgmt-cluster-project
  - capi_mgmt_dns_servers: DNS server to be used for the CAPI mgmt cluster
  - capi_boot_from_volume: Should be set to true (default)

* other important role variables:
  - capi_mgmt_cluster_flavor: Flavor the CAPI mgmt cluster vms (flavor name and specs)
  - capi_mgmt_cluster_volume_type: Volume Type for the CAPI mgmt cluster (defaults to lvmdriver-1)
  - capi_mgmt_cluster_volumes: Can be used to define the size of the volumes for CAPI mgmt cluster vms
  - capi_mgmt_etcd_backup_volume: Can be used to define the size of the etcd backup volume and volume type
  - capi_mgmt_cluster_lb_enable_fip: Can be used to create the CAPI mgmt cluster lb on the geneve network and assign a floating IP
  - create_tunnelled_network_infra: When true creates the CAPI mgmt cluster instances on geneve network or otherwise directly on the external network

Refer to defaults/main.yml with the role directory for more details on the variables

Dependencies
------------

There are no external dependencies for the role; basic genestack venv should be sufficient

Example Playbook
----------------

The playbook which includes the role for capi mgmt cluster infra should be used as below.
The OS Auth URL should be set to the public Keystone URL to allow the CAPI cluster to connect
from all networks.

```
ansible-playbook capi-mgmt-main.yaml -e os_auth_url='https://keystone-api.example.com/v3' -e os_user_password=password1234 -e ext_net_id='7f84bb82-996e-4520-a2f0-50a9602de363'
```

Author Information
------------------

Name: Punit Shankar Kundal\
Email: punitshankar.kundal@rackspace.com
