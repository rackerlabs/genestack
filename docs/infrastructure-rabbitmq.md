# Deploy the RabbitMQ Operator and a RabbitMQ Cluster

## Deploy the RabbitMQ operator.

``` shell
kubectl apply -k /opt/genestack/kustomize/rabbitmq-operator
```

!!! note

    The operator may take a minute to get ready, before deploying the RabbitMQ cluster, wait until the operator pod is online.

## Deploy the RabbitMQ topology operator.

``` shell
kubectl apply -k /opt/genestack/kustomize/rabbitmq-topology-operator
```

## Deploy the RabbitMQ cluster.

``` shell
kubectl apply -k /opt/genestack/kustomize/rabbitmq-cluster/base
```

!!! note

    RabbitMQ has a base configuration which is HA and production ready. If you're deploying on a small cluster the `aio` configuration may better suit the needs of the environment.

## Validate the status with the following

``` shell
kubectl --namespace openstack get rabbitmqclusters.rabbitmq.com -w
```
