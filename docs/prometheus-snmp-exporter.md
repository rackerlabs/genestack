# Prometheus SNMP Exporter

You will not generally need the Prometheus SNMP Exporter unless you have
specific SNMP monitoring needs and take additional steps to configure the
Prometheus SNMP Exporter. The default Genestack configuration doesn't make
immediate use of it without site-specific customization, such as writing an
applicable snmp.conf

Use the Prometheus SNMP exporter for getting metrics from monitoring with SNMP
into Prometheus.

#### Install the Prometheus SNMP Exporter Helm Chart


``` shell
bin/install-chart.sh prometheus-snmp-exporter
```

!!! success
    If the installation is successful, you should see the prometheus-snmp-exporter pod running in the prometheus namespace.
