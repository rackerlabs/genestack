# trove_enablement_techpreview

End-to-end enablement of OpenStack Trove (Database as a Service) for Genestack deployments.

Supports three datastores, selected with `trove_datastore_name`:

- `mysql` (default) — MySQL 8.4, `docker.io/library/mysql:8.4`
- `mariadb` — MariaDB 11.8 LTS, `docker.io/library/mariadb:11.8`
- `percona` — Percona Server for MySQL 8.4, `docker.io/percona/percona-server:8.4`

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

### Enable the Percona Server 8.4 datastore

Percona Server for MySQL 8.4 is a drop-in fork of Oracle MySQL 8.4. It reuses
the MySQL guest-agent manager, GTID replication, InnoBackupEx backups, and the
`trove-mysql-*` my.cnf templates; only the container registry
(`docker.io/percona/percona-server`) and the datastore name differ. Select it
on the standard playbook with `trove_datastore_name=percona`:

```bash
ansible-playbook ansible/playbooks/trove-enablement-techpreview.yaml \
  --tags trove_image_build,trove_datastore \
  -e trove_datastore_name=percona

ansible-playbook ansible/playbooks/trove-enablement-techpreview.yaml \
  --tags trove_post_install \
  -e trove_datastore_name=percona
```

This builds the `trove-percona-8.4-bookworm` Glance image and registers the
`percona` datastore with version `8.4`.

### Force Rebuild Image

```bash
ansible-playbook ansible/playbooks/trove-enablement-techpreview.yaml \
  -e force_rebuild_image=true
```

### Force Create Flavors

```bash
ansible-playbook ansible/playbooks/trove-enablement-techpreview.yaml \
  -e force_create_flavors=true
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

### Force SSH Key Regeneration

By default the Trove SSH key (`trove-ssh` K8s secret) and the Nova keypair
(`trove_keypair_name`) are only created if they do not exist. To regenerate
the key, re-create the Nova keypair and push the new private key to the
compute nodes in one step:

```bash
ansible-playbook ansible/playbooks/trove-enablement-techpreview.yaml \
  --tags trove_keypair \
  -e force_create_keys=true
```

Existing Trove instances keep the key they were booted with.

## Variables

| Variable                         | Default                 | Description                                                                                                                                                                                                                 |
|----------------------------------|-------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `trove_datastore_name`           | `mysql`                 | Datastore to enable: `mysql`, `mariadb`, or `percona`                                                                                                                                                                       |
| `trove_flavor_profiles`          | see `defaults/main.yml` | Per-flavor settings map. Each flavor carries `name`, `cores` (number of logical cores), `ram` (amount of RAM in gigabytes), and `root_disk` (amount of root partition in gigabytes).                                        |
| `trove_datastore_profiles`       | see `defaults/main.yml` | Per-datastore settings map. Each profile carries `name`, `version` (engine/docker tag), `version_name` (Trove datastore-version label), `docker_image`, `guest_manager`, backup/replication strategy, and config templates. |
| `trove_guest_image_name`         | `trove-<name>-<version_name>-<os>` | Glance image name, derived from the selected profile (e.g. `trove-mariadb-11.8-bookworm`)                                                                                                                                   |
| `trove_keypair_name`             | `trove-access-keypair`  | Nova keypair for instance access                                                                                                                                                                                            |
| `trove_secgroup_name`            | `trove-access-secgroup` | Security group for Trove instances                                                                                                                                                                                          |
| `trove_mgmt_public_network_name` | `flat`                  | Management network name for public provider network                                                                                                                                                                         |
| `force_rebuild_image`            | `false`                 | Force rebuild and re-upload guest image                                                                                                                                                                                     |
| `force_create_flavors`           | `false`                 | Force rebuild of flavors                                                                                                                                                                                                    |
| `force_create_dsv`               | `false`                 | Force rebuild of datastore version                                                                                                                                                                                          |
| `force_full_recreation`          | `false`                 | Nuclear option — rebuild everything                                                                                                                                                                                         |
| `force_create_keys`              | `false`                 | Regenerate the Trove SSH key, re-create the Nova keypair and redistribute the private key; otherwise the key is only created if missing                                                                                     |
| `trove_force_recreate_secrets`   | `false`                 | Legacy alias of `force_create_keys`                                                                                                                                                                                         |

## Tags

### Grouping tags

| Tag | Scope |
|-----|-------|
| `trove_pre_install` | Runs before the Helm install: install-script managed secrets, mgmt network, security groups, helm config, gateway/kustomize |
| `trove_post_install` | Runs after Trove is up: image build, datastore version, client, SSH key + keypair + distribute |
| `deploy_swift` | Deploy Swift (object-store) for backup/restore |

### Granular tags

## Trove Setup Tasks

| **Tag**                    | **Task**                                                     |
| :------------------------- | :----------------------------------------------------------- |
| `trove_secrets`            | Ensure Trove secret prerequisites                            |
| `trove_mgmt_network`       | Create Management Network, Subnet & Router                   |
| `trove_security_groups`    | Create Trove Security Groups                                 |
| `trove_helm_config`        | Deep-Merge Trove Helm Values                                 |
| `trove_gateway`            | Configure Gateway, Kustomize & Endpoints                     |
| `trove_image_build`        | Build & Upload the Trove Guest Image                         |
| `trove_datastore`          | Create Datastore Type & Version                              |
| `trove_client`             | Install `python-troveclient`                                 |
| `trove_keypair`            | Create Trove SSH Key & Nova Keypair, Distribute Key to Nodes |
| `trove_ssh_key_distribute` | Re-distribute the existing Trove SSH Key to Nodes            |

## License

Apache-2.0
