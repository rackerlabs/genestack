# Barbican Exporter

The Barbican exporter allows monitoring of OpenStack's Key Management Service (Barbican) by exposing metrics to Prometheus. It collects metrics about secrets, containers, and other Barbican-specific resources.

#### Install the Barbican Exporter Helm Chart

```shell
/opt/genestack/bin/install.sh --service barbican-exporter
```

!!! success
    If the installation is successful, you should see the barbican-exporter pod running in the openstack namespace.
