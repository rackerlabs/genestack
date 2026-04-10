CAPI CLUSTER
=========

This is the ansible role for creating the infra for installing capi mgmt cluster on a genestack cloud

Requirements
------------

These are the infra level requirements for the role to create the required infra for the capi mgmt cluster:
* cinder-volume service enabled: Currently the role only supports bfv instances; so cinder-volume should be enabled
* external network: A pre-created shared external neutron network (either flat or vlan) to be used for the role
* keystone admin credentials: when running the role; keystone admin user credentials would be required
* octavia service enabled: role creates loadbalancer for the capi mgmt cluster; so octavia should be enabled

These are the network level requirements for the role to create the capi mgmt cluster:
* dns server: Atleast one dns server to be defined:
  - dns server should be reachable from the external neutron network used with the role
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
* required role variables:
  - ext_net_id: external neutron network ID (should already exist)
  - os_admin_password: keystone admin password
  - os_user_password: password for the new user to be created for capi-mgmt-cluster-project
  - capi_mgmt_dns_servers: dns server to be used for the capi mgmt cluster
  - capi_boot_from_volume: should be set to true (default)

* other important role variables:
  - capi_mgmt_cluster_flavor: flavor the capi mgmt cluster vms (flavor name and specs)
  - capi_mgmt_cluster_volume_type: volume type for the capi mgmt cluster (defaults to lvmdriver-1)
  - capi_mgmt_cluster_volumes: can be used to define the size of the volumes for capi mgmt cluster vms
  - capi_mgmt_etcd_backup_volume: can be used to define the size of the etcd backup volume and volume type

Refer to defaults/main.yml with the role directory for more details on the variables

Dependencies
------------

There are no external dependencies for the role; basic genestack venv should be sufficient

Example Playbook
----------------

The playbook which includes the role for capi mgmt cluster infra should be used as below:

```
ansible-playbook capi-mgmt-main.yaml -e os_admin_password=<keystone_admin_passwd> -e os_user_password=rack1234 -e ext_net_id='7f84bb82-996e-4520-a2f0-50a9602de363'
```

Author Information
------------------

Name: Punit Shankar Kundal\
Email: punitshankar.kundal@rackspace.com
