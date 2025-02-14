# Setup the MetalLB Loadbalancer

The MetalLb loadbalancer can be setup by editing the following file `metallb-openstack-service-lb.yml`, You will need to add
your "external" VIP(s) to the loadbalancer so that they can be used within services. These IP addresses are unique and will
need to be customized to meet the needs of your environment.

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

    It is recommended that you modify the file locally so that your changes are not impacted by the git tree.

    ``` shell
    mkdir -p /etc/genestack/manifests/metallb/
    cp /etc/genestack/manifests/metallb/metallb-openstack-service-lb.yml /etc/genestack/manifests/metallb/metallb-openstack-service-lb.yml
    ```

    Edit the `metallb-openstack-service-lb.yml` file following the comment instructions with the details of your cluster.

Verify the deployment of MetalLB by checking the pods in the `metallb-system` namespace.

``` shell
kubectl --namespace metallb-system get deployment.apps/metallb-controller
```

Once MetalLB is operatoinal, apply the metallb service manifest.

``` shell
kubectl apply -f /etc/genestack/manifests/metallb/metallb-openstack-service-lb.yml
```
