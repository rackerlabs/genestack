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

    Make sure Prometheus Operator is deployed prior to running these commands. It will error out if the
    rquired CRDs are not already installed.

Check if the required CRDs are installed

``` shell
kubectl get customresourcedefinitions.apiextensions.k8s.io servicemonitors.monitoring.coreos.com
```

if the CRDs are present you can run the following

```shell
kubectl apply --filename https://raw.githubusercontent.com/rabbitmq/cluster-operator/main/observability/prometheus/monitors/rabbitmq-servicemonitor.yml

kubectl apply --filename https://raw.githubusercontent.com/rabbitmq/cluster-operator/main/observability/prometheus/monitors/rabbitmq-cluster-operator-podmonitor.yml
```

then,

```shell
for file in $(curl -s https://api.github.com/repos/rabbitmq/cluster-operator/contents/observability/prometheus/rules/rabbitmq | jq -r '.[].download_url'); do   kubectl apply -n prometheus -f $file; done

for file in $(curl -s https://api.github.com/repos/rabbitmq/cluster-operator/contents/observability/prometheus/rules/rabbitmq-per-object | jq -r '.[].download_url'); do   kubectl apply -n prometheus -f $file; done
```

In order for these to work we need to also make sure that they match the `ruleSelector` from Prometheus deploy.
For genestack deploys run

```shell
kubectl get prometheusrule -n prometheus -o name | xargs -I {} kubectl label -n prometheus {} release=kube-prometheus-stack --overwrite
```
This will get all the rules in prometheus namespace and apply `release=kube-prometheus-stack` label. At this point the alerts will be configured
in prometheus.

## Epoxy upgrade notes

Genestack targets RabbitMQ `4.1.4` for the Epoxy release path. The
`RabbitmqCluster` manifest pins `spec.image` explicitly to
`rabbitmq:4.1.4-management` so upgrades remain predictable and do not depend on
operator default image changes.

When upgrading an existing environment, re-apply the RabbitMQ cluster manifest
so that the intended RabbitMQ image is reconciled.

!!! warning
