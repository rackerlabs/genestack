# OpenTelemetry

Genestack uses the OpenTelemetry Helm chart to deploy the operator, daemon collector, and deployment collector into the `monitoring` namespace.

The repository keeps the chart values and overlays in service-specific directories to match the rest of Genestack, but the monitoring docs still treat OpenTelemetry as one part of the overall monitoring stack.

## Paths

- Base Helm values: `/opt/genestack/base-helm-configs/opentelemetry-kube-stack/`
- Service overrides: `/etc/genestack/helm-configs/opentelemetry-kube-stack/`
- Kustomize overlay: `/etc/genestack/kustomize/opentelemetry-kube-stack/overlay/`

## Default Receivers

The default configuration enables:

- MySQL
- RabbitMQ
- Memcached

## Additional Receivers

- PostgreSQL
- HTTPCheck
- 
The deployment collector also includes placeholder `httpcheck` targets. 
Update those endpoints in the base or service override values for your environment before relying on that receiver.

## Secret and Database Preparation

Before Helm runs, the install script:

- ensures `monitoring` exists
- applies Talos Pod Security labels when the provider is `talos`
- creates or applies the `mariadb-monitoring` secret in `openstack`
- creates or applies the `rabbitmq-monitoring-user` secret in `openstack`
- creates or applies the `postgres-monitoring-user` secret in `postgres-system`
- copies `mariadb-monitoring` into `monitoring`
- applies the MariaDB `User` and `Grant` resources for the monitoring account
- applies the RabbitMQ `User` and `Permission` resources for the monitoring account
- copies `rabbitmq-monitoring-user` from `openstack` into `monitoring`
- copies `postgres-monitoring` from `postgres-system` into `monitoring`

PostgreSQL telemetry is optional and not enabled by default. If you want to collect PostgreSQL metrics, add a service override file under `/etc/genestack/helm-configs/opentelemetry-kube-stack/` before installation. 
You can start from `/opt/genestack/base-helm-configs/opentelemetry-kube-stack/opentelemetry-kube-stack-helm-postgresql-overrides.yaml.example`, then adjust the secret and endpoint values for your environment.

You will also need to ensure that you've re-installed the Postgres operator to create the `postgres-monitoring-user` within the postgres cluster.
See [Postgressql installation docs](infrastructure-postgresql.md) for more information. 

The supported way to seed the generated secrets file is:

```shell
/opt/genestack/bin/create-secrets.sh
```

## Install

```shell
/opt/genestack/bin/install-opentelemetry-kube-stack.sh
```

## Verify

```shell
kubectl -n monitoring get pods -l app.kubernetes.io/instance=opentelemetry-kube-stack
kubectl -n monitoring get opentelemetrycollectors
```

Use these companion guides when you are validating the rest of the stack:

- [Monitoring Getting Started](monitoring-getting-started.md)
- [Prometheus](monitoring-prometheus.md)
- [Loki](monitoring-loki.md)
- [Tempo](monitoring-tempo.md)
- [Grafana](monitoring-grafana.md)
- [OpenStack Exporter](openstack-exporter.md)
- [Pushgateway](prometheus-pushgateway.md)

!!! info "Talos-only"

    The daemon collector and node-level monitoring components need privileged Pod Security labels on Talos.
    Skip this on Kubespray unless your cluster enforces the same restriction.
