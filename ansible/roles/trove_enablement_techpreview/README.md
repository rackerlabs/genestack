# trove_enablement_techpreview

End-to-end enablement of OpenStack Trove (Database as a Service) for Genestack deployments.

Supports two datastores, selected with `trove_datastore_name`:

- `mysql` (default) — MySQL 8.4, `docker.io/library/mysql:8.4`
- `mariadb` — MariaDB 11.8 LTS, `docker.io/library/mariadb:11.8`

## What It Does

1. **Installs python-troveclient** in the genestack virtualenv
2. **Builds a guest image** with diskimage-builder (Debian bookworm + docker + trove-guestagent) and bakes in the datastore engine + backup container images (`mysql:8.4` or `mariadb:11.8`)
3. **Uploads the image** to Glance with proper tags and properties (`trove,<datastore>,<version>,<os_release>`)
4. **Configures gateway and kustomize** — Envoy listener, HTTPRoute, kustomize overlay, endpoint merge
5. **Deep-merges Helm config** — management network, security group, keypair, datastore config into trove-helm-overrides.yaml
6. **Creates datastore type and version** (post-deploy) — links the Glance image to Trove

## Prerequisites

- Ansible >= 2.15.8
- Kubernetes collections (`kubernetes.core`)
- Keystone, Nova, Neutron, Cinder, Glance deployed and operational
- Trove Helm chart deployed (API running for post-deploy tasks)
- Trove pre-configuration complete (keypair, security group)

## Usage

### Full Run (build image + configure + datastore setup)

```bash
ansible-playbook ansible/playbooks/trove-enablement-techpreview.yaml
```

### Pre-install only (before the Trove Helm install)

```bash
ansible-playbook ansible/playbooks/trove-enablement-techpreview.yaml \
  --tags trove_pre_install
```

### Post-install only (after Trove is running)

```bash
ansible-playbook ansible/playbooks/trove-enablement-techpreview.yaml \
  --tags trove_post_install
```

### Enable the MariaDB 11.8 (LTS) datastore

Build the guest image and register the datastore version for MariaDB by
selecting the datastore with `trove_datastore_name=mariadb`:

```bash
ansible-playbook ansible/playbooks/trove-enablement-techpreview.yaml \
  --tags trove_image_build,trove_datastore \
  -e trove_datastore_name=mariadb

ansible-playbook ansible/playbooks/trove-enablement-techpreview.yaml \
  --tags trove_post_install \
  -e trove_datastore_name=mariadb
```

This builds the `trove-mariadb-11.8-bookworm` Glance image and registers the
MariaDB 11.8 datastore version.

### Force Rebuild Image

```bash
ansible-playbook ansible/playbooks/trove-enablement-techpreview.yaml \
  -e force_rebuild_image=true
```

### Force Rebuild Datastore Version

```bash
ansible-playbook ansible/playbooks/trove-enablement-techpreview.yaml \
  -e force_create_dsv=true
```

### Force Full Recreation

```bash
ansible-playbook ansible/playbooks/trove-enablement-techpreview.yaml \
  -e force_full_recreation=true
```

## Variables

| Variable                         | Default                 | Description                                         |
|----------------------------------|-------------------------|-----------------------------------------------------|
| `trove_datastore_name`           | `mysql`                 | Datastore to enable: `mysql` or `mariadb`           |
| `trove_datastore_profiles`       | see `defaults/main.yml` | Per-datastore settings map. Each profile carries `name`, `version` (engine/docker tag), `version_name` (Trove datastore-version label), `docker_image`, `guest_manager`, backup/replication strategy, and config templates. |
| `trove_guest_image_name`         | `trove-<name>-<version_name>-<os>` | Glance image name, derived from the selected profile (e.g. `trove-mariadb-11.8-bookworm`) |
| `trove_keypair_name`             | `trove-access-keypair`  | Nova keypair for instance access                    |
| `trove_secgroup_name`            | `trove-access-secgroup` | Security group for Trove instances                  |
| `trove_mgmt_public_network_name` | `flat`                  | Management network name for public provider network |
| `force_rebuild_image`            | `false`                 | Force rebuild and re-upload guest image             |
| `force_create_dsv`               | `false`                 | Force rebuild of datastore version                  |
| `force_full_recreation`          | `false`                 | Nuclear option — rebuild everything                 |

## Tags

### Grouping tags

| Tag | Scope |
|-----|-------|
| `trove_pre_install` | Runs before the Helm install: secrets, mgmt network, security groups, helm config, gateway/kustomize |
| `trove_post_install` | Runs after Trove is up: image build, datastore version, client, keypair, ssh-key distribute |
| `deploy_swift` | Deploy Swift (object-store) for backup/restore |

### Granular tags

## Trove Setup Tasks

| **Tag**                    | **Task**                                   |
| :------------------------- | :----------------------------------------- |
| `trove_secrets`            | Create Trove Kubernetes Secrets            |
| `trove_mgmt_network`       | Create Management Network, Subnet & Router |
| `trove_security_groups`    | Create Trove Security Groups               |
| `trove_helm_config`        | Deep-Merge Trove Helm Values               |
| `trove_gateway`            | Configure Gateway, Kustomize & Endpoints   |
| `trove_image_build`        | Build & Upload the Trove Guest Image       |
| `trove_datastore`          | Create Datastore Type & Version            |
| `trove_client`             | Install `python-troveclient`               |
| `trove_keypair`            | Create Trove Keypair                       |
| `trove_ssh_key_distribute` | Distribute Trove SSH Key to Nodes          |

## License

Apache-2.0
