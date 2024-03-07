# Post deployment Operations

## Remove taint from our Controllers

In an environment with a limited set of control plane nodes removing the NoSchedule will allow you to converge the
openstack controllers with the k8s controllers.

``` shell
# Remote taint from control-plane nodes
kubectl taint nodes $(kubectl get nodes -o 'jsonpath={.items[*].metadata.name}') node-role.kubernetes.io/control-plane:NoSchedule-
```

## Optional - Deploy K8S Dashboard RBAC

While the dashboard is installed you will have no ability to access it until we setup some basic RBAC.

``` shell
kubectl apply -k /opt/genestack/kustomize/k8s-dashboard
```

You can now retrieve a permanent token.

``` shell
kubectl get secret admin-user -n kube-system -o jsonpath={".data.token"} | base64 -d
```

## Label all of the nodes in the environment

> The following example assumes the node names can be used to identify their purpose within our environment. That
  may not be the case in reality. Adapt the following commands to meet your needs.

``` shell
# Label the storage nodes - optional and only used when deploying ceph for K8S infrastructure shared storage
kubectl label node $(kubectl get nodes | awk '/ceph/ {print $1}') role=storage-node

# Label the openstack controllers
kubectl label node $(kubectl get nodes | awk '/controller/ {print $1}') openstack-control-plane=enabled

# Label the openstack compute nodes
kubectl label node $(kubectl get nodes | awk '/compute/ {print $1}') openstack-compute-node=enabled

# Label the openstack network nodes
kubectl label node $(kubectl get nodes | awk '/network/ {print $1}') openstack-network-node=enabled

# Label the openstack storage nodes
kubectl label node $(kubectl get nodes | awk '/storage/ {print $1}') openstack-storage-node=enabled

# With OVN we need the compute nodes to be "network" nodes as well. While they will be configured for networking, they wont be gateways.
kubectl label node $(kubectl get nodes | awk '/compute/ {print $1}') openstack-network-node=enabled

# Label all workers - Recommended and used when deploying Kubernetes specific services
kubectl label node $(kubectl get nodes | awk '/worker/ {print $1}')  node-role.kubernetes.io/worker=worker
```

Check the node labels

``` shell
# Verify the nodes are operational and labled.
kubectl get nodes -o wide --show-labels=true
```

``` shell
# Here is a way to make it look a little nicer:
kubectl get nodes -o json | jq '[.items[] | {"NAME": .metadata.name, "LABELS": .metadata.labels}]'
```
