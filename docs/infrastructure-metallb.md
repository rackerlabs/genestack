# Setup the MetalLB Loadbalancer

The MetalLb loadbalancer can be setup by editing the following file `metallb-openstack-service-lb.yml`, You will need to add
your "external" VIP(s) to the loadbalancer so that they can be used within services. These IP addresses are unique and will
need to be customized to meet the needs of your environment.

!!! tip

    When L2Advertisement is used, you should use a CIDR that is not overlapping with any local interface CIDR.
    This also enables later migration to BGP advertisement.

## Create the MetalLB namespace

``` shell
kubectl apply -f /etc/genestack/manifests/metallb/metallb-namespace.yaml
```

## Install MetalLB

!!! example "Run the MetalLB deployment Script `/opt/genestack/bin/install-metallb.sh` You can include paramaters to deploy aio or base-monitoring. No paramaters deploys base"

    ``` shell
    --8<-- "bin/install-metallb.sh"
    ```

## Example LB manifest

??? abstract "Example for `metallb-openstack-service-lb.yml` file."

    ``` yaml
    --8<-- "manifests/metallb/metallb-openstack-service-lb.yml"
    ```

!!! tip

    Edit the `/etc/genestack/manifests/metallb/metallb-openstack-service-lb.yml` file following the comment instructions with the details of your cluster.
    The file `metallb-openstack-service-lb.yml` is intially provided during bootstrap for genestack.

Verify the deployment of MetalLB by checking the pods in the `metallb-system` namespace.

``` shell
kubectl --namespace metallb-system get deployment.apps/metallb-controller
```

Once MetalLB is operatianal, apply the metallb service manifest.

``` shell
kubectl apply -f /etc/genestack/manifests/metallb/metallb-openstack-service-lb.yml
```

## Re-IP the advertisement pools

In situations where the advertisement pools must be changed, the following disruptive procedure can be used:

Update existing metallb configuration:

```shell
kubectl -n metallb-system delete IPAddressPool/primary
kubectl -n metallb-system delete IPAddressPool/gateway-api-external
kubectl apply -f /etc/genestack/manifests/metallb/metallb-openstack-service-lb.yml
```

Restart the metallb controller:

```shell
kubectl rollout restart deployment metallb-controller -n metallb-system
```

Once the metallb controller restarts it'll begin to reip the external service IP associations which typically
requires DNS entry updates. This change including the DNS refresh (TTL) time will be disruptive.

!!! tip "Node Exclusion from LoadBalancer"

    To exclude specific nodes from receiving loadbalancer traffic, you can add the following
    label to the nodes you want to exclude.

    ``` shell
    kubectl label node <node-name> node.kubernetes.io/exclude-from-external-load-balancers=true
    ```

    Replace `<node-name>` with the name of the node you want to exclude. This will prevent MetalLB
    from assigning load balancer IPs to services on that node.

    Conversely, to include a node back into loadbalancer assignments, you can remove the label.

    ``` shell
    kubectl label node <node-name> node.kubernetes.io/exclude-from-external-load-balancers-
    ```

    For more information on this well known label, refer to the
    [Kubernetes documentation](https://kubernetes.io/docs/reference/labels-annotations-taints/#node-kubernetes-io-exclude-from-external-load-balancers).
