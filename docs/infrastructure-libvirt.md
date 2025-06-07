# Deploy Libvirt

The first part of the compute kit is Libvirt.

## Run the package deployment

!!! example "Run the libvirt deployment Script `/opt/genestack/bin/install-libvirt.sh`"

    ``` shell
    --8<-- "bin/install-libvirt.sh"
    ```

Once deployed you can validate functionality on your compute hosts with `virsh`

``` shell
kubectl exec -it $(kubectl get pods -l application=libvirt -o=jsonpath='{.items[0].metadata.name}' -n openstack) -n openstack -- virsh list
```
