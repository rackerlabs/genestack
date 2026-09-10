# Deploy Qonos

QonoS v2 is a modern, extensible scheduling platform for executing time-based actions against OpenStack services. It provides cron-scheduled operations including server snapshots (Nova), volume full and incremental backups (Cinder), with Keystone authentication, trust-based delegation, retention policies, and RabbitMQ notifications.

Genestack deploys QonoS with three control-plane components — API, scheduler, and worker — backed by MariaDB and RabbitMQ.

This document outlines deploying QonoS using Genestack.

## Supported action types

| Action type | Description |
|-------------|-------------|
| `server_snapshot` | Create a Glance image snapshot of a Nova server |
| `volume_backup_full` | Full Cinder backup of a block storage volume |
| `volume_backup_incremental` | Incremental Cinder backup |

Each schedule references an execution profile with Keystone trust delegation so tenant-scoped jobs run under the correct OpenStack project context.

!!! note

    QonoS can be enabled during `bin/setup-openstack.sh` (component prompt **Qonos (Scheduled Actions)**) or installed later with `/opt/genestack/bin/install-qonos.sh`.

## Create secrets

!!! note "Information about the secrets used"

    Manual secret generation is only required if you haven't run the `create-secrets.sh` script located in `/opt/genestack/bin`.

    ??? example "Example secret generation"

        ``` shell
        kubectl --namespace openstack \
                create secret generic qonos-rabbitmq-password \
                --type Opaque \
                --from-literal=username="qonos" \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-64};echo;)"
        kubectl --namespace openstack \
                create secret generic qonos-db-password \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        kubectl --namespace openstack \
                create secret generic qonos-admin \
                --type Opaque \
                --from-literal=password="$(< /dev/urandom tr -dc _A-Za-z0-9 | head -c${1:-32};echo;)"
        ```

## Configure Qonos

The install script renders `qonos.conf` into the `qonos-etc` secret. It prefers a site override, then falls back to the shipped default:

| Source | Path |
|--------|------|
| Override | `/etc/genestack/kustomize/qonos/base/qonos.conf` |
| Default | `/opt/genestack/base-kustomize/qonos/base/qonos.conf` |

!!! tip

    Copy the default template to `/etc/genestack/kustomize/qonos/base/qonos.conf` before install if you need region-specific timeouts, concurrency, or endpoints.

## Run the package deployment

!!! example "Run the Qonos deployment Script `/opt/genestack/bin/install-qonos.sh`"

    ``` shell
    --8<-- "bin/install-qonos.sh"
    ```

## Enable Skyline integration

The Skyline **Scheduled Actions** tab (QonoS) is hidden until Skyline is configured with the QonoS endpoint and service user id.

Add the following to `/etc/genestack/helm-configs/skyline/skyline-helm-overrides.yaml`:

```yaml
conf:
  skyline:
    openstack:
      qonos_endpoint: https://qonos.your.domain.tld/
      qonos_user_id: <qonos-keystone-user-id>
```

Resolve the user id after QonoS is deployed:

``` shell
kubectl --namespace openstack exec -ti openstack-admin-client -- \
  openstack user show qonos --domain service -f value -c id
```

Set `qonos_endpoint` to the same public hostname used on the QonoS Gateway HTTPRoute, then re-run `/opt/genestack/bin/install-skyline.sh` so the override is applied.

!!! note

    Without `qonos_endpoint` and `qonos_user_id`, the Scheduled Actions tab does not appear in Skyline.

## Monitoring

| Component | Port | Path |
|-----------|------|------|
| API | `8080` | `/metrics` |
| Worker | `8081` | `/metrics` |
| Scheduler | `8082` | `/metrics` |

Import `etc/grafana-dashboards/qonos_v2_operations.json` with the [Grafana dashboard import](import-grafana-dashboard.md) script.

## Validate functionality

``` shell
kubectl --namespace openstack get pods -l app.kubernetes.io/name=qonos
kubectl --namespace openstack get jobs qonos-ks-user qonos-db-sync
kubectl --namespace openstack get servicemonitor -l app.kubernetes.io/name=qonos
kubectl --namespace openstack exec -ti openstack-admin-client -- \
  openstack user show qonos --domain service
```
