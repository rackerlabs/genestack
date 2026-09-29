# VPNaaS with OVN

Genestack configures Neutron VPNaaS with the OVN StrongSwan driver. The base
Neutron values already provide:

- The `ovn-vpnaas` service plugin.
- The `IPsecOvnVPNDriver` service provider.
- The OVN StrongSwan device driver and VPN agent DaemonSet.
- RabbitMQ, OVN northbound, and OVN southbound connection settings through the
  configuration files loaded by the agent.

Each environment must select the OVN gateway nodes that may run the VPN agent
and enable the Neutron RPC server.

## Label the OVN gateway nodes

Apply the dedicated label only to nodes configured as OVN gateway chassis:

``` shell
kubectl label node <gateway-node> openstack-ovn-vpn-agent=enabled
```

Repeat the command for every gateway node that should host VPN services. Verify
the resulting placement set:

``` shell
kubectl get nodes \
  -l openstack-ovn-vpn-agent=enabled \
  -o custom-columns=NAME:.metadata.name,LABEL:.metadata.labels.openstack-ovn-vpn-agent
```

An OVN gateway chassis has `enable-chassis-as-gw` in its CMS options. You can
check a node through an OVN-enabled pod running on that node:

``` shell
ovs-vsctl --db=tcp:127.0.0.1:6640 \
  get Open_vSwitch . external_ids:ovn-cms-options
```

!!! warning

    Do not label ordinary compute nodes. Compute nodes may have
    `openstack-network-node=enabled` because they run OVN networking components,
    but that does not make them gateway chassis. VPN agents share an RPC queue;
    an agent placed on a non-gateway compute can consume an update and fail while
    creating or opening the router's `qvpn-*` network namespace.

## Configure Neutron

Create a dedicated per-cluster override such as
`/etc/genestack/helm-configs/neutron/neutron-vpnaas-overrides.yaml` with the
following values:

``` yaml
labels:
  agent:
    ovn_vpn:
      node_selector_key: openstack-ovn-vpn-agent
      node_selector_value: enabled

manifests:
  deployment_rpc_server: true
```

The Neutron installation script loads every YAML file in
`/etc/genestack/helm-configs/neutron/`, so the exact filename is optional. A
feature-specific file keeps the VPNaaS settings easy to identify and maintain.

The RPC server is required because current Neutron releases separate agent RPC
handling from the API server. Without it, VPN connections remain in
`PENDING_CREATE` and the VPN agent logs timeouts for
`get_vpn_services_on_host`.

Do not duplicate `transport_url`, RabbitMQ credentials, `ovn_nb_connection`, or
`ovn_sb_connection` under `conf.ovn_vpn_agent`. The OpenStack-Helm startup
command loads the shared Neutron and OVN configuration files in addition to
`neutron_ovn_vpn_agent.ini`.

Apply the configuration:

``` shell
/opt/genestack/bin/install-neutron.sh
```

## Validate the deployment

Confirm that the RPC server is available:

``` shell
kubectl --namespace openstack get deployment neutron-rpc-server
```

Confirm that every VPN-agent pod is running on a labeled gateway node:

``` shell
kubectl --namespace openstack get pods -o wide \
  -l application=neutron,component=ovn-vpn-agent
```

If a VPN connection remains in `PENDING_CREATE`, inspect the RPC server and VPN
agent logs. A transition to `DOWN` means the RPC create request was processed;
continue by checking the IPsec peer configuration and tunnel reachability.

An error such as `OSError: [Errno 22] failed to open netns` on a compute node
usually indicates that the VPN agent was scheduled outside the OVN gateway
nodes. Correct the label and selector placement before cleaning up any stale
`qvpn-*` namespace.
