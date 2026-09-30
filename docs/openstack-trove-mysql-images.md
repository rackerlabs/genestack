!!! banner "TECH PREVIEW"

# Building MySQL Images for Trove

Trove boots each database instance as a Nova guest VM from a purpose-built image that carries
the database engine, the Trove guest agent, and the supporting tooling the agent expects at
runtime. This guide explains how Genestack builds that image and how to customize the build.

## Overview

In Genestack the guest image is **not** produced by customizing a stock cloud image with
`virt-customize`. It is built with [diskimage-builder](https://docs.openstack.org/diskimage-builder/latest/)
(DIB) and a set of custom elements, all driven by the `trove_enablement_techpreview` Ansible
role (task file `trove_guest_image_builder.yml`). The result is a Debian `bookworm` qcow2 named
`trove-mysql-8.4-bookworm` that is uploaded to Glance and shared with the `admin` and `service`
projects.

The image build is one phase of the larger Trove enablement flow. For the full deployment,
see the [Deploy Trove](openstack-trove.md) guide — in most cases you will run the enablement
playbook rather than building the image by hand.

## What the build produces

The guest image contains:

- **Debian bookworm** base, built via DIB's `debian-minimal` element (debootstrap).
- **MySQL 8.4 as a container**: rather than installing mysqld on the host, the datastore runs
  as the `mysql:8.4` Docker image, pre-loaded into the guest's Docker cache at build time.
  A `mysql-backup:8.4` image (built from the Trove repo's `backup/` Dockerfile) is also baked
  in for backups.
- **Docker CE**, installed from Docker's official Debian repository (`debian-docker` element).
- **The Trove guest agent**, from the upstream `guest-agent` element at the release branch
  (`stable/2025.2` by default).
- **A `debian` guest user** in the `sudo`, `adm`, `systemd-journal` and `docker` groups.
- **Baseline tooling** — `default-mysql-client`, `curl`, `chrony`, `iputils-ping`,
  `traceroute`, `net-tools`, `telnet`, and debug helpers.
- **Boot-time image loaders** — systemd units that restore the datastore and backup images
  into the Docker cache if they are missing (see [Datastore image loaders](#datastore-image-loaders)).

## Prerequisites

The build runs on the Genestack jump host / launcher node and needs:

- The genestack virtualenv at `/home/ubuntu/.venvs/genestack` and `genestack.rc`.
- A working `openstack` CLI against the cluster (Keystone + Glance reachable).
- Internet access to clone the Trove repo, pull the `mysql:8.4` image, and install packages.
- At least ~10 GB of free space in `/tmp` for the build.

The role installs the build-time system dependencies itself (`qemu-utils`, `debootstrap`,
`kpartx`, `skopeo`, `libguestfs-tools`, Docker), so you do not need to pre-install them.

## Building the image with the role

The recommended way to build (and upload) the image is through the enablement playbook. The
image build is tagged `trove_image_build`, so you can run just that phase:

!!! example "Build and upload the guest image"

    ``` shell
    cd /opt/genestack/ansible/playbooks
    ansible-playbook trove-enablement-techpreview.yaml --tags trove_image_build
    ```

The build is **idempotent**: if `trove-mysql-8.4-bookworm` already exists in Glance the build is
skipped. To force a fresh build and re-upload:

!!! example "Force a rebuild"

    ``` shell
    ansible-playbook trove-enablement-techpreview.yaml -e force_rebuild_image=true
    ```

### What the build does, step by step

`trove_guest_image_builder.yml` performs the following:

1. Installs `python-troveclient` into the genestack venv and the build-time system packages.
2. Clones `openstack/trove` at `stable/{{ trove_openstack_release }}` and creates an isolated
   build virtualenv with `diskimage-builder`.
3. Checks Glance for the target image and decides whether a build is needed.
4. Pulls `docker.io/library/mysql:8.4` as a docker-archive tarball with `skopeo`, and builds
   `mysql-backup:8.4` from the Trove repo's `backup/` Dockerfile.
5. Renders `trove-guestagent.conf` and copies this role's custom DIB elements into the Trove
   elements path.
6. Runs `disk-image-create` to build the qcow2.
7. Uploads the image to Glance (shared) with datastore properties and tags, then adds the
   `service` and `admin` projects as image members and accepts the membership.

### The disk-image-create invocation

For reference, the core build command the role runs is:

``` shell
disk-image-create \
    -a amd64 \
    -o trove-mysql-8.4-bookworm \
    -t qcow2 \
    --image-size 10 \
    -x \
    --logfile /tmp/trove-build-guest-image.log \
    base vm debian-minimal cloud-init-datasources \
    pip-cache guest-agent debian-guest debian-docker image-pre-load
```

The last three elements (`debian-guest`, `debian-docker`, `image-pre-load`) are the custom
elements this role ships. Key environment variables set for the build include
`DIB_RELEASE=bookworm`, `DISTRO_NAME=debian`, `GUEST_USERNAME=debian`,
`DIB_CLOUD_INIT_DATASOURCES=ConfigDrive`, and `TROVE_SERVICES_VIP_IP` (the services anchor IP).

## The custom DIB elements

The role's elements live under
`ansible/roles/trove_enablement_techpreview/files/elements/`:

### `debian-guest`

Prepares the Debian guest for Trove: installs baseline packages, creates the `debian` guest
user, configures NTP/chrony, DHCP-renew and management-NIC hooks, and adjusts MySQL's
`my.cnf`. Notably, `post-install.d/21-mysql-my-cnf` replaces the `/etc/mysql/my.cnf` symlink
so it points at `mariadb.cnf` (which receives the config Trove renders from its template)
instead of `/etc/alternatives/my.cnf`, which is not mapped into the MySQL container.

### `debian-docker`

Installs Docker CE from Docker's official Debian repository, enables it at boot, and adds the
`debian` user to the `docker` group. The datastore runs as a container, so Docker is required
in the guest.

### `image-pre-load`

Bakes the datastore images into the guest so instances boot with a warm Docker cache:

- `extra-data.d/31-copy-datastore-images` copies the `*.tar` image tarballs from the host
  build directory into the mounted image's `/var/lib/trove-images`.
- `pre-finalise.d/31-preload-datastore-images` starts a temporary dockerd pointed at the
  image's `/var/lib/docker` and `docker load`s the tarballs so they are in the cache.
- `install.d/32-install-datastore-image-loader` installs the boot-time loader (below).

## Datastore image loaders

The guest ships two systemd units and a loader script
(`/usr/local/bin/trove-load-datastore-images.sh`) that restore the datastore/backup images
into the Docker cache from `/var/lib/trove-images` if they are missing (for example after a
datastore upgrade or a rebuild re-images the root disk).

The loader is "load only if missing": if every `RepoTag` a tarball declares is already in the
local cache it returns after a sub-second `docker image inspect`; a real `docker load` runs
only when an image is genuinely absent.

!!! example "Loader usage (invoked by the systemd units in the guest)"

    ``` shell
    # Blocking unit — datastore image only, before the guest agent
    trove-load-datastore-images.sh datastore

    # Non-blocking unit — backup image, in the background
    trove-load-datastore-images.sh backup
    ```

**What it does and why two units:** `trove-load-datastore-images.service` is ordered
`Before=guest-agent.service` and loads only the datastore image (`mysql:8.4`), so the image is
present before the agent runs `start_db`/`prepare`. Because it is a near-instant no-op when
the image is already cached, it does not meaningfully delay boot.
`trove-load-backup-image.service` is deliberately **not** ordered before the guest agent and
loads the larger `mysql-backup:8.4` image in the background, so even a multi-minute load can
never delay the agent or push a reboot past the taskmanager's RPC reply timeout.

## Guest agent configuration

The guest agent configuration is rendered from
`templates/trove-guestagent.conf.j2` at build/config time and delivered to the guest. It
points the agent at the in-cluster services via the management overlay:

- `transport_url` → `rabbit://trove:<password>@rabbitmq.openstack.svc.cluster.local:5672/trove`
- `trove_auth_url` → `http://keystone-api.openstack.svc.cluster.local:5000/v3`
- `swift_url` → `http://<services-anchor-ip>:8080/v1/AUTH_` (for backups)
- classic non-durable RabbitMQ queues (`rabbit_quorum_queue = false`) to match the conductor

Guest VMs reach these hostnames through the `trove-mgmt-bridge` DaemonSet described in the
[Deploy Trove](openstack-trove.md#guest-connectivity-the-trove-mgmt-bridge) guide. A small
cloud-init snippet (`templates/trove-mysql-cloudinit.j2`) also copies the `os_admin.cnf` that
the guest agent creates during `prepare` into `/etc/mysql/conf.d` so it is usable inside the
MySQL container.

## Uploading to Glance

The role uploads the image and shares it automatically. If you need to upload a
locally-built qcow2 by hand, the equivalent command is:

``` shell
openstack image create \
    --disk-format qcow2 \
    --container-format bare \
    --shared \
    --property os_type=linux \
    --property os_distro=debian \
    --property os_version=bookworm \
    --property trove_datastore=mysql \
    --property trove_datastore_version=8.4 \
    --tag trove --tag mysql --tag 8.4 --tag bookworm \
    --file /tmp/trove-image-build/trove-mysql-8.4-bookworm.qcow2 \
    trove-mysql-8.4-bookworm
```

The `--tag` values matter: the datastore version is linked to the image by tags, not by ID
(see [Configuring the datastore](#configuring-the-datastore)).

## Configuring the datastore

After the image is in Glance and the Trove API is running, register the datastore version.
The role does this in `trove_datastore_setup.yml` (tag `trove_datastore`):

!!! example "Register the datastore version"

    ``` shell
    ansible-playbook trove-enablement-techpreview.yaml --tags trove_datastore
    ```

The equivalent manual commands are:

``` shell
# Trove auto-creates the 'mysql' datastore type when the first version is created.
openstack datastore version create 8.4 mysql mysql "" \
    --image-tags trove,mysql,8.4,bookworm --active --default

# Load the configuration parameter validation rules (run inside the taskmanager pod)
TM_POD=$(kubectl -n openstack get pods --no-headers | awk '/trove-task/ {print $1; exit}')
kubectl -n openstack exec "$TM_POD" -- \
    trove-manage db_load_datastore_config_parameters mysql 8.4 \
    /var/lib/openstack/lib/python3.12/site-packages/trove/templates/mysql/validation-rules.json
```

To rebuild the datastore version (for example after re-uploading the image):

``` shell
ansible-playbook trove-enablement-techpreview.yaml -e force_create_dsv=true
```

## Customizing the build

The build is driven by variables in
`ansible/roles/trove_enablement_techpreview/defaults/main.yml`. The most relevant for image
building are:

| Variable                       | Default                     | Description                                       |
|--------------------------------|-----------------------------|---------------------------------------------------|
| `trove_mysql_version`          | `8.4`                       | MySQL version (datastore container tag)           |
| `trove_guest_image_os_release` | `bookworm`                  | Debian release for the guest                      |
| `trove_guest_image_name`       | `trove-mysql-8.4-bookworm`  | Glance image name (derived from the two above)    |
| `trove_openstack_release`      | `2025.2`                    | Trove branch for DIB elements + guest agent       |
| `trove_dib_distribution_mirror`| `http://deb.debian.org/debian` | Debian mirror used by debootstrap             |

!!! example "Build for a different MySQL version"

    ``` shell
    ansible-playbook trove-enablement-techpreview.yaml \
        --tags trove_image_build \
        -e trove_mysql_version=8.0 \
        -e force_rebuild_image=true
    ```

!!! warning "Guest agent and server release must match"

    `trove_openstack_release` controls the guest agent branch and must be compatible with the
    Trove server-side image configured in `trove-helm-overrides.yaml`. A mismatch across the
    23.x/25.x boundary can cause silently dropped RPC heartbeats and guest-agent build
    timeouts. See the extensive comments in `defaults/main.yml` for the rationale before
    changing it.

## Testing the image

Once the image is uploaded and the datastore version is registered, create a test instance:

``` shell
openstack database instance create test-mysql-instance \
    --flavor <flavor-id> \
    --size 10 \
    --datastore mysql \
    --datastore-version 8.4 \
    --nic net-id=<tenant-network-id>

openstack database instance show test-mysql-instance
openstack database instance list
```

Then verify basic database functionality:

``` shell
openstack database db create test-mysql-instance testdb
openstack database user create test-mysql-instance testuser testpass --databases testdb
openstack database db list test-mysql-instance
openstack database user list test-mysql-instance
```

## Troubleshooting

### Build fails

- Check the DIB log at `/tmp/trove-build-guest-image.log`.
- Ensure there is enough free space in `/tmp` (the build stages several GB).
- Verify the host can pull `docker.io/library/mysql:8.4` and reach the Debian mirror.
- Stale DIB mounts from a previous failed run can interfere; the role cleans
  `/tmp/dib_build.*` and `/tmp/dib_image.*`, but a manual `umount`/`rm -rf` of those paths
  may be needed if a build was interrupted.

### Instance stuck in BUILD, then guest-agent timeout

Usually a guest agent/server release mismatch (see the warning above), or the guest cannot
reach the services anchor IP. Check the `trove-mgmt-bridge` pods and the instance console log:

``` shell
kubectl --namespace openstack get ds trove-mgmt-bridge
SERVER_ID=$(openstack database instance show test-mysql-instance -f value -c server_id)
openstack console log show "$SERVER_ID"
```

### Datastore version not found

Confirm the image exists and its tags match what the datastore version expects:

``` shell
openstack image show trove-mysql-8.4-bookworm
openstack datastore version list mysql
```

## Related documentation

- [Deploy Trove](openstack-trove.md) — full enablement flow, networking, and validation.
- [OpenStack Trove documentation](https://docs.openstack.org/trove/latest/)
- [diskimage-builder documentation](https://docs.openstack.org/diskimage-builder/latest/)
