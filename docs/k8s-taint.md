# Post deployment Operations

## Remove taint from our Controllers

In an environment with a limited set of control plane nodes removing the NoSchedule will allow you to converge the
openstack controllers with the k8s controllers.

``` shell
# Remote taint from control-plane nodes
kubectl taint nodes $(kubectl get nodes -o 'jsonpath={.items[*].metadata.name}') node-role.kubernetes.io/control-plane:NoSchedule-
```
