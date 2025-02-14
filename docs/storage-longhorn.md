# Longhorn

Longhorn is a lightweight, reliable, and highly available distributed block storage solution designed for Kubernetes. By default, it stores
its data in `/var/lib/longhorn` on each host node, keeping volumes close to where the workloads are running. This local-path approach can reduce
latency and boost performance, making Longhorn a fantastic choice for hyperconverged environments. In a hyperconverged setup, compute, networking,
and storage resources are consolidated on the same nodes, eliminating the need for separate storage servers. With Longhorn’s default storage path
and straightforward deployment, clusters become simpler to manage and scale while maintaining robust data protection, snapshots, and backups across
the infrastructure.

## Setup and Installation of the Longhorn Storage Provider

This guide walks through installing and configuring Longhorn, a lightweight, reliable, and powerful distributed block storage system for Kubernetes.
By following these steps, you'll set up the necessary host prerequisites, configure the Helm chart values, deploy Longhorn via Helm, and optionally
create an encrypted StorageClass.

### Storage Node Setup

Longhorn will create volumes under the `/var/lib/longhorn` directory on each node. Ensure that this directory has
enough space to accommodate the volumes you plan to create. If you have a separate disk or partition that you want
to use for Longhorn volumes, you can mount it at `/var/lib/longhorn` before installing Longhorn.

### Label the Storage Nodes

Longhorn can run on all of your cluster nodes, or you can restrict it to specific nodes. Labeling nodes helps control where Longhorn components (managers, drivers, etc.)
are scheduled. By labeling only certain nodes, you ensure that these nodes handle storage-related operations.

| <div style="width:220px">key</div> | type | <div style="width:128px">value</div>  | notes |
|:-----|--|:----------------:|:------|
| **longhorn.io/storage-node** | str | `enabled` | When set to "enabled" the node will be used within the Longhorn deployment |

Use the following command to label a node to be part of the Longhorn storage cluster:

``` shell
kubectl label node -l node-role.kubernetes.io/control-plane longhorn.io/storage-node=enabled
```

!!! note

    It is possible to replace `-l node-role.kubernetes.io/control-plane` with the name of your node. If you have multiple storage nodes, that are not also controllers.

### Create the Helm Values File

Before deploying Longhorn, it’s best practice to customize the chart’s values to suit your environment. One of the most common customizations is telling Longhorn where to run
its services and components—in this case, on nodes that have the label `longhorn.io/storage-node=enabled`.

1. Create the override file at `/etc/genestack/helm-configs/longhorn/longhorn.yaml`.
2. Copy the following YAML content into that file. (Adapt as needed.)

!!! example "longhorn.yaml"

    ``` yaml
    --8<-- "base-helm-configs/longhorn/longhorn-helm-overrides.yaml"
    ```

    - `nodeSelector` ensures that the respective component is only scheduled onto nodes labeled `longhorn.io/storage-node=enabled`.
    - This configuration helps separate storage responsibilities from other workloads if you have a mixed cluster.

