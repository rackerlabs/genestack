# Configuring OpenStack Networking for DNS Integration

Guide for how to use the DNS integration functionality of the Networking service and its interaction with the Compute service.
The integration of the Networking service with an external DNSaaS (DNS-as-a-Service)
Users can control the behavior of the Networking service in regards to DNS using two attributes associated with ports, networks, and floating IPs

## Add a neutron overrides neutron-helm-designate-overrides.yaml

Add the following to file in /etc/genestack/helm-configs/neutron/neutron-helm-designate-overrides.yaml

```bash
---
conf:
  neutron:
    DEFAULT:
      dns_domain: "cluster.local"
      external_dns_driver: designate
    designate:
      url: http://designate-api.openstack.svc.cluster.local:9001/v2
      auth_type: password
      auth_url: http://keystone-api.openstack.svc.cluster.local:5000/v3
      username: neutron
      password: <NEUTRON_USER_PASSWORD> 
      project_name: service
      project_domain_name: service
      user_domain_name: service
      region_name: RegionOne  # Change if needed
      allow_reverse_dns_lookup: True
      ipv4_ptr_zone_prefix_size: 24
      ipv6_ptr_zone_prefix_size: 116
  plugins:
    ml2_conf:
      ml2:
        extension_drivers: "port_security,qos,dns_domain_ports,subnet_dns_publish_fixed_ip"
```

!!! Note "Get the Neutron user password run the following"

```bash
kubectl get secret -n openstack neutron-admin -o jsonpath='{.data.password}' | base64 -d
```

## Re-Deploy Neutron

```bash
/opt/genestack/bin/install-neutron.sh
```

## Validation

```bash
# Check if plugins enabled
openstack extension list --network -f value -c Alias | grep dns
# Modify or Create network
openstack network set --dns-domain example.net. <NEUTRON_NET>
# Modify or Create Subnet
openstack subnet set --dns-publish-fixed-ip <SUBNET_ID>
```

- Create a VM with a port on that subnet
- Check Designate command for A record

```bash
openstack recordset list <zone>
```
