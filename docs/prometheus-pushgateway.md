# Prometheus Pushgateway

_Prometheus_ can use a _pushgateway_ to gather metrics from short-lived jobs, like
Kubernetes _CronJobs_. The pushgateway stays up to allow _Promethus_ to gather
the metrics. The short-lived job can push metrics to the gateway and terminate.

In particular, _Genestack_ can use the _pushgateway_ to collect metrics from
the OVN backup _CronJob_.

#### Install the Prometheus Pushgateway Helm Chart


``` shell
bin/install-chart.sh prometheus-pushgateway
```

!!! success
    If the installation is successful, you should see the prometheus-pushgateway pod running in the prometheus namespace.
