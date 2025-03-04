# Install Kube OVN

The Kube-OVN project is a Kubernetes Network Plugin that uses OVN as the network provider. It
is a CNI plugin that provides a network solution for Kubernetes. It is a lightweight, scalable,
and easy-to-use network solution for Kubernetes.

## Prerequisites

The override values file for Kube-OVN can be found in `/etc/genestack/helm-configs/kube-ovn/kube-ovn-helm-overrides.yaml`
and should be setup-up before running the deployment. In a common production ready setup, the only values that will
likely need to be defined is the network interface that will Kube-OVN will bind to.

!!! example "Example Kube-OVN Helm Overrides"

    In the example below, the `IFACE` and `VLAN_INTERFACE_NAME` are the only values that need to be defined and
    are set to `br-overlay`. If you intend to enable hardware offloading, you will need to set the `IFACE` to the
    a physical interface that supports hardware offloading.

    ``` yaml
    networking:
      IFACE: "br-overlay"
      vlan:
        VLAN_INTERFACE_NAME: "br-overlay"
    ```

For a full review of all the available options, see the Kube-OVN base helm overrides file.

??? example "Example Kube-OVN Helm Overrides"

    ``` yaml
    --8<-- "base-helm-configs/kube-ovn/kube-ovn-helm-overrides.yaml"
    ```

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

## Deployment

To run the Kube-OVN deployment, run the following command commands or script.

!!! example "Run the Kube-OVN deployment Script `/opt/genestack/bin/install-kube-ovn.sh`."

    ``` shell
    --8<-- "bin/install-kube-ovn.sh"
    ```

### Deployment Verification

Once the script has completed, you can verify that the Kube-OVN pods are running by running the following command

``` shell
kubectl get subnets.kubeovn.io
```

!!! example "Output"

    ``` shell
    NAME          PROVIDER   VPC           PROTOCOL   CIDR            PRIVATE   NAT     DEFAULT   GATEWAYTYPE   V4USED   V4AVAILABLE   V6USED   V6AVAILABLE   EXCLUDEIPS       U2OINTERCONNECTIONIP
    join          ovn        ovn-cluster   IPv4       100.64.0.0/16   false     false   false     distributed   3        65530         0        0             ["100.64.0.1"]
    ovn-default   ovn        ovn-cluster   IPv4       10.236.0.0/14   false     true    true      distributed   111      262030        0        0             ["10.236.0.1"]
    ```

!!! tip

    After the deployment, and before going into production, it is highly recommended to review the
    [Kube-OVN Backup documentation](infrastructure-ovn-db-backup.md), from the operators guide for setting up you backups.

Upon successful deployment the Kubernetes Nodes should transition into a `Ready` state. Validate the nodes are ready by
running the following command.

``` shell
kubectl get nodes
```

!!! example "Output"

    ``` shell
    NAME                                  STATUS   ROLES                  AGE   VERSION
    compute-0.cloud.cloudnull.dev.local   Ready    control-plane,worker   24m   v1.30.4
    compute-1.cloud.cloudnull.dev.local   Ready    control-plane,worker   24m   v1.30.4
    compute-2.cloud.cloudnull.dev.local   Ready    control-plane,worker   24m   v1.30.4
    ```
