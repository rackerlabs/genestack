# Prometheus Blackbox Exporter

Using the blackbox exporter we can gather metrics around uptime, latency, cert expiry and more for our public endpoints.
The blackbox exporter ideally would be ran outside the cluster but can still provide useful information when deployed within it when combined with alerting and visualizations.


#### Install Blackbox Exporter Helm Chart


``` shell
bin/install-prometheus-blackbox-exporter.sh
```

!!! success
    If the installation is successful, you should see the related blackbox exporter pods in the prometheus namespace.
