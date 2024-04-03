# Prometheus

We are taking advantage of the prometheus community kube-prometheus-stack as well as other various components for monitoring and alerting. For more information take a look at [Prometheus Kube Stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)

#### Install kube-prometheus-stack helm chart

## Update Alertmanager configurations

Currently you can supply a Teams webhook url to send all current alerts to a teams channel. This section will be updated to be more comprehensive in the future...

!!! tip

    You can ignore this step if you don't want to send alerts to teams, the alertmanager will still deploy and provide information

``` shell
webhook_url='https://my.webhook.example'
sed -i -e "s#https://webhook_url.example#$webhook_url#" /opt/genestack/kustomize/prometheus/alertmanager_config.yaml
```

## Install the prometheus stack

``` shell
kubectl kustomize --enable-helm /opt/genestack/kustomize/prometheus | kubectl apply --server-side -f -
```

!!! success
    If the installation is successful, you should see the related exporter pods in the prometheus namespace.
