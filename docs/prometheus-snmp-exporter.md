# Prometheus SNMP Exporter

You will not generally need the Prometheus SNMP Exporter unless you have
specific SNMP monitoring needs and take additional steps to configure the
Prometheus SNMP Exporter. The default Genestack configuration doesn't make
immediate use of it without site-specific customization, such as writing an
applicable snmp.conf

Use the Prometheus SNMP exporter for getting metrics from monitoring with SNMP
into Prometheus.

## Installation

Install the SNMP Exporter

??? example "`/opt/genestack/bin/install-prometheus-snmp-exporter.sh`"

    ``` shell
    --8<-- "bin/install-prometheus-snmp-exporter.sh"
    ```

If the installation is successful, you should see the prometheus-snmp-exporter pod running in the prometheus namespace.
