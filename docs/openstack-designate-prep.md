# Add NS Pools Config and RNDC key

Will create a example Pools config that is used by Designate service to target a Bind9 Nameserver.
This can change if using for example PowerDNS

Openstack Designate Pools Documentation [Link](https://docs.openstack.org/designate/latest/admin/pools.html)

## Add designate pools file

``` shell
vim /etc/genestack/helm-configs/designate/designate-pools-helm-overrides.yaml
```

### Example designate-pools-helm-overrides.yaml

```bash
conf:
  pools: |
    - name: default
      # The name is immutable. There will be no option to change the name after
      # creation and the only way will to change it will be to delete it
      # (and all zones associated with it) and recreate it.
      description: Default Pool

      attributes: {}

      # List out the NS records for zones hosted within this pool
      # This should be a record that is created outside of designate, in our
      # case this is the hostname of the bind9 server
      ns_records:
        - hostname: <BIND9_NS_SERVER_FQDN>.
          priority: 1

      # List out the nameservers for this pool. These are the actual DNS servers.
      # We use these to verify changes have propagated to all nameservers.
      nameservers:
        - host: <BIND9_SERVER_IP>
          port: 53

      # List out the targets for this pool. For BIND there will be one
      # entry for each BIND server, as we have to run rndc command on each server
      targets:
        - type: bind9
          description: BIND9 Server 1
          # List out the designate-mdns servers from which BIND9 servers should
          # request zone transfers (AXFRs) from.
          # This should be the IP of the controller node.
          # If you have multiple controllers you can add multiple masters
          # by running designate-mdns on them, and adding them here.
          # It's the loadbalancer IP of the mdns service
          masters:
            - host: <DESIGNATE_MDNS_SVC_IP>
              port: 5354

          # BIND Configuration options
          options:
            host: <BIND9_SERVER_IP>
            port: 53
            rndc_host: <BIND9_SERVER_IP>
            rndc_port: 953
            rndc_key_file: /etc/designate/rndc.key
```
