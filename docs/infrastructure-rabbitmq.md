# Deploy the RabbitMQ Operator and a RabbitMQ Cluster

<!-- Genestack Epoxy RabbitMQ Deprecations
Genestack now pins the RabbitMQ server image explicitly in the RabbitmqCluster
manifest for the Epoxy release path instead of relying on operator defaults.
-->

## Deploy the RabbitMQ operator.

``` shell
kubectl apply -k /etc/genestack/kustomize/rabbitmq-operator/base
```

!!! note

    The operator may take a minute to get ready, before deploying the RabbitMQ cluster, wait until the operator pod is online.

## Deploy the RabbitMQ topology operator.

``` shell
kubectl apply -k /etc/genestack/kustomize/rabbitmq-topology-operator/base
```

## Deploy the RabbitMQ cluster.

``` shell
kubectl apply -k /etc/genestack/kustomize/rabbitmq-cluster/overlay
```

!!! note

    RabbitMQ has a base configuration which is HA and production ready. If you're deploying on a small cluster the `aio` configuration may better suit the needs of the environment.

## Validate the status with the following

``` shell
kubectl --namespace openstack get rabbitmqclusters.rabbitmq.com -w
```

## Monitoring Integration

RabbitMQ telemetry in Genestack is collected through the OpenTelemetry monitoring stack. Do not add
RabbitMQ-specific Prometheus `ServiceMonitor`, `PodMonitor`, or rule resources as part of the infrastructure
deployment flow.

See [OpenTelemetry](monitoring-opentelemetry.md) and [Monitoring Getting Started](monitoring-getting-started.md)
for the supported monitoring path.

## Epoxy upgrade notes

Genestack targets RabbitMQ `4.1.4` for the Epoxy release path. The
`RabbitmqCluster` manifest pins `spec.image` explicitly to
`rabbitmq:4.1.4-management` so upgrades remain predictable and do not depend on
operator default image changes.

When upgrading an existing environment, re-apply the RabbitMQ cluster manifest
so that the intended RabbitMQ image is reconciled.

!!! warning

    Upgrading the RabbitMQ cluster operator can trigger a rolling update of the
    managed RabbitMQ StatefulSet.
