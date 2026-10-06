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
- Trove pre-configuration complete (keypair, security group)

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

## Variables

| Variable                         | Default                 | Description                                                                                                                                                                                                                 |
|----------------------------------|-------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `trove_datastore_name`           | `mysql`                 | Datastore to enable: `mysql` or `mariadb`                                                                                                                                                                                   |
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

## Tags

| Tag | Scope |
|-----|-------|
| `always` | Client install, image build, gateway, helm config |
| `post_deploy` | Datastore type and version creation |
| `trove_pre_install` | Runs before the Helm install: install-script managed secrets, mgmt network, security groups, helm config, gateway/kustomize |
| `trove_post_install` | Runs after Trove is up: image build, datastore version, client, keypair, ssh-key distribute |
| `deploy_swift` | Deploy Swift (object-store) for backup/restore |

### Granular tags

## Trove Setup Tasks

| **Tag**                    | **Task**                                   |
| :------------------------- | :----------------------------------------- |
| `trove_secrets`            | Ensure Trove secret prerequisites          |
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
