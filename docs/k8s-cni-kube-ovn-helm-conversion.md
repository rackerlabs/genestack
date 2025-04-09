# Kube OVN Helm Conversion

If you are using the Kube-OVN project, and it was deployed by hand or through another system you
can convert your existing Kube-OVN deployment to a Helm chart. This will allow you to manage your
Kube-OVN deployment using Helm.

## Prerequisites

Before converting take a look at your `ovn-default` and `join` networks and note the CIDR ranges.
To ensure that the conversion is successful and does not cause any network conflicts, you will need to
ensure that the CIDR ranges for the `ovn-default` and `join` networks are defined in the
`/etc/genestack/helm-configs/kube-ovn/kube-ovn-helm-overrides.yaml` file.

### Label Kube-OVN nodes

| <div style="width:220px">key</div> | type | <div style="width:128px">value</div>  | notes |
|:-----|--|:----------------:|:------|
| **kube-ovn/role** | str | `master` | Defines where the Kube-OVN Masters will reside |
| **ovn.kubernetes.io/ovs_dp_type** | str | `kernel` | (Optional) Defines OVS DPDK mode |

!!! example "Label all controllers as Kube-OVN control plane nodes"

    ``` shell
    kubectl label node -l beta.kubernetes.io/os=linux kubernetes.io/os=linux
    kubectl label node -l node-role.kubernetes.io/control-plane kube-ovn/role=master
    kubectl label node -l ovn.kubernetes.io/ovs_dp_type!=userspace ovn.kubernetes.io/ovs_dp_type=kernel
    ```

### Fact Gathering

Before getting started you will need to know a few pieces of information: the network interface used
for the cluster, and the CIDR ranges for the `ovn-default` and `join` networks.

!!! example "Output"

    You can get the network interface used for the cluster by running the following command.

    ``` shell
    kubectl get subnets.kubeovn.io
    ```

    The output will return most everything needed.

    ``` shell
    NAME          PROVIDER   VPC           PROTOCOL   CIDR            PRIVATE   NAT     DEFAULT   GATEWAYTYPE   V4USED   V4AVAILABLE   V6USED   V6AVAILABLE   EXCLUDEIPS       U2OINTERCONNECTIONIP
    join          ovn        ovn-cluster   IPv4       100.64.0.0/16   false     false   false     distributed   3        65530         0        0             ["100.64.0.1"]
    ovn-default   ovn        ovn-cluster   IPv4       10.236.0.0/14   false     true    true      distributed   111      262030        0        0             ["10.236.0.1"]
    ```

In this example the following values will be used in the configuration.

* The gateway address for the join network is `100.64.0.1` and the CIDR range is `100.64.0.0/16`
* The gateway address for the ovn-default network is `10.236.0.1` and the CIDR range is `10.236.0.0/14`

!!! tip

    If the installation was originally done with Kubespray the required values can typically be found
    in the `/etc/genestack/inventory/group_vars/k8s_cluster/k8s-cluster.yml` file or in the inventory.

    * `kube_service_addresses` is used for the Service CIDR
    * `kube_pods_subnet` is used for the ovn-default CIDR
    * `kube_ovn_node_switch_cidr` is used for the join CIDR
    * `kube_ovn_default_interface_name` is used for the VLAN interface
    * `kube_ovn_iface` is used for the interface

With the required information, update the `/etc/genestack/helm-configs/kube-ovn/kube-ovn-helm-overrides.yaml` file
with following content.

``` yaml
ipv4:
  POD_CIDR: "10.236.0.0/14"  # ovn-default CIDR
  POD_GATEWAY: "10.236.0.1"  # ovn-default CIDR
  SVC_CIDR: "10.233.0.0/18"  # Service CIDR
  JOIN_CIDR: "100.64.0.0/16"  # join

networking:
  IFACE: "br-overlay"  # Interface used for the cluster
  vlan:
    VLAN_INTERFACE_NAME: "br-overlay"  # VLAN Interface used for the cluster
```

## Running the Upgrade

Upgrade the Kube-OVN deployment to a Helm chart is simple and quick. Get it done by running the
`kube-ovn-convert.sh` script.

??? example "Run the Kube-OVN deployment Script `/opt/genestack/scripts/kube-ovn-convert.sh`."

    ``` shell
    --8<-- "scripts/kube-ovn-convert.sh"
    ```

After converting the Kube-OVN deployment to a Helm chart, you can manage the deployment using Helm commands.
To ensure there's no future conflict with the Kube-OVN deployment, you can reset the network plugin option
deployment options from the `/etc/genestack/inventory/group_vars/k8s_cluster/k8s-cluster.yml` file.

Set the value `kube_network_plugin` to **`none`**.

``` diff
--- a/inventory/group_vars/k8s_cluster/k8s-cluster.yml
+++ b/inventory/group_vars/k8s_cluster/k8s-cluster.yml
@@ -67,7 +67,7 @@ credentials_dir: "{{ inventory_dir }}/credentials"

 # Choose network plugin (cilium, calico, kube-ovn, weave, flannel or none. Use cni for generic cni plugin)
 # Can also be set to 'cloud', which lets the cloud provider setup appropriate routing
-kube_network_plugin: kube-ovn
+kube_network_plugin: none
```

This will ensure that any future Kubspray operations will not deploy with a network plugin and not
create a conflict in the Kube-OVN deployment.
