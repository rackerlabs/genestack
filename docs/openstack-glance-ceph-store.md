# Connecting Glance to External Ceph

When operating a cloud environment, it is often necessary to store images in a separate storage system. This can be useful for a number of reasons, such as:

* To provide a scalable storage solution for images
* To provide a storage solution that is separate from the compute nodes
* To provide a storage solution that is separate from the control plane
* Offsite backups for instances and instance snapshots
* Disaster recovery for instances and instance snapshots

In this guide, we will show you how to connect Glance to an external Ceph storage system. This will allow you to store images in an externally-managed Ceph deployment while still using Glance to manage the images.

## Prerequisites

Before you begin, you will need the following:

* A running OpenStack environment
* A running Ceph environment
* A running Glance environment
* The `ceph.conf` file from the Ceph deployment server
* An OSD pool named `images` with adequate PGs
* A Ceph client named `glance` with adequate permissions to the `images` pool

## Information Needed

The following information is needed to configure Glance to use Ceph as an external storage system.

| Property | Notes |
| -------- | ----- |
| `fsid` | The UUID of the respective Ceph deployment. Contained in `ceph.conf`. |
| `mon_host` | Specially-crafted list of Ceph monitor hosts. Contained in `ceph.conf`. |
| Ceph `glance` client key | The Ceph key used to operate as the `glance` user in Ceph |

### Step 1: Configure Ceph for Glance

Prior to configuring Glance to support an external Ceph deployment, you must first configure users and pools within Ceph. The examples below are provided as reference only, and may not be applicable to your environment. An assumption is made that Ceph is operational and OSDs have been made available for use.

#### Step 1a: Create and Initialize a Pool

```bash
ceph osd pool create images
rbd pool init images
```

#### Step 1b: Disable Autoscaling (optional)

```bash
ceph osd pool set images pg_autoscale_mode off
```

#### Step 1c: Set Placement Groups on the Pool

```bash
ceph osd pool set images pg_num 2048
```

Please note the value provided for pgs may not be appropriate for your deployment. Please refer to the Ceph PG calculator for additional guidance.

#### Step 1d: Create a client user for Glance

```bash
ceph auth get-or-create client.glance mon 'profile rbd' osd 'profile rbd pool=images' mgr 'profile rbd pool=images'
```

The following output may be provided:

```bash
[client.glance]
	key = AQCLqXJpLg11LxBBqh985cW6XWQlIAged0MNgA==
```

Please note the key will be unique to your deployment. The key value will be needed for a Kubernetes secret later in this guide.

### Step 2: Configure Kubernetes Resources

The OpenStack-Helm charts rely on Kubernetes resources such as ConfigMaps and Secrets to create and populate configuration files during the deployment.

On a Ceph node, locate the `ceph.conf` file at `/etc/ceph/ceph.conf` and copy its output. 

#### Step 2a: Create the Kubernetes ConfigMap

On your OpenStack deploy node, create a file at `/etc/genestack/manifests/ceph/ceph-etc.yaml` containing the following ConfigMap with your respective `ceph.conf` output:

```bash
apiVersion: v1
kind: ConfigMap
metadata:
  name: ceph-etc
  namespace: openstack
data:
  ceph.conf: |
    [global]
	fsid = 6be518ac-f7b4-11f0-a76d-4bc5024d47a0
	mon_host = [v2:172.16.1.70:3300/0,v1:172.16.1.70:6789/0] [v2:172.16.1.71:3300/0,v1:172.16.1.71:6789/0] [v2:172.16.1.72:3300/0,v1:172.16.1.72:6789/0] [v2:172.16.1.73:3300/0,v1:172.16.1.73:6789/0] [v2:172.16.1.74:3300/0,v1:172.16.1.74:6789/0]
```

Apply the ConfigMap using the following command:

```bash
kubectl apply -f /etc/genestack/manifests/ceph/ceph-etc.yaml
```

Please note the same `ceph-etc` ConfigMap may be used for other Ceph integrations such as Nova and Cinder. The name `ceph-etc` is built in to the template and should not be overridden unless you know what you're doing.

#### Step 2b: Create the Kubernetes Secret

On your OpenStack deploy node, create a file at `/etc/genestack/manifests/ceph/glance-keyring.yaml` containing the following Secret using the key provided earlier:

```bash
apiVersion: v1
kind: Secret
metadata:
  name: images-rbd-keyring
  namespace: openstack
stringData:
  key: AQCLqXJpLg11LxBBqh985cW6XWQlIAged0MNgA==
type: Opaque
```

Apply the Secret using the following command:

```bash
kubectl apply -f /etc/genestack/manifests/ceph/glance-keyring.yaml
```

Please note the name `images-rbd-keyring` is built in to the template and should not be overridden unless you know what you're doing.

### Step 3: Configure Glance to use External Ceph

Update the Glance Helm overrides at `/etc/genestack/helm-configs/glance/glance-helm-overrides.yaml` with the following configuration to connect Glance to External Ceph.

``` yaml
---
storage: rbd
images:
  tags:
    glance_storage_init: quay.io/airshipit/ceph-config-helper:latest-ubuntu_jammy
    glance_api: quay.io/airshipit/glance:2024.1-ubuntu_jammy
conf:
  glance:
    DEFAULT:
      enabled_backends: "rbd:rbd"
      show_image_direct_url: True
    glance_store:
      default_backend: rbd
    rbd:
      rbd_store_chunk_size: 8
      rbd_store_replication: 3
      rbd_store_crush_rule: replicated_rule
      rbd_store_pool: images
      rbd_store_user: glance
      rbd_store_ceph_conf: /etc/ceph/ceph.conf
```

Please note the `rbd` storage value is necessary for Helm to implement Ceph support in Glance and must be set. In addition, upstream container images are required for Ceph support at this time.

If migrating from the `pvc` storage type, be sure to remove or comment out any `volume` configuration in the overrides file.

### Step 4: Apply the Configuration

Apply the configuration to the Glance Helm chart.

``` bash
/opt/genestack/bin/install-glance.sh
```

Once the configuration has been applied, Glance will be configured to use an external Ceph deployment for image storage. You can now store images in Ceph using Glance.
