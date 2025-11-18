# Enhanced Gateway Setup

The `setup-envoy-gateway.sh` script has been enhanced to support multiple gateways with different configurations, allowing for more flexible deployments that can separate external and internal services with appropriate security configurations.

## Features

- **Multiple Gateways**: Configure multiple gateways with different domains and purposes
- **Namespace Isolation**: Each gateway runs in its own namespace for better security and organization
- **Hybrid Gateway Support**: Gateways can be external-only, internal-only, or both (hybrid)
- **Flexible Certificate Management**: Choose between Let's Encrypt or self-signed certificates per gateway
- **Route Segregation**: Assign specific OpenStack services to specific gateways
- **Security Zones**: Separate external-facing services from internal monitoring/admin tools
- **DNS Challenge Support**: Full support for DNS01 challenges with multiple providers
- **Multiple MetalLB Pools**: Support for different MetalLB address pools for external and internal access

## Usage Modes

### 1. Configuration File Mode (Recommended)

Create a YAML configuration file and use it with the script:

```bash
./bin/setup-envoy-gateway.sh --config /path/to/gateway-config.yaml
```

### 2. Legacy Single Gateway Mode

For backward compatibility, the original single gateway setup is still supported:

```bash
# With Let's Encrypt
./bin/setup-envoy-gateway.sh --email admin@example.com --domain cloud.example.com

# With DNS01 challenge
./bin/setup-envoy-gateway.sh --email admin@example.com --domain cloud.example.com \
  --challenge dns01 --dns-plugin cloudflare --api-token YOUR_TOKEN
```

### 3. Interactive Mode

Run without parameters for interactive prompts:

```bash
./bin/setup-envoy-gateway.sh
```

## Configuration File Format

```yaml
gateways:
  - name: external-gateway              # Required: Gateway name
    namespace: external-gateway         # Optional: Namespace (defaults to gateway name)
    domain: cloud.example.com           # Required: Domain for the gateway
    type:                               # Required: List of gateway types
      - external                        # Can be: external, internal, or both
    metallb_pools:                      # Required: MetalLB address pools
      external: gateway-api-external    # Pool for external access
      internal: gateway-api-internal    # Pool for internal access (optional)
    issuer:
      type: letsencrypt                 # Required: letsencrypt or selfsigned
      email: admin@example.com          # Required for letsencrypt
      challenge: http01                 # Optional: http01 or dns01 (default: http01)
      dns_plugin: cloudflare           # Optional: DNS plugin for dns01
      api_token: "your-token"          # DNS provider credentials (varies by provider)
    routes:                            # Optional: List of services to route through this gateway
      - keystone
      - nova
      - neutron
```

## Common Deployment Patterns

### Pattern 1: External + Internal Separation

```yaml
gateways:
  # External gateway for user-facing OpenStack APIs
  - name: external-gateway
    namespace: external-gateway
    domain: cloud.example.com
    type: 
      - external
    metallb_pools:
      external: gateway-api-external
    issuer:
      type: letsencrypt
      email: admin@example.com
      challenge: http01
    routes:
      - keystone
      - nova
      - neutron
      - cinder
      - glance
      - heat
      - octavia
      - placement

  # Internal gateway for monitoring and admin tools
  - name: internal-gateway
    namespace: internal-gateway
    domain: internal.cluster.local
    type: 
      - internal
    metallb_pools:
      internal: gateway-api-internal
    issuer:
      type: selfsigned
    routes:
      - grafana
      - prometheus
      - alertmanager
```

### Pattern 2: Environment Separation

```yaml
gateways:
  # Production gateway with DNS01 challenge
  - name: prod-gateway
    namespace: prod-gateway
    domain: cloud.example.com
    type:
      - external
    metallb_pools:
      external: gateway-api-prod
    issuer:
      type: letsencrypt
      email: admin@example.com
      challenge: dns01
      dns_plugin: cloudflare
      api_token: "prod-token"
    routes:
      - keystone
      - nova
      - neutron

  # Development gateway with self-signed certs
  - name: dev-gateway
    namespace: dev-gateway
    domain: dev.example.com
    type:
      - external
    metallb_pools:
      external: gateway-api-dev
    issuer:
      type: selfsigned
    routes:
      - keystone
      - nova
      - skyline
```

