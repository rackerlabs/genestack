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
| `GRAFANA_URL`     | False    | URL of your Grafana instance                          | `http://grafana.monitoring.svc.cluster.local:80` |


## Usage

```bash
# python import-grafana-dashboard.py -h
usage: import-grafana-dashboard.py [-h] -d DIR [-ds DATASOURCE] [-f FILE]

Import Grafana dashboards from a local directory.

options:
  -h, --help            show this help message and exit
  -d DIR, --dir DIR     Path to directory containing dashboard JSON files
  -ds DATASOURCE, --datasource DATASOURCE
                        Name of the Prometheus datasource. Default: "Prometheus"
  -f FILE, --file FILE  Dashboard JSON file to import. May be repeated; paths are
                        relative to --dir unless absolute. If omitted, import all
                        JSON files in --dir.
```

```bash
export GRAFANA_USERNAME=admin
export GRAFANA_URL=`awk -F': ' '/custom_host/{print "https://" $2}' /etc/genestack/helm-configs/grafana/grafana-helm-overrides.yaml`
export GRAFANA_PASSWORD=`kubectl -n monitoring get secret grafana -o jsonpath='{.data.admin-password}' |base64 -d`
```

### Import all default dashboards

```bash
source /opt/genestack/scripts/genestack.rc
python3 /opt/genestack/scripts/import-grafana-dashboard.py --dir /opt/genestack/etc/grafana-dashboards/ --datasource Prometheus
```


### Import selected and or custom dashboards only

python3 /opt/genestack/scripts/import-grafana-dashboard.py \
  --dir <file_directory_path> \
  --file <some_grafana_dashboard_json> \
  --datasource Prometheus

The importer also converts Grafana `dashboard.grafana.app/v2beta1` dashboard
exports to the legacy format required by the dashboard import API.
