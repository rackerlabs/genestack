# Deploy Libvirt

The first part of the compute kit is Libvirt.

``` shell
kubectl kustomize --enable-helm /opt/genestack/kustomize/libvirt | kubectl apply --namespace openstack -f -
```

Once deployed you can validate functionality on your compute hosts with `virsh`

``` shell
root@openstack-flex-node-3:~# virsh
Welcome to virsh, the virtualization interactive terminal.

Type:  'help' for help with commands
       'quit' to quit

virsh # list
 Id   Name   State
--------------------

virsh #
```