For additional customization, you can review the full list of supported values in Longhorn’s
[values.yaml](https://raw.githubusercontent.com/longhorn/charts/master/charts/longhorn/values.yaml).

!!! tip

    While Longhorn can be used as a isolated storage cluster, it is also possible, and in some cases recommended, to run Longhorn on the same nodes as your worker nodes. To run Longhorn everywhere, remove the `nodeSelector` fields from the `longhorn.yaml` file.

### Create The Longhorn Namespace

!!! example "longhorn-namespace.yaml"

    ``` yaml
    --8<-- "manifests/longhorn/longhorn-namespace.yaml"
    ```

``` shell
kubectl apply -f /etc/genestack/manifests/longhorn/longhorn-namespace.yaml
```

### Run the Deployment

With your values file in place, you can now deploy Longhorn using the `/opt/genestack/bin/install-longhorn.sh`
command. This command will install Longhorn if it is not installed yet, or upgrade it if an older version is
already present.

??? example "Run the Longhorn deployment Script `/opt/genestack/bin/install-longhorn.sh`"

    ``` shell
    --8<-- "bin/install-longhorn.sh"
    ```

## Validate the Deployment

After the Helm deployment finishes, you’ll want to verify that everything is running correctly.

1. **Check the Longhorn pods**

   ``` shell
   kubectl -n longhorn-system get pod
   ```

   This should show multiple pods such as `longhorn-manager`, `longhorn-driver`, `longhorn-ui`, etc. They should eventually report a `Running` or `Ready` status.

2. **Check the Longhorn Nodes**

   ``` shell
   kubectl -n longhorn-system get nodes.longhorn.io
   ```

   This will show the nodes known to the Longhorn system, verifying that Longhorn has recognized and is managing them.

3. **Run a test Pod with a Longhorn Persistent Volume**

   ``` shell
   kubectl create -f https://raw.githubusercontent.com/longhorn/longhorn/v1.8.0/examples/pod_with_pvc.yaml
   ```

   This sample manifest creates a test Pod that uses a PersistentVolumeClaim (PVC) managed by Longhorn. It helps confirm that Longhorn can successfully provision and attach storage.

4. **Validate the Volume State**

   ``` shell
   kubectl -n longhorn-system get volumes.longhorn.io
   ```

You should see an entry for the newly created volume, and it should be in an attached, healthy state if everything is working.

!!! example "Example Output"

    ``` shell
    NAME                                       DATA ENGINE   STATE      ROBUSTNESS   SCHEDULED   SIZE         NODE                                  AGE
    pvc-42c89b53-f08e-4d69-9d4d-cd2297f2c280   v1            attached   healthy                  2147483648   compute-0.cloud.cloudnull.dev.local   54s
    ```

Once you verify the test deployment, you can remove the Pod and related resources if you like. This helps keep your cluster clean if the test is no longer needed.

## StorageClass Configuration

The Longhorn StorageClass is a Kubernetes resource that defines how PersistentVolumeClaims (PVCs) are provisioned.
By creating a StorageClass, you can specify the default settings for Longhorn volumes, such as the number of
replicas, data locality, and more. This section will guide you through creating a general-purpose StorageClass and
an optional encrypted StorageClass.

For a generic StorageClass and an overview of common properties, review the upstream
[example](https://github.com/longhorn/longhorn/blob/master/examples/storageclass.yaml). You can also review the Longhorn
[documentation](https://longhorn.io/docs/1.7.2/references/storage-class-parameters/#longhorn-specific-parameters)
for more information on StorageClasses.

!!! note

    The Longhorn StorageClass created here will use two custom parameters: `numberOfReplicas` and `dataLocality`. While these have default values, they can be adjusted to better suit the needs of the cloud environment.

    - The `numberOfReplicas` parameter specifies the number of replicas for built PVC. While the common default is "3" for redundancy, you can adjust this value
      based on your requirements.

    - The `dataLocality` parameter controls how Longhorn places replicas.
        - For "**disabled**", replicas are placed on different nodes.
        - For "**best-effort**", a replica will be co-located if possible, but is permitted to find another node if not.
        - For "**strict-local**" the Replica count should be **1**, or volume creation will fail with a parameter validation error. This option enforces Longhorn keep the only one replica on the same node as the attached volume, and therefore, it offers higher IOPS and lower latency performance.

### General StorageClass

Longhorn will provide two default StorageClasses: `longhorn` and `longhorn-static`.

- The `longhorn` StorageClass is marked as **default** and is suitable for most use cases. It dynamically provisions volumes with the default settings.
- The `longhorn-static` StorageClass is for users who want to manually specify the number of replicas for a volume. This StorageClass is useful for
  workloads that require a specific number of replicas for data redundancy.

For the purposes of Genestack, it is recommended that you create the `general` StorageClass to avoid deployment confusion.

!!! example "longhorn-general-storageclass.yaml"

    ``` yaml
    --8<-- "manifests/longhorn/longhorn-general-storageclass.yaml"
    ```

Apply the general storage class manifest to create the StorageClass.

``` shell
kubectl apply -f /etc/genestack/manifests/longhorn/longhorn-general-storageclass.yaml
```

With the `general` StorageClass in place, you can now create PVCs that reference it to dynamically provision Longhorn volumes with the desired settings.

### (Optional) Create an Encrypted StorageClass

If you want to enable data encryption, you can create an encrypted StorageClass. This feature encrypts the data at rest within the Longhorn volumes. Opting for the
encryption feature, your data remains secure and encrypted on the underlying disks.

#### Steps to Create an Encrypted StorageClass

1. **Generate a global secret** containing the encryption passphrase (or key).
2. **Create the encrypted StorageClass** that references this secret, ensuring that volumes created using this StorageClass are automatically encrypted.

Below is an example combined manifest. Save this content to `/etc/genestack/manifests/longhorn-encrypted-storageclass.yaml`.

!!! example "longhorn-encrypted-storageclass.yaml"

    ``` yaml
    --8<-- "manifests/longhorn/longhorn-encrypted-storageclass.yaml"
    ```

!!! info "Explanation of Key Fields"

    **Secret References**: Points to the `longhorn-crypto` secret so that the driver can retrieve encryption keys.

    **Secret**

    - `CRYPTO_KEY_VALUE`: The encryption passphrase/string.
    - `CRYPTO_KEY_PROVIDER`: Specifies which key provider Longhorn uses (in this case, `secret`).
    - `CRYPTO_KEY_CIPHER`: The cipher algorithm (e.g., `aes-xts-plain64`).
    - `CRYPTO_KEY_SIZE`: The encryption key size in bits.
    - `CRYPTO_PBKDF`: Determines the password-based key derivation function.

    **StorageClass**

    - `provisioner: driver.longhorn.io`: Uses the Longhorn CSI driver.
    - `allowVolumeExpansion: true`: Allows you to resize volumes after creation.
    - `reclaimPolicy: Delete`: Automatically deletes the underlying volume when the PVC is deleted.
    - `encrypted: "true"`: Ensures volumes are encrypted.

Apply the encrypted storage class manifest to create the StorageClass.

``` shell
kubectl apply -f /etc/genestack/manifests/longhorn/longhorn-encrypted-storageclass.yaml
```

After applying this manifest, a new `StorageClass` named `general-encrypted` will be available. Any PVC you create referencing this StorageClass will
automatically generate an encrypted Longhorn volume.

## Conclusion

With Longhorn deployed and the StorageClass created, you can now use it in your PVCs to dynamically provision Longhorn volumes with the desired settings.
Longhorn should now be operating as a high-availability, cloud-native storage solution in your Kubernetes environment. You can use Longhorn’s UI or CLI
to manage and monitor volumes, snapshots, backups, and more.

Review the upstream Longhorn [documentation](https://longhorn.io/docs) for more information on how to use the Longhorn UI and CLI.
