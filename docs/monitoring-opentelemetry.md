# OpenTelemetry

Genestack uses the OpenTelemetry Helm chart to deploy the operator, daemon collector, and deployment collector into the `monitoring` namespace.

## Paths

- Base Helm values: `/opt/genestack/base-helm-configs/opentelemetry-kube-stack/`
- Service overrides: `/etc/genestack/helm-configs/opentelemetry-kube-stack/`
- Kustomize overlay: `/etc/genestack/kustomize/opentelemetry-kube-stack/overlay/`

## Default Receivers

The default configuration enables:

- MySQL
- PostgreSQL
- RabbitMQ
- Memcached

The deployment collector also includes placeholder `httpcheck` targets. Update those endpoints in the base or service override values for your environment before relying on that receiver.

## Secret and Database Preparation

Before Helm runs, the install script:

- ensures `monitoring` exists
- applies Talos Pod Security labels when the provider is `talos`
- creates or applies the `mariadb-monitoring` secret in `openstack`
- copies `mariadb-monitoring` into `monitoring`
- copies `rabbitmq-default-user` from `openstack` into `monitoring`
- applies the MariaDB `User` and `Grant` resources for the monitoring account

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

!!! info "Talos-only"

    The daemon collector and node-level monitoring components need privileged Pod Security labels on Talos.
    Skip this on Kubespray unless your cluster enforces the same restriction.
