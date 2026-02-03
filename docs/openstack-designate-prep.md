# Add pools and RNDC key

## Add designate pools file
Edit /etc/genestack/helm-configs/designate/designate-pools-helm-overrides.yaml

# Example

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
        - hostname: bind9-dns.openstack.svc.cluster.local.
          priority: 1

      # List out the nameservers for this pool. These are the actual DNS servers.
      # We use these to verify changes have propagated to all nameservers.
      nameservers:
        - host: 10.233.25.207
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
            - host: 10.233.1.155
              port: 5354

          # BIND Configuration options
          options:
            host: 10.233.25.207
            port: 53
            rndc_host: 10.233.25.207
            rndc_port: 953
            rndc_key_file: /etc/designate/rndc.key
```