### Pattern 3: Service Segregation

```yaml
gateways:
  # Core compute services
  - name: compute-gateway
    namespace: compute-gateway
    domain: compute.example.com
    type:
      - external
    metallb_pools:
      external: gateway-api-compute
    issuer:
      type: letsencrypt
      email: admin@example.com
    routes:
      - keystone
      - nova
      - placement
      - neutron

  # Storage services
  - name: storage-gateway
    namespace: storage-gateway
    domain: storage.example.com
    type:
      - external
    metallb_pools:
      external: gateway-api-storage
    issuer:
      type: letsencrypt
      email: admin@example.com
    routes:
      - cinder
      - glance

  # Orchestration services
  - name: orchestration-gateway
    namespace: orchestration-gateway
    domain: orchestration.example.com
    type:
      - external
    metallb_pools:
      external: gateway-api-orchestration
    issuer:
      type: letsencrypt
      email: admin@example.com
    routes:
      - heat
      - magnum
```

### Pattern 4: Hybrid Gateway (External + Internal)

```yaml
gateways:
  # Hybrid gateway accessible both externally and internally
  - name: hybrid-gateway
    namespace: hybrid-gateway
    domain: cloud.example.com
    type:
      - external
      - internal
    metallb_pools:
      external: gateway-api-external
      internal: gateway-api-internal
    issuer:
      type: letsencrypt
      email: admin@example.com
      challenge: http01
    routes:
      - keystone  # Available on both external (port 443) and internal (port 443)
      - nova      # Available on both external (port 443) and internal (port 443)
      - grafana   # Available on both external (port 443) and internal (port 443)

  # Pure internal gateway for sensitive admin operations
  - name: admin-gateway
    namespace: admin-gateway
    domain: admin.cluster.local
    type:
      - internal
    metallb_pools:
      internal: gateway-api-admin
    issuer:
      type: selfsigned
    routes:
      - prometheus
      - alertmanager
```

## Available Routes

The following OpenStack services can be routed through gateways:

- `keystone` - Identity service
- `nova` - Compute service
- `neutron` - Networking service
- `cinder` - Block storage service
- `glance` - Image service
- `heat` - Orchestration service
- `octavia` - Load balancing service
- `placement` - Placement service
- `magnum` - Container orchestration service
- `barbican` - Key management service
- `blazar` - Resource reservation service
- `cloudkitty` - Billing service
- `freezer` - Backup service
- `ironic` - Bare metal service
- `masakari` - Instance high availability service
- `skyline` - Modern dashboard
- `grafana` - Monitoring dashboard
- `prometheus` - Metrics collection
- `alertmanager` - Alert management
- `loki` - Log aggregation

## Architecture

### Namespace Isolation
Each gateway is deployed in its own namespace, providing:
- **Security isolation**: Resources are separated by namespace boundaries
- **RBAC control**: Fine-grained access control per gateway
- **Resource management**: Independent resource quotas and limits
- **Operational clarity**: Clear separation of concerns

### Gateway Types and Ports
- **External gateways**: Use standard ports 80/443 with external MetalLB pools
- **Internal gateways**: Use standard ports 80/443 with internal MetalLB pools  
- **Hybrid gateways**: Create separate gateway instances for each type:
  - `gateway-name-external`: Ports 80/443 with external pool
  - `gateway-name-internal`: Ports 80/443 with internal pool

### Route Distribution
Routes are automatically created for each gateway type:
- External routes reference `gateway-name-external`
- Internal routes reference `gateway-name-internal`
- Hybrid gateways get routes for both instances

## MetalLB Configuration

When using multiple gateways with different MetalLB pools, you need to ensure that each pool has a corresponding L2Advertisement resource. This allows MetalLB to advertise the IP addresses for each pool on the network.

### Adding New MetalLB Pools

If your configuration uses MetalLB pools other than the default `gateway-api-external` and `primary`, you need to add L2Advertisement resources for each pool.

