# Component Maintenance: Neutron 2024.1 to 2025.1 (Epoxy)

## Validation

**Source Version**: 2024.2.529+13651f45-628a320c (images: 2024.1-latest)
**Target Version**: 2025.1.17+95bf0bf6e (images: 2025.1-latest)
**Kubernetes Version**: Compatible with current cluster version
**Upgrade Path**: Direct upgrade supported
**Major Operational Risks**:

- Firewall_v2 enabled may affect existing firewall policies
- Resource tag limit enforcement (50 tags max)
- OVN emit_need_to_frag enabled may impact older kernels (<5.2)

## Goal

Upgrade neutron from 2024.1 to 2025.1 (Epoxy) with OVN backend support, firewall_v2 enabled, and updated container images without service regression.

## Prep

### Deployment Node

Use the standard deployment node or bastion for maintenance operations.

**Verify current component health:**

```bash
kubectl get pods -n openstack | grep neutron
```

**Verify current cluster health:**

```bash
kubectl get nodes
```

**Verify the current deployed version:**

```bash
grep neutron /etc/genestack/helm-chart-versions.yaml
```

Verify that neutron is in the helm-chart-versions.yaml file.

**Verify node or workload placement:**

```bash
kubectl get pods -n openstack -l release_group=neutron -o wide
```

**Verify backups are available:**

```bash
kubectl get pv
```

**Expected:** All persistent volumes are backed up

If backups are required but missing, stop and create them before continuing.

### Configuration Review

**Configuration files:**

- `/etc/genestack/helm-chart-versions.yaml`
- `/etc/genestack/helm-configs/neutron/neutron-helm-overrides.yaml`

**Verify current config:**

```bash
grep -A 2 service_plugins /etc/genestack/helm-configs/neutron/neutron-helm-overrides.yaml
```

If any non-standard override exists, document it in the maintenance log before continuing.

### Pre-Change Safety Checks

**Check for unhealthy pods:**

```bash
kubectl get pods -n openstack | grep -E 'Error|CrashLoopBackOff'
```

**Check for open alerts:**

```bash
kubectl get events -n openstack --sort-by='.lastTimestamp'
```

If any critical dependency is unhealthy, stop and resolve it first.

## Execute

### Update the Target Version

**Edit:** `/etc/genestack/helm-chart-versions.yaml`

**Set:**

```yaml
neutron: 2025.1.17+95bf0bf6e
```

If intermediate version is required, perform each hop separately and validate after each hop.

### Apply Required Overrides or Patches

**Update:** `/etc/genestack/helm-configs/neutron/neutron-helm-overrides.yaml`

**Update all neutron image tags to:**

```yaml
ghcr.io/rackerlabs/genestack-images/neutron:2025.1-latest
```

**Update service_plugins:**

```yaml
service_plugins: "ovn-router,ovn-vpnaas,qos,metering,trunk,segments,firewall_v2"
```

**Enable firewall_v2:**

```yaml
fwaas:
  enabled: true
```

**Update ML2 extension drivers:**

```yaml
ml2:
  extension_drivers: "port_security,qos,fwaas_v2"
```

**Images:**

It is possible that you have custom overrides for neutron images. If so, remove them or update them to the new 2025.1-latest tag as their source build.

### Create the required secrets

Neutron Epoxy requires new secrets for the updated deployment. Create them first defining a secrets yaml file. The file can be anywhere, for example, create it at `/tmp/neutron-secrets.yaml` with the following content:

```yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: neutron-keystone-nova
  namespace: openstack
type: Opaque
data:
  password: $neutron_keystone_nova
---
apiVersion: v1
kind: Secret
metadata:
  name: neutron-keystone-placement
  namespace: openstack
type: Opaque
data:
  password: $neutron_keystone_placement
---
apiVersion: v1
kind: Secret
metadata:
  name: neutron-keystone-designate
  namespace: openstack
type: Opaque
data:
  password: $neutron_keystone_designate
---
apiVersion: v1
kind: Secret
metadata:
  name: neutron-keystone-ironic
  namespace: openstack
type: Opaque
data:
  password: $neutron_keystone_ironic
```

> Note: The above secrets are examples. Verify which secrets are required based on your deployment and create them accordingly.
  you will need to replace the variables with the actual passwords from your environment. Each secret is a single line base64 encoded string.

```bash
kubectl apply -f /tmp/neutron-secrets.yaml
```

Once the secrets are created, eliminate the file containing the secrets to prevent accidental exposure:

```bash
rm -f /tmp/neutron-secrets.yaml
```

### Run the Maintenance

**Dry-run check:**

```bash
/opt/genestack/bin/install-neutron.sh --dry-run --debug
```

**Expected:** No errors, all resources reconcile successfully

**Apply the upgrade:**

```bash
/opt/genestack/bin/install-neutron.sh
```

## Post-Maint

**Verify workload health:**

```bash
kubectl get pods -n openstack | grep neutron
```

**Expected:** All neutron pods in Running state

**Verify dependent services:**

```bash
kubectl get pods -n openstack | grep -E 'nova|cinder|heat'
```

**Check logs for upgrade failures:**

```bash
kubectl logs -n openstack -l release_group=neutron --tail=100
```

**Verify user-facing functionality:**

```bash
openstack network list
openstack router list
openstack firewall policy list
```

**Expected:** Networks, routers, and firewall policies are accessible

## Troubleshooting

### Common Failure Signals

- **Pod CrashLoopBackOff**: Check logs with `kubectl logs -n openstack <pod-name> -c neutron-server`
- **Service Unavailable**: Verify database connectivity and RabbitMQ status
- **Firewall Policy Errors**: Check for resources exceeding 50 tags limit

### Rollback

**Trigger conditions:**

- Critical services unavailable after 30 minutes
- Data corruption or loss detected
- Unresolvable upgrade errors

**Rollback command:**

```bash
helm rollback neutron <revision>
```

**Expected:** All neutron pods return to previous version

### Additional Recovery Actions

**If pods remain stuck:**

```bash
kubectl delete pods -n openstack -l release_group=neutron
```

**If settings do not reconcile:**

```bash
kubectl rollout restart deployment/neutron-server -n openstack
```

**If firewall policies fail to migrate:**

```bash
# Check for resources exceeding tag limit
openstack resource provider list --usage

# Manually reduce tags on affected resources if needed
```

## Important Upgrade Notes

### Firewall_v2 Enablement

- Firewall_v2 is now enabled by default
- Existing firewall policies will be migrated automatically
- Verify firewall policies after upgrade: `openstack firewall policy list`

### Resource Tag Limit

- 50 tags per resource limit is now enforced
- Resources with more than 50 tags will need modification
- Check current tag usage: `openstack resource provider list --usage`

### OVN emit_need_to_frag

- Now enabled by default
- May impact performance on kernels older than 5.2
- If experiencing issues, set `ovn_emit_need_to_frag: false` in config

### uWSGI Configuration

- The `start-time=%t` variable is now mandatory in uWSGI configuration
- This is handled automatically by the helm chart

### Interface Driver

- `[DEFAULT] interface_driver` now defaults to `openvswitch`
- No longer required when using OVN mechanism driver

## References

- [Neutron 2025.1 Release Notes](https://docs.openstack.org/releasenotes/neutron/2025.1.html)
- [OpenStack-Helm Neutron Chart](https://github.com/openstack/openstack-helm/tree/master/neutron)
- [Genestack Images Repository](https://github.com/rackerlabs/genestack-images)
