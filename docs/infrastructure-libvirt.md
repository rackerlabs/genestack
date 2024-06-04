# Deploy Libvirt

The first part of the compute kit is Libvirt.

``` shell
kubectl kustomize --enable-helm /opt/genestack/kustomize/libvirt | kubectl apply --namespace openstack -f -
```

Once deployed you can validate functionality on your compute hosts with `virsh`

``` shell
kubectl exec -it $(kubectl get pods -l application=libvirt -o=jsonpath='{.items[0].metadata.name}' -n openstack) -n openstack -- virsh list
```
