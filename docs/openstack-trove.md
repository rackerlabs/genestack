!!! banner "TECH PREVIEW"

# Deploy Trove

OpenStack Trove is the Database as a Service (DBaaS) component of OpenStack. It provisions
and manages database instances (running as Nova guest VMs) without the operator having to
hand-build and administer each database. This document describes how Trove is deployed in
Genestack.

Unlike a plain Helm install, Trove needs a good deal of surrounding scaffolding to actually
work: install-script managed secret prerequisites, a dedicated management overlay network,
security groups, a guest image that carries the Trove guest agent, a datastore registration,
and a per-chassis bridge that lets guest VMs reach RabbitMQ and Keystone. In Genestack that
entire
lifecycle is driven by the `trove_enablement_techpreview` Ansible role, which wraps the
`bin/install-trove.sh` Helm deployment.

> Genestack facilitates the deployment by leveraging Kubernetes' orchestration capabilities
> together with an Ansible role that stitches Trove into Nova, Neutron, Cinder, Glance and
> Swift.

Reference the full online [OpenStack Trove documentation](https://docs.openstack.org/trove/latest/).

## Overview of the enablement flow

The `trove_enablement_techpreview` role performs the end-to-end enablement. At a high level it:

1. **Ensures secret prerequisites** — chart-derived Trove passwords are owned by
   `bin/install-trove.sh` and `bin/services/trove.yaml`; the role ensures they exist before
   pre-install work needs them. The role owns only the `trove-ssh` ed25519 keypair secret.
2. **Creates the Trove management overlay network** — a geneve network (`trove-mgmt-net`),
   its subnet, and a router with an external gateway to the public provider network.
3. **Creates the security groups** — `trove-access-secgroup` (ICMP, SSH, 3306 for guests)
   and `trove-services-secgroup` (5672 RabbitMQ, 5000 Keystone, 8080 Swift for the services
   VIP).
4. **Deep-merges the Helm overrides** — network ID, security group ID, keypair name and
   related `conf.trove` settings are merged into `trove-helm-overrides.yaml`. It also wires
   up the `trove-mgmt-bridge` DaemonSet, guest cloud-init/guest-agent ConfigMaps, and a
   MySQL config-template override.
5. **Configures the gateway, kustomize overlay and endpoints** — Envoy listener, HTTPRoute,
   the `/etc/genestack/kustomize/trove` overlay, and Trove stanzas in
   `global_overrides/endpoints.yaml`.
6. **Builds and uploads the guest image** — a Debian `bookworm` qcow2 built with
   diskimage-builder that carries MySQL, the Trove guest agent, Docker, and pre-baked
   datastore images. The image is uploaded to Glance and shared with the `admin` and
   `service` projects.
7. **Registers the datastore version** (post-deploy) — links the Glance image to the Trove
   `mysql` datastore and loads the configuration validation rules.
8. **Installs `python-troveclient`**, creates the Nova keypair as the `trove` service user,
   and distributes the guest SSH key to the compute nodes.
9. **Deploys Swift** (`swift_all_in_one`) for backup/restore support, unless disabled.

!!! note "This is a tech preview focused on MySQL 8.4"

    The role currently builds and registers a MySQL 8.4 datastore on Debian bookworm. The
    datastore, MySQL version, and OpenStack release used for the guest agent are all
    configurable (see [Role variables](#role-variables)), but MySQL 8.4 is the tested path.

## Prerequisites

- Keystone, Nova, Neutron, Cinder and Glance deployed and operational.
- A public provider network (default name `flat`) for the management router's external
  gateway.
- The genestack virtualenv at `/home/ubuntu/.venvs/genestack` and `genestack.rc` present
  (the standard Genestack jump-host layout).
- Ansible >= 2.15.8 with the `kubernetes.core` collection.

## Create secrets

The role ensures Trove secrets for you as its first step, so **no manual secret creation
is normally required**.

!!! note "Information about the secrets used"

    Trove chart-derived secrets such as `trove-rabbitmq-password`, `trove-db-password`,
    and `trove-admin` are managed by `bin/install-trove.sh` through the shared
    `bin/services/trove.yaml` schema. Existing secret values are reused.

    The techpreview role also manages the `trove-ssh` keypair secret used by the
    post-install access workflow. `trove_force_recreate_secrets=true` and
    `force_full_recreation=true` recreate only this SSH keypair secret; they do not
    rotate Trove database, RabbitMQ, or Keystone service-user passwords.

## Define policy configuration

!!! note "Information about the default policy rules used"

    The default RabbitMQ policy sets the quorum queues target group size to 3 for the
    `trove` vhost. This can be changed in `base-kustomize/trove/base/policies.yaml`.

    ??? example "Default RabbitMQ policy"

        ``` yaml
        apiVersion: rabbitmq.com/v1beta1
        kind: Policy
        metadata:
          name: trove-quorum-three-replicas
          namespace: openstack
        spec:
          name: trove-quorum-three-replicas
          vhost: "trove"
          pattern: ".*"
          applyTo: queues
          definition:
            target-group-size: 3
          priority: 0
          rabbitmqClusterReference:
            name: rabbitmq
        ```

## Run the enablement

The recommended path is to run the Ansible role end to end. It performs the pre-install
scaffolding, calls `bin/install-trove.sh` for the Helm release, and then finishes the
post-install steps (datastore registration, keypair, SSH key distribution).

!!! example "Run the Trove enablement playbook"

    ``` shell
    cd /opt/genestack/ansible/playbooks
    ansible-playbook trove-enablement-techpreview.yaml
    ```

The playbook is a thin wrapper around the role:

``` yaml
--8<-- "ansible/playbooks/trove-enablement-techpreview.yaml"
```

### Running specific phases with tags

The role's tasks are tagged so you can run just part of the flow. This is useful when the
Trove API is not yet up (defer the post-install steps) or when you only need to rebuild one
piece.

| Tag                       | What runs                                                            |
|---------------------------|----------------------------------------------------------------------|
| `trove_pre_install`       | Install-script managed secrets, mgmt network, security groups, Helm config, gateway/kustomize |
| `trove_secrets`           | Install-script managed secret prerequisites                          |
| `trove_mgmt_network`      | Management overlay network, subnet, router                           |
| `trove_security_groups`   | `trove-access` and `trove-services` security groups                  |
| `trove_helm_config`       | Deep-merge Helm overrides, mgmt-bridge DaemonSet, guest ConfigMaps   |
| `trove_gateway`           | Envoy listener, HTTPRoute, kustomize overlay, endpoints merge        |
| `trove_post_install`      | Image build, datastore setup, client install, keypair, SSH key       |
| `trove_image_build`       | Build/upload the guest image only                                    |
| `trove_datastore`         | Register the datastore version (requires the Trove API to be up)     |
| `trove_client`            | Install `python-troveclient`                                         |
| `trove_keypair`           | Create the Nova keypair as the `trove` service user                  |
| `trove_ssh_key_distribute`| Copy the guest SSH key to compute nodes                              |
| `deploy_swift`            | Deploy Swift for backup/restore                                      |

!!! example "Run only the post-install steps after Trove is up"

    ``` shell
    ansible-playbook trove-enablement-techpreview.yaml --tags trove_post_install
    ```

!!! example "Register the datastore version only"

    ``` shell
    ansible-playbook trove-enablement-techpreview.yaml --tags trove_datastore
    ```

### Force / recreation flags

By default the role is idempotent — it skips work that is already done (for example, it will
not rebuild the guest image if it already exists in Glance). Pass these flags to force
specific work:

| Flag                                     | Effect                                                              |
|------------------------------------------|---------------------------------------------------------------------|
| `-e force_rebuild_image=true`            | Delete and rebuild the guest image, then re-upload to Glance        |
| `-e force_create_dsv=true`               | Recreate the datastore version and reload configuration parameters  |
| `-e trove_force_recreate_secrets=true`   | Recreate only the `trove-ssh` keypair secret                         |
| `-e trove_force_recreate_mgmt_network=true` | Delete and recreate the management network/subnet/router         |
| `-e trove_force_recreate_security_groups=true` | Delete and recreate the security groups                       |
| `-e force_full_recreation=true`          | Nuclear option — recreate SSH keypair, network, security groups, image and datastore |

!!! example "Force a guest image rebuild"

    ``` shell
    ansible-playbook trove-enablement-techpreview.yaml -e force_rebuild_image=true
    ```

## The Helm deployment script

The role installs the Trove chart with `bin/install-trove.sh`. You can also run it directly
if you only need to (re)deploy the chart after the scaffolding is in place.

!!! example "Run the Trove deployment script `/opt/genestack/bin/install-trove.sh`"

    ``` shell
    --8<-- "bin/install-trove.sh"
    ```

**What it does:** the script reads the pinned Trove chart version from
`helm-chart-versions.yaml`, then runs `helm upgrade --install trove` in the `openstack`
namespace. It layers Helm values from three directories in order of increasing precedence —
`base-helm-configs/trove`, `helm-configs/global_overrides`, then the operator's
`helm-configs/trove` overrides — and injects service passwords with `--set` by reading the
Keystone, Nova, Neutron, Cinder, MariaDB, memcached and RabbitMQ secrets out of Kubernetes.
Finally it runs the Trove kustomize overlay as a Helm post-renderer.

!!! tip

    For a multi-region deployment, see the [Multi-Region Support](multi-region-support.md)
    guide for the recommended workflow.

## Guest image and datastore

Trove instances are Nova VMs booted from a purpose-built guest image that contains the
database engine and the Trove guest agent. Genestack builds this image with
diskimage-builder rather than by customizing a cloud image.

The build (task file `trove_guest_image_builder.yml`) clones the upstream Trove repo at the
release branch (`stable/2025.2` by default), adds this role's custom DIB elements
(`debian-guest`, `debian-docker`, `image-pre-load`), and runs `disk-image-create` to produce
a Debian `bookworm` qcow2 named `trove-mysql-8.4-bookworm`. The `image-pre-load` element bakes
the `mysql:8.4` datastore image and a `mysql-backup:8.4` image into the guest's Docker cache
so instances boot with a warm cache and can perform backups.

After the Trove API is running, `trove_datastore_setup.yml` registers the datastore version
and links it to the Glance image via image tags:

``` shell
openstack datastore version create 8.4 mysql mysql "" \
    --image-tags trove,mysql,8.4,bookworm --active --default
```

!!! note "Datastore image loader scripts inside the guest"

    The guest image ships two systemd units installed by the
    `image-pre-load/install.d/32-install-datastore-image-loader` element. On boot,
    `trove-load-datastore-images.service` loads only the datastore image (blocking, ordered
    before the guest agent — a sub-second no-op when already cached) and
    `trove-load-backup-image.service` loads the backup image in the background. Splitting the
    work this way keeps a reboot from delaying the guest agent past the taskmanager's RPC
    reply timeout.

For details on customizing the image build, see the
[Building MySQL Images for Trove](openstack-trove-mysql-images.md) guide.

## Guest connectivity: the trove-mgmt-bridge

Trove guest VMs live on the `trove-mgmt-net` geneve overlay and must reach the in-cluster
RabbitMQ and Keystone services. There is no physnet or MetalLB involved. Instead, the role
deploys the `trove-mgmt-bridge` DaemonSet: one anchor pod per control-plane chassis, each
bound to a per-chassis Neutron port and running haproxy that proxies 5672 (RabbitMQ) and 5000
(Keystone) into the cluster. Guest cloud-init points the `rabbitmq` and `keystone` hostnames
at the services anchor IP (`10.0.0.10` by default).

The per-chassis anchor ports are created by `create_trove_mgmt_ports.sh`.

!!! example "How the role invokes it"

    ``` shell
    create_trove_mgmt_ports.sh \
        trove-mgmt-net \                # network name
        <trove-services-secgroup-id> \  # security group allowing 5672/5000 in
        trove-mgmt-subnet \             # subnet name
        10 \                            # first host octet for anchor IPs
        default                         # os-cloud name
    ```

**What it does:** it lists the control-plane nodes, then creates one Neutron port per node on
`trove-mgmt-net`, each bound to its specific chassis with `--host=` and pinned to a
deterministic fixed IP below the subnet's allocation pool (mirroring the Octavia
health-manager port pattern). The `trove-mgmt-bridge` init container later resolves "its"
port by node-name suffix and plumbs the LSP into the pod network namespace.

## Validate the deployment

After deployment, verify that the Trove services are running:

``` shell
kubectl --namespace openstack get pods -l application=trove
```

List the Trove services and datastores:

``` shell
openstack database service list
openstack datastore list
openstack datastore version list mysql
```

## Database instance management

### Create a database instance

``` shell
openstack database instance create my-database \
    --flavor <flavor-id> \
    --size 10 \
    --datastore mysql \
    --datastore-version 8.4 \
    --nic net-id=<tenant-network-id>
```

The `--nic` should reference a tenant network the instance can use for client access; the
management NIC on `trove-mgmt-net` is attached automatically by Trove.

### List and inspect instances

``` shell
openstack database instance list
openstack database instance show my-database
```

### Create databases and users

``` shell
# Create a database
openstack database db create my-database myapp_db

# Create a user with access to the database
openstack database user create my-database myapp_user myapp_password --databases myapp_db

# List databases and users
openstack database db list my-database
openstack database user list my-database
```

## Backups

Backups require an object store. The role deploys Swift (`swift_all_in_one`) by default so
that backups work out of the box. Set `-e trove_deploy_swift=false` to skip Swift deployment,
in which case backups will not be available.

``` shell
openstack database backup create my-database my-backup
openstack database backup list
```

## Supported datastores

This tech preview builds and registers **MySQL 8.4**. The datastore name, version, and guest
OS/OpenStack release are configurable through the role variables below, but MySQL 8.4 on
Debian bookworm is the tested configuration.

## Role variables

Common variables (see `ansible/roles/trove_enablement_techpreview/defaults/main.yml` for the
full list):

| Variable                          | Default                          | Description                                              |
|-----------------------------------|----------------------------------|----------------------------------------------------------|
| `trove_mysql_version`             | `8.4`                            | MySQL version to build and register                      |
| `trove_guest_image_os_release`    | `bookworm`                       | Debian release for the guest image                       |
| `trove_guest_image_name`          | `trove-mysql-8.4-bookworm`       | Glance image name (derived from the two above)           |
| `trove_openstack_release`         | `2025.2`                         | Trove branch cloned for DIB elements + guest agent       |
| `trove_datastore_name`            | `mysql`                          | Trove datastore type name                                |
| `trove_datastore_version_name`    | `8.4`                            | Trove datastore version                                  |
| `trove_keypair_name`              | `trove-access-keypair`           | Nova keypair for instance access                         |
| `trove_secgroup_name`             | `trove-access-secgroup`          | Security group applied to guest instances                |
| `trove_services_secgroup_name`    | `trove-services-secgroup`        | Security group for the services (RabbitMQ/Keystone) VIP  |
| `trove_mgmt_public_network_name`  | `flat`                           | Public provider network for the mgmt router's gateway    |
| `trove_mgmt_network_name`         | `trove-mgmt-net`                 | Management overlay network name                          |
| `trove_mgmt_subnet_cidr`          | `10.0.0.0/20`                    | Management subnet CIDR                                    |
| `trove_services_anchor_ip`        | `10.0.0.10`                      | Anchor IP guests use for RabbitMQ/Keystone               |
| `trove_deploy_swift`              | `true`                           | Deploy Swift for backup/restore support                  |

!!! note "Guest agent and server release must match"

    `trove_openstack_release` (the guest agent branch) must be compatible with the Trove
    server-side image in `trove-helm-overrides.yaml`. A mismatch across the 23.x/25.x
    boundary can cause silently dropped RPC heartbeats and guest-agent build timeouts. See
    the comments in `defaults/main.yml` for the full rationale.

## Troubleshooting

### Check Trove logs

``` shell
# API logs
kubectl --namespace openstack logs -l application=trove,component=api

# Conductor logs
kubectl --namespace openstack logs -l application=trove,component=conductor

# Taskmanager logs
kubectl --namespace openstack logs -l application=trove,component=taskmanager
```

### Verify guest connectivity plumbing

``` shell
# The mgmt-bridge DaemonSet should have one running pod per control-plane node
kubectl --namespace openstack get ds trove-mgmt-bridge
kubectl --namespace openstack rollout status ds/trove-mgmt-bridge
```

### Common issues

1. **Instance stuck in BUILD then errors with a guest-agent timeout** — usually a guest
   agent/server release mismatch (see the note above) or the guest cannot reach the services
   anchor IP. Check the `trove-mgmt-bridge` pods and the guest's console log.
2. **Datastore setup skipped** — `trove_datastore` tasks are skipped when the Trove API is
   not reachable. Re-run with `--tags trove_datastore` once Trove is up.
3. **Image not found** — ensure the guest image built and uploaded to Glance
   (`openstack image show trove-mysql-8.4-bookworm`); rebuild with `-e force_rebuild_image=true`.
4. **Instance creation fails on dependencies** — ensure Nova, Neutron, Cinder and Glance are
   healthy and the `trove` service user has the roles it needs.

## Configuration options

Key configuration options merged into `trove-helm-overrides.yaml` by the role
(`conf.trove.DEFAULT`):

- `default_datastore`: default database engine (`mysql`)
- `management_networks`: the `trove-mgmt-net` network ID
- `management_security_groups`: the `trove-access-secgroup` ID
- `nova_keypair`: the keypair injected into guest instances
- `network_driver`: `trove.network.neutron.NeutronDriver`

For advanced configuration, refer to the
[OpenStack Trove documentation](https://docs.openstack.org/trove/latest/).
