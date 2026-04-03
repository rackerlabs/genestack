# manila_enablement_techpreview

End-to-end enablement of OpenStack Manila (Shared File Systems) for
Genestack Kubernetes deployments. **Tech Preview** — suitable for lab and
pre-production evaluation.

## What It Does

This role handles the full lifecycle of getting Manila operational:

1. **K8s Secrets** — Generates and manages four Kubernetes secrets
   (RabbitMQ password, DB password, admin password, SSH keypair).
   Syncs passwords to RabbitMQ and MariaDB when secrets are recreated.

2. **Service Image** — Builds an Ubuntu-based Manila service VM image
   using upstream `manila-image-elements`, uploads it to Glance, and
   shares it with the admin and service projects.

3. **Gateway & Kustomize** — Generates Envoy gateway listener and
   HTTPRoute for Manila HTTPS, creates kustomize overlay, and
   deep-merges Manila endpoint stanzas (`share`, `sharev2`,
   `identity.auth.manila`) into the global endpoints override file.
   Patches the running envoy gateway config idempotently.

4. **Helm Configuration** — Templates driver-specific config and
   deep-merges it into the existing Manila Helm overrides. Injects
   the service image ID, flavor ID, and admin password.

5. **Share Type** (post-deploy) — Creates the `generic` share type
   with appropriate extra-specs after Manila is running.

## Requirements

- Ansible >= 2.15.8
- `kubernetes.core` collection (for K8s secret lookups)
- `community.general` collection
- Genestack environment with Keystone, Nova, Neutron, Cinder, Glance,
  and Barbican deployed
- Run from the jump host (localhost) where `kubectl` is available

## Usage

### Full run (pre-deploy + helm config)

```bash
ansible-playbook -i /etc/genestack/inventory/inventory.yaml \
    ansible/playbooks/manila-enablement-techpreview.yaml
```

### Post-deploy only (share type creation)

```bash
ansible-playbook -i /etc/genestack/inventory/inventory.yaml \
    ansible/playbooks/manila-enablement-techpreview.yaml \
    --tags post_deploy
```

### Force modes

```bash
# Rebuild service image only
ansible-playbook ... -e force_rebuild_image=true

# Recreate keypair + rebuild image
ansible-playbook ... -e force_recreate_keypair=true

# Nuclear: regenerate ALL secrets, sync passwords, recreate everything
ansible-playbook ... -e force_full_recreation=true
```

## Role Variables

See `defaults/main.yml` for the full list. Key variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `manila_service_image_version` | `noble` | Ubuntu version for the service image |
| `manila_service_image_name` | `manila-service-image` | Glance image name |
| `manila_service_instance_flavor_name` | `m1.medium` | Flavor for share server VMs |
| `manila_driver_config_template` | `manila_default_helm_config.yaml` | Helm driver template |
| `manila_force_recreate_secrets` | `false` | Force-regenerate all K8s secrets |
| `force_rebuild_image` | `false` | Rebuild and re-upload Glance image |
| `force_recreate_keypair` | `false` | Recreate SSH keypair + rebuild image |
| `force_full_recreation` | `false` | Full recreation of all resources |

## Included Utility Scripts

Located in `files/`:

| Script | Purpose |
|--------|---------|
| `manage-test-tenants.sh` | Create/destroy/reset test tenant projects with networks |
| `manage-test-tenant-shares.sh` | End-to-end share test: creates shares, VMs, routers, mounts |
| `manila-full-teardown-and-test-tenants.sh` | Complete Manila teardown (Helm, K8s, OpenStack resources) |

## Driver Templates

| Template | Backend |
|----------|---------|
| `manila_default_helm_config.yaml` | Generic driver (Cinder-backed LVM) — lab/dev |
| `manila_generic_driver_helm_config.yaml` | Driver-only overlay for customization |

## Tags

| Tag | Runs |
|-----|------|
| (no tag) | Full role: secrets, image, gateway/kustomize, helm config, share type |
| `manila_gateway_kustomize` | Gateway listener, route, kustomize overlay, endpoints merge |
| `post_deploy` | Share type creation only (requires running Manila API) |

## License

Apache-2.0

## Author

Dan With — Rackspace Technology
