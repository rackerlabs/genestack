# Deploy Custom Metrics

We can utilize the Node Exporter deployed by Prometheus to collect custom metrics that may not be available from other exporters.

For more information visit: [Node Exporter Textfile Collectors](https://github.com/prometheus/node_exporter?tab=readme-ov-file#textfile-collector)

You can also view example scripts here: [Textfile Collector Scripts](https://github.com/prometheus-community/node-exporter-textfile-collector-scripts)

## Example custom exporter playbook

``` shell
ansible-playbook custom_exporters.yml
```

## Example custom exporter playbook with overrides

Confirm `inventory.yaml` matches what is in `/etc/genestack/inventory`. If it does not match update the command to match the file names.

``` shell
# Example overriding things on the CLI
source /opt/genestack/scripts/genestack.rc
```

!!! example "Run the playbook"

    ``` shell
    ansible-playbook custom_exporters.yml --private-key ${HOME}/.ssh/openstack-keypair.key
    ```

Once the scripts run the node exporter will collect your metrics and supply them to prometheus for you to view.
