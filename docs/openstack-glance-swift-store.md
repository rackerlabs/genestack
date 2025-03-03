# Connecting Glance to External Swift

When operating a cloud environment, it is often necessary to store images in a separate storage system. This can be useful for a number of reasons, such as:

* To provide a scalable storage solution for images
* To provide a storage solution that is separate from the compute nodes
* To provide a storage solution that is separate from the control plane
* Offsite backups for instances and instance snapshots
* Disaster recovery for instances and instance snapshots

In this guide, we will show you how to connect Glance to an external Swift storage system. This will allow you to store images in Swift, while still using Glance to manage the images.

## Prerequisites

Before you begin, you will need the following:

* A running OpenStack environment
* A running Swift environment
* A running Glance environment
* The IP address of the Swift server
* The port number of the Swift server
* The username and password for the Swift server

## Information Needed

The following information is needed to configure Glance to use Swift as an external storage system.

| Property | Value | Notes |
| -------- | ----- | ----- |
| KEYSTONE_AUTH_URL | STRING | Keystone V3 or later authentication endpoint where Swift is available within the service catalog |
| SUPER_SECRETE_KEY | STRING | Authentication password or key |
| CLOUD_DOMAIN_NAME | STRING | The domain name associated with the cloud account |
| CLOUD_PROJECT_NAME | STRING | The name of the project where objects will be stored |
| CLOUD_USERNAME | STRING | The username of that will be accessing the cloud project |

!!! note "For Rackspace OpenStack Flex Users"

    If you're using Rackspace OpenStack Flex, you can use the following options for the swift object storage.

    * `KEYSTONE_AUTH_URL` will be defined as "https://keystone.api.${REGION}.rackspacecloud.com/v3"
      * Replace `${REGION}` with the region where the Swift object storage is located, See [Rackspace Cloud Regions](api-status.md) for more information on available regions.
    * `CLOUD_DOMAIN_NAME` will be defined as "rackspace_cloud_domain"

### Step 1: Configure Glance to use Swift

Update the Helm overrides at `/etc/genestack/helm-configs/glance/glance-helm-overrides.yaml` with the following configuration to connect Glance to Swift.

``` yaml
---
conf:
  glance:
    DEFAULT:
      enabled_backends: swift:swift
    glance_store:
      default_backend: swift
      default_store: swift
  swift_store: |
    [ref1]
    auth_address = $KEYSTONE_AUTH_URL
    auth_version = 3
    key = $SUPER_SECRETE_KEY
    project_domain_id =
    project_domain_name = $CLOUD_DOMAIN_NAME
    swift_buffer_on_upload = true
    swift_store_container = glance
    swift_store_create_container_on_put = true
    swift_store_endpoint_type = publicURL
    swift_store_multi_tenant = false
    swift_store_region = SJC3
    swift_upload_buffer_dir = /var/lib/glance/images
    user = $CLOUD_PROJECT_NAME:$CLOUD_USERNAME
    user_domain_id =
    user_domain_name = $CLOUD_DOMAIN_NAME
```

### Step 2: Apply the Configuration

Apply the configuration to the Glance Helm chart.

``` bash
/opt/genestack/bin/install-glance.sh
```

Once the configuration has been applied, Glance will be configured to use Swift as an external storage system. You can now store images in Swift using Glance.
