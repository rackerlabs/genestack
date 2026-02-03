# Placeholder

## Add neutron overrides 

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
      password: <neutron_user_password_from_secret>
      project_name: service
      project_domain_name: service
      user_domain_name: service
      region_name: RegionOne
      allow_reverse_dns_lookup: true
      ipv4_ptr_zone_prefix_size: 24
      ipv6_ptr_zone_prefix_size: 116
  plugins:
    ml2_conf:
      ml2:
        extension_drivers: "port_security,qos,dns,dns_domain_ports,subnet_dns_publish_fixed_ip,dns_domain_keywords"
```

## Re-Deploy Neutron

```bash
/opt/genestack/bin/install-neutron.sh
```
