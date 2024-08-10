# Setup the MetalLB Loadbalancer

The MetalLb loadbalancer can be setup by editing the following file `metallb-openstack-service-lb.yml`, You will need to add
your "external" VIP(s) to the loadbalancer so that they can be used within services. These IP addresses are unique and will
need to be customized to meet the needs of your environment.

## Example LB manifest

``` yaml
--8<-- "manifests/metallb/metallb-openstack-service-lb.yml"
```

!!! tip

    It is recommended that you modify the file locally so that your changes are not impacted by the git tree.

    ??? example "Example for creating a local `metallb-openstack-service-lb.yml` file."

        ``` shell
        mkdir -p /etc/genestack/manifests/metallb/
        cp /opt/genestack/manifests/metallb/metallb-openstack-service-lb.yml /etc/genestack/manifests/metallb/metallb-openstack-service-lb.yml
        ```

    Edit the `metallb-openstack-service-lb.yml` file following the comment instructions with the details of your cluster.

``` shell
kubectl apply -f /etc/genestack/manifests/metallb/metallb-openstack-service-lb.yml
```
