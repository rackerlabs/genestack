# Connecting Cinder to External Ceph

When operating a cloud environment, it is often necessary to use a shared storage system rather than the local compute node for virtual machine disk storage. This can be useful for a number of reasons, such as:

* To provide a scalable storage solution for instances
* To provide a storage solution that is separate from the compute nodes
* To enable live migration capabilities

In this guide, we will show you how to connect Cinder to an external Ceph storage system. Doing so can enable users to leverage Nova's boot-from-volume capabilities as well as secondary attached volumes using an external Ceph backend.

## Prerequisites

Before you begin, you will need the following:

* A running OpenStack environment
* A running Ceph environment
* A running Cinder environment
* The `ceph.conf` file from the Ceph deployment server
* An OSD pool named `volumes` with adequate PGs
* A Ceph client named `cinder` with adequate permissions to the `volumes` pool

## Information Needed

The following information is needed to configure Nova to use Ceph as an external storage system.

| Property | Notes |
| -------- | ----- |
| `fsid` | The UUID of the respective Ceph deployment. Contained in `ceph.conf`. |
| `mon_host` | Specially-crafted list of Ceph monitor hosts. Contained in `ceph.conf`. |
| Ceph `cinder` client key | The Ceph key used to operate as the `cinder` user in Ceph |

### Step 1: Configure Ceph for Cinder

Prior to configuring Cinder to support an external Ceph deployment, you must first configure users and pools within Ceph. The examples below are provided as reference only, and may not be applicable to your environment. An assumption is made that Ceph is operational and OSDs have been made available for use.

#### Step 1a: Create and Initialize a Pool

```bash
ceph osd pool create volumes
rbd pool init volumes
```

#### Step 1b: Disable Autoscaling (optional)

```bash
ceph osd pool set volumes pg_autoscale_mode off
```

#### Step 1c: Set Placement Groups on the Pool

```bash
ceph osd pool set volumes pg_num 4096
```

Please note the value provided for pgs may not be appropriate for your deployment. Please refer to the Ceph PG calculator for additional guidance.

#### Step 1d: Create a client user for Nova/Cinder

In this example, a common client name `cinder` will be used for both Nova and Cinder integrations.

```bash
ceph auth get-or-create client.cinder mon 'profile rbd' osd 'profile rbd pool=volumes, profile rbd pool=vms, profile rbd-read-only pool=images' mgr 'profile rbd pool=volumes, profile rbd pool=vms'
```

The following output may be provided:

```bash
[client.cinder]
	key = AQCQqXJpHtP3AhBBU6rf/yvgq92fuJqBgy3Nxg==
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

Please note the same `ceph-etc` ConfigMap may be used for other Ceph integrations such as Glance and Nova. The name `ceph-etc` is built in to the template and should not be overridden unless you know what you're doing.

#### Step 2b: Create the Kubernetes Secret

On your OpenStack deploy node, create a file at `/etc/genestack/manifests/ceph/pvc-ceph-keyring.yaml` containing the following Secret using the key provided earlier:

```bash
apiVersion: v1
kind: Secret
metadata:
  name: pvc-ceph-client-key
  namespace: openstack
  labels:
    application: ceph
    component: rbd
stringData:
  key: AQCQqXJpHtP3AhBBU6rf/yvgq92fuJqBgy3Nxg==  
type: Opaque
```

Apply the Secret using the following command:

```bash
kubectl apply -f /etc/genestack/manifests/ceph/pvc-ceph-keyring.yaml
```

Please note the name `pvc-ceph-client-key` is built in to the template and should not be overridden unless you know what you're doing.

### Step 3: Create a Libvirt Secret UUID

Using the `uuidgen` utility, create a unique UUID that can be used to create a Libvirt secret:

```bash
# uuidgen
eea41bd9-c85e-4c99-879b-65e38ffb3213
```

### Step 4: Configure Cinder to use External Ceph

Update the Cinder Helm overrides at `/etc/genestack/helm-configs/cinder/cinder-helm-overrides.yaml` with the following configuration to connect Cinder to External Ceph.

Note that the values for both `secret_uuid` and `rbd_secret_uuid` should be the same UUID generated in the previous step. The `keyring` value should match the key generated in **Step 1d**.

``` yaml
images:
  tags:
    cinder_volume: "quay.io/airshipit/cinder:2024.1-ubuntu_jammy"

ceph_client:
  enable_external_ceph_backend: true
  external_ceph:
    rbd_user: cinder
    rbd_user_keyring: AQCQqXJpHtP3AhBBU6rf/yvgq92fuJqBgy3Nxg==

conf:
  ceph:
    enabled: true
  cinder:
    DEFAULT:
      enabled_backends: rbd-ceph
      default_volume_type: rbd-ceph
  backends:
    rbd-ceph:
      volume_driver: cinder.volume.drivers.rbd.RBDDriver
      volume_backend_name: rbd-ceph
      rbd_pool: volumes
      rbd_ceph_conf: /etc/ceph/ceph.conf
      rbd_secret_uuid: eea41bd9-c85e-4c99-879b-65e38ffb3213
      rbd_flatten_volume_from_snapshot: false
      report_discard_supported: true
      rbd_max_clone_depth: 5
      rbd_store_chunk_size: 4
      rados_connect_timeout: -1
      rbd_user: cinder
      image_volume_cache_enabled: true
      image_volume_cache_max_size_gb: 200
      image_volume_cache_max_count: 50
secrets:
  rbd:
    backup: pvc-ceph-client-key
    volume: pvc-ceph-client-key
    volume_external: pvc-ceph-client-key
manifests:
  deployment_volume: true
```

Please note the upstream container images are required for Ceph support at this time.

### Step 5: Apply the Configuration

Apply the configuration to the Cinder Helm chart.

``` bash
/opt/genestack/bin/install-cinder.sh
```

### Step 6: Create the Default Volume Type

Using the `openstack` client, create a default volume type for Cinder that matches the backend defined in **Step 4**.

```bash
openstack volume type create rbd-ceph --public
```

Once the configuration has been applied and the default volume type has been created, Cinder will be configured to use an external Ceph deployment for volume storage.