**Example:** If you add `gateway-api-internal` and `gateway-api-dev` pools to your configuration, add the following to `manifests/metallb/metallb-openstack-service-lb.yml`:

```yaml
---
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: gateway-api-internal
  namespace: metallb-system
spec:
  addresses:
    - 10.234.1.0/24  # Adjust to your internal network range
  autoAssign: false
  avoidBuggyIPs: true
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: internal-gateway-advertisement
  namespace: metallb-system
spec:
  ipAddressPools:
    - gateway-api-internal
  nodeSelectors:
    - matchLabels:
        node-role.kubernetes.io/worker: worker
---
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: gateway-api-dev
  namespace: metallb-system
spec:
  addresses:
    - 10.234.2.0/24  # Adjust to your dev network range
  autoAssign: false
  avoidBuggyIPs: true
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: dev-gateway-advertisement
  namespace: metallb-system
spec:
  ipAddressPools:
    - gateway-api-dev
  nodeSelectors:
    - matchLabels:
        node-role.kubernetes.io/worker: worker
```

Then apply the updated configuration:

```bash
kubectl apply -f manifests/metallb/metallb-openstack-service-lb.yml
```

### Important Notes

- Each MetalLB pool must have a corresponding L2Advertisement
- The L2Advertisement tells MetalLB which nodes should advertise the pool's IP addresses
- Adjust the IP address ranges to match your network configuration
- The `autoAssign: false` setting prevents automatic assignment; gateways explicitly request pools via annotations

## Security Considerations

### External Gateways
- Use Let's Encrypt certificates for production
- Configure appropriate firewall rules
- Consider rate limiting and DDoS protection
- Use strong DNS provider credentials for DNS challenges
- Restrict external MetalLB pools to appropriate network segments

### Internal Gateways
- Self-signed certificates are acceptable for internal use
- Ensure internal gateways are not accessible from external networks
- Use network policies to restrict access
- Consider using internal DNS for resolution
- Use dedicated internal MetalLB pools

### Hybrid Gateways
- Carefully consider which services should be exposed both ways
- Use different MetalLB pools for external vs internal access
- Monitor access patterns to ensure appropriate usage
- Consider using different authentication mechanisms for internal vs external access

## Troubleshooting

### Certificate Issues
```bash
# Check certificate status
kubectl get certificates -A

# Check cluster issuer status
kubectl get clusterissuers

# Check certificate requests
kubectl get certificaterequests -A
```

### Gateway Status
```bash
# Check all gateways across namespaces
kubectl get gateways -A

# Check gateways in a specific namespace
kubectl get gateways -n <gateway-namespace>

# Check gateway events
kubectl describe gateway <gateway-name> -n <gateway-namespace>

# Check gateway instances for hybrid gateways
kubectl get gateways -n <gateway-namespace> -l gateway.genestack.io/parent=<gateway-name>
```

### Route Issues
```bash
# Check HTTP routes
kubectl get httproutes -A

# Check route status
kubectl describe httproute <route-name> -n <namespace>
```

## Migration from Single Gateway

To migrate from the existing single gateway setup:

1. Create a configuration file with your current gateway settings
2. Add additional gateways as needed
3. Test the new configuration in a development environment
4. Apply the new configuration to production

Example migration config:
```yaml
gateways:
  # Existing gateway (maintains compatibility)
  - name: flex-gateway
    namespace: envoy-gateway  # Keep in original namespace for compatibility
    domain: your-current-domain.com
    type: 
      - external
    metallb_pools:
      external: gateway-api-external  # Your current pool
    issuer:
      type: letsencrypt  # or selfsigned if you weren't using ACME
      email: your-current-email@example.com
      challenge: http01  # or dns01 if you were using that
    routes:
      # Add all the routes you currently have configured
      - keystone
      - nova
      # ... etc
```

### Backward Compatibility Notes
- The legacy single gateway mode still works unchanged
- Existing `flex-gateway` in `envoy-gateway` namespace is preserved
- New gateways use their own namespaces by default
- Configuration file format supports both old and new syntax