# trove_enablement_techpreview

End-to-end enablement of OpenStack Trove (Database as a Service) for Genestack deployments.

## What It Does

1. **Installs python-troveclient** in the genestack virtualenv
2. **Builds a MySQL guest image** using virt-customize (Ubuntu 22.04 + MySQL + trove-guestagent)
3. **Uploads the image** to Glance with proper tags and properties
4. **Configures gateway and kustomize** — Envoy listener, HTTPRoute, kustomize overlay, endpoint merge
5. **Deep-merges Helm config** — management network, security group, keypair into trove-helm-overrides.yaml
6. **Creates datastore type and version** (post-deploy) — links the Glance image to Trove

## Prerequisites

- Ansible >= 2.15.8
- Kubernetes collections (`kubernetes.core`)
- Keystone, Nova, Neutron, Cinder, Glance deployed and operational
- Trove Helm chart deployed (API running for post-deploy tasks)
- Trove pre-configuration complete (keypair, security group created via `hclab_service_conf`)

## Usage

### Full Run (build image + configure + datastore setup)

```bash
ansible-playbook ansible/playbooks/trove-enablement-techpreview.yaml
```

### Post-Deploy Only (datastore setup after Trove is running)

```bash
ansible-playbook ansible/playbooks/trove-enablement-techpreview.yaml --tags post_deploy
```

### Force Rebuild Image

```bash
ansible-playbook ansible/playbooks/trove-enablement-techpreview.yaml \
  -e force_rebuild_image=true
```

### Force Full Recreation

```bash
ansible-playbook ansible/playbooks/trove-enablement-techpreview.yaml \
  -e force_full_recreation=true
```

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `trove_guest_image_name` | `trove-mysql-8.4` | Name of the Glance image |
| `trove_mysql_version` | `8.4` | MySQL version to install |
| `trove_datastore_name` | `mysql` | Trove datastore type name |
| `trove_datastore_version_name` | `8.4` | Trove datastore version |
| `trove_keypair_name` | `trove-access-keypair` | Nova keypair for instance access |
| `trove_secgroup_name` | `trove-access-secgroup` | Security group for Trove instances |
| `trove_flat_network_name` | `flat` | Management network name |
| `force_rebuild_image` | `false` | Force rebuild and re-upload guest image |
| `force_full_recreation` | `false` | Nuclear option — rebuild everything |

## Tags

| Tag | Scope |
|-----|-------|
| `always` | Client install, image build, gateway, helm config |
| `post_deploy` | Datastore type and version creation |

## License

Apache-2.0
