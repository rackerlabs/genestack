# Connecting Nova to External Ceph

When operating a cloud environment, it is often necessary to use a shared storage system rather than the local compute node for virtual machine disk storage. This can be useful for a number of reasons, such as:

* To provide a scalable storage solution for instances
* To provide a storage solution that is separate from the compute nodes
* To enable live migration capabilities

In this guide, we will show you how to connect Nova to an external Ceph storage system. The examples provided here assume Cinder is also configured for the same external Ceph backend.

## Prerequisites

Before you begin, you will need the following:

* A running OpenStack environment
* A running Ceph environment
* A running Nova environment
* A running Cinder environment using External Ceph
* The `ceph.conf` file from the Ceph deployment server
* An OSD pool named `vms` with adequate PGs
* A Ceph client named `cinder` with adequate permissions to the `vms` pool

## Information Needed

The following information is needed to configure Nova to use Ceph as an external storage system.

| Property | Notes |
| -------- | ----- |
| `fsid` | The UUID of the respective Ceph deployment. Contained in `ceph.conf`. |
| `mon_host` | Specially-crafted list of Ceph monitor hosts. Contained in `ceph.conf`. |
| Ceph `cinder` client key | The Ceph key used to operate as the `cinder` user in Ceph |

### Step 1: Configure Ceph for Nova

Prior to configuring Nova to support an external Ceph deployment, you must first configure users and pools within Ceph. The examples below are provided as reference only, and may not be applicable to your environment. An assumption is made that Ceph is operational and OSDs have been made available for use.

#### Step 1a: Create and Initialize a Pool

```bash
ceph osd pool create vms
rbd pool init vms
```

#### Step 1b: Disable Autoscaling (optional)

```bash
ceph osd pool set vms pg_autoscale_mode off
```

#### Step 1c: Set Placement Groups on the Pool

```bash
ceph osd pool set vms pg_num 2048
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

Please note the same `ceph-etc` ConfigMap may be used for other Ceph integrations such as Glance and Cinder. The name `ceph-etc` is built in to the template and should not be overridden unless you know what you're doing.

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

### Step 4: Configure Nova to use External Ceph

Update the Nova Helm overrides at `/etc/genestack/helm-configs/nova/nova-helm-overrides.yaml` with the following configuration to connect Nova to External Ceph.

Note that the values for both `secret_uuid` and `rbd_secret_uuid` should be the same UUID generated in the previous step. The `keyring` value should match the key generated in **Step 1d**.

``` yaml
---
images:
  tags:
    nova_compute: "quay.io/airshipit/nova:2024.1-ubuntu_jammy"

conf:
  ceph:
    enabled: true
    cinder:
      secret_uuid: eea41bd9-c85e-4c99-879b-65e38ffb3213
      keyring: AQCQqXJpHtP3AhBBU6rf/yvgq92fuJqBgy3Nxg==
  nova:
    libvirt:
      images_type: rbd
      images_rbd_pool: vms
      images_rbd_ceph_conf: /etc/ceph/ceph.conf
      rbd_secret_uuid: eea41bd9-c85e-4c99-879b-65e38ffb3213
      force_raw_images: true
      volume_use_multipath: false
```

Please note the upstream container images are required for Ceph support at this time.

### Step 5: Configure Libvirt to use External Ceph

Update the Libvirt Helm overrides at `/etc/genestack/helm-configs/libvirt/libvirt-helm-overrides.yaml` with the following configuration to connect Libvirt to External Ceph.

Note that the value for both `secret_uuid` should be the same UUID generated in **Step 3**. The `keyring` value should match the key generated in **Step 1d**.

``` yaml
---
images:
  tags:
    libvirt: "docker.io/openstackhelm/libvirt:2024.1-ubuntu_jammy"

conf:
  ceph:
    enabled: true
    cinder:
      keyring: AQCQqXJpHtP3AhBBU6rf/yvgq92fuJqBgy3Nxg==
      secret_uuid: eea41bd9-c85e-4c99-879b-65e38ffb3213
      external_ceph:
        enabled: true
        user: cinder
        secret_uuid: eea41bd9-c85e-4c99-879b-65e38ffb3213
        user_secret_name: pvc-ceph-client-key
```

Please note the upstream container images are required for Ceph support at this time.


### Step 6: Apply the Configuration

Apply the configuration to the Nova Helm chart.

``` bash
/opt/genestack/bin/install-nova.sh
```

Once the configuration has been applied, Nova will be configured to use an external Ceph deployment for image storage. Instances deployed from image (not boot-from-volume) should automatically use the external Ceph RBD backend.
