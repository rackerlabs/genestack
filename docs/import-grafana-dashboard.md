# Grafana Dashboard Import Script

This script helps you **import Grafana dashboards** from a local directory that contains JSON files. Each file must contain a valid Grafana dashboard definition.


## Prerequisites
- A running [monitoring stack](https://github.com/rackerlabs/genestack/blob/main/docs/monitoring-info.md)
- Dashboards exported as valid [JSON files](https://github.com/rackerlabs/genestack/tree/main/etc/grafana-dashboards)

## Environment Variables
Set the following environment variables before running the script:

| Variable          | Required | Description                                           | Default                         |
|-------------------|----------|-------------------------------------------------------|---------------------------------|
| `GRAFANA_PASSWORD`| True     | Grafana admin password                                | None.                           |
| `GRAFANA_USERNAME`| False    | Grafana admin username                                | `admin`                         |
| `GRAFANA_URL`     | False    | URL of your Grafana instance                          | `http://grafana.grafana.svc.cluster.local:80` |


## Usage
```bash
# python import_dashboard.py -h
usage: import_dashboard.py [-h] -d DIR [-ds DATASOURCE]

Import Grafana dashboards from a local directory.

options:
  -h, --help            show this help message and exit
  -d DIR, --dir DIR     Path to directory containing dashboard JSON files
  -ds DATASOURCE, --datasource DATASOURCE
                        Name of the Prometheus datasource. Default: "Prometheus"

export GRAFANA_USERNAME=admin
export GRAFANA_URL=https://grafana.sjc3.rackspacecloud.com
export GRAFANA_PASSWORD=your_admin_password

python import_dashboards.py --dir /opt/genestack/etc/grafana-dashboards/ --datasource Prometheus
```
