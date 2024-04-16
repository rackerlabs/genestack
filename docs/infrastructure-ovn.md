# Deploy Open vSwitch OVN

Note that we're not deploying Openvswitch, however, we are using it. The implementation on Genestack is assumed to be
done with Kubespray which deploys OVN as its networking solution. Because those components are handled by our infrastructure
there's nothing for us to manage / deploy in this environment. OpenStack will leverage OVN within Kubernetes following the
scaling/maintenance/management practices of kube-ovn.
