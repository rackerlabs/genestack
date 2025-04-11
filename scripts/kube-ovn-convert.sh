#!/usr/bin/env -S bash
set -e

function helmLabelMaker() {
    kubectl -n kube-system annotate "$1" meta.helm.sh/release-name=kube-ovn meta.helm.sh/release-namespace=kube-system
    kubectl -n kube-system label "$1" app.kubernetes.io/managed-by=Helm
}

kubectl label node -l beta.kubernetes.io/os=linux kubernetes.io/os=linux
kubectl label node -l node-role.kubernetes.io/control-plane kube-ovn/role=master
kubectl label node -l ovn.kubernetes.io/ovs_dp_type!=userspace ovn.kubernetes.io/ovs_dp_type=kernel

helmLabelMaker "serviceaccounts/ovn"
helmLabelMaker "serviceaccounts/ovn-ovs"
helmLabelMaker "serviceaccounts/kube-ovn-cni"
helmLabelMaker "serviceaccounts/kube-ovn-app"

helmLabelMaker "configmaps/ovn-vpc-nat-config"
helmLabelMaker "configmaps/ovn-vpc-nat-gw-config"

helmLabelMaker "customresourcedefinitions.apiextensions.k8s.io/vpc-dnses.kubeovn.io"
helmLabelMaker "customresourcedefinitions.apiextensions.k8s.io/switch-lb-rules.kubeovn.io"
helmLabelMaker "customresourcedefinitions.apiextensions.k8s.io/vpc-nat-gateways.kubeovn.io"
helmLabelMaker "customresourcedefinitions.apiextensions.k8s.io/iptables-eips.kubeovn.io"
helmLabelMaker "customresourcedefinitions.apiextensions.k8s.io/iptables-fip-rules.kubeovn.io"
helmLabelMaker "customresourcedefinitions.apiextensions.k8s.io/iptables-dnat-rules.kubeovn.io"

helmLabelMaker "customresourcedefinitions.apiextensions.k8s.io/iptables-snat-rules.kubeovn.io"
helmLabelMaker "customresourcedefinitions.apiextensions.k8s.io/ovn-eips.kubeovn.io"
helmLabelMaker "customresourcedefinitions.apiextensions.k8s.io/ovn-fips.kubeovn.io"
helmLabelMaker "customresourcedefinitions.apiextensions.k8s.io/ovn-snat-rules.kubeovn.io"
helmLabelMaker "customresourcedefinitions.apiextensions.k8s.io/ovn-dnat-rules.kubeovn.io"
helmLabelMaker "customresourcedefinitions.apiextensions.k8s.io/vpcs.kubeovn.io"
helmLabelMaker "customresourcedefinitions.apiextensions.k8s.io/ips.kubeovn.io"
helmLabelMaker "customresourcedefinitions.apiextensions.k8s.io/vips.kubeovn.io"
helmLabelMaker "customresourcedefinitions.apiextensions.k8s.io/subnets.kubeovn.io"
helmLabelMaker "customresourcedefinitions.apiextensions.k8s.io/ippools.kubeovn.io"
helmLabelMaker "customresourcedefinitions.apiextensions.k8s.io/vlans.kubeovn.io"
helmLabelMaker "customresourcedefinitions.apiextensions.k8s.io/provider-networks.kubeovn.io"
helmLabelMaker "customresourcedefinitions.apiextensions.k8s.io/security-groups.kubeovn.io"
helmLabelMaker "customresourcedefinitions.apiextensions.k8s.io/qos-policies.kubeovn.io"

helmLabelMaker "clusterrole/system:ovn"
helmLabelMaker "clusterrole/system:ovn-ovs"
helmLabelMaker "clusterrole/system:kube-ovn-cni"
helmLabelMaker "clusterrole/system:kube-ovn-app"

helmLabelMaker "clusterrolebindings.rbac.authorization.k8s.io/ovn"
helmLabelMaker "clusterrolebindings.rbac.authorization.k8s.io/ovn-ovs"
helmLabelMaker "clusterrolebindings.rbac.authorization.k8s.io/kube-ovn-cni"
helmLabelMaker "clusterrolebindings.rbac.authorization.k8s.io/kube-ovn-app"

helmLabelMaker "rolebindings.rbac.authorization.k8s.io/ovn"
helmLabelMaker "rolebindings.rbac.authorization.k8s.io/kube-ovn-cni"
helmLabelMaker "rolebindings.rbac.authorization.k8s.io/kube-ovn-app"

helmLabelMaker "services/kube-ovn-controller"
helmLabelMaker "services/kube-ovn-monitor"
helmLabelMaker "services/ovn-nb"
helmLabelMaker "services/ovn-northd"
helmLabelMaker "services/kube-ovn-cni"
helmLabelMaker "services/kube-ovn-pinger"
helmLabelMaker "services/ovn-sb"

helmLabelMaker "daemonsets.apps/kube-ovn-cni"
helmLabelMaker "daemonsets.apps/ovs-ovn"
helmLabelMaker "daemonsets.apps/kube-ovn-pinger"

helmLabelMaker "deployments.apps/ovn-central"
helmLabelMaker "deployments.apps/kube-ovn-controller"
helmLabelMaker "deployments.apps/kube-ovn-monitor"

if [ ! -f "/etc/genestack/helm-configs/kube-ovn/kube-ovn-helm-overrides.yaml" ]; then
    mkdir -p /etc/genestack/helm-configs/kube-ovn
    echo "---" | tee /etc/genestack/helm-configs/kube-ovn/kube-ovn-helm-overrides.yaml
fi

/opt/genestack/bin/install-kube-ovn.sh
