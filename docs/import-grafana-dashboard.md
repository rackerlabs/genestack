# Grafana Dashboard Import Script

This script helps you **import Grafana dashboards** from a local directory that contains JSON files. Each file must contain a valid Grafana dashboard definition.


## Prerequisites
- A running [monitoring stack](https://github.com/rackerlabs/genestack/blob/main/docs/monitoring-info.md)
- Dashboards exported as valid [JSON files](https://github.com/rackerlabs/genestack/tree/main/etc/grafana-dashboards)
- A Grafana service account token (see [Authentication](#authentication))

## Authentication

The scripts authenticate with a **Grafana service account token**. A service account
is scoped to the role you give it, can be revoked on its own, and keeps the Grafana
`admin` credentials out of your shell history and CI logs.

### Create a service account and token

In the Grafana UI, go to **Administration → Users and access → Service accounts →
Add service account**, give it a role, then **Add service account token** and copy
the generated token.

To do the same from the CLI, create the service account once using the admin
credentials, then use only the token from that point on:

```bash
GRAFANA_URL=$(awk -F': ' '/custom_host/{print "https://" $2}' /etc/genestack/helm-configs/grafana/grafana-helm-overrides.yaml)
GRAFANA_ADMIN_PASSWORD=$(kubectl -n monitoring get secret grafana -o jsonpath='{.data.admin-password}' | base64 -d)

# Create the service account
SA_ID=$(curl -sS -X POST "${GRAFANA_URL}/api/serviceaccounts" \
  -u "admin:${GRAFANA_ADMIN_PASSWORD}" \
  -H "Content-Type: application/json" \
  -d '{"name": "genestack-dashboards", "role": "Admin"}' | jq -r '.id')

# Mint a token for it
export GRAFANA_TOKEN=$(curl -sS -X POST "${GRAFANA_URL}/api/serviceaccounts/${SA_ID}/tokens" \
  -u "admin:${GRAFANA_ADMIN_PASSWORD}" \
  -H "Content-Type: application/json" \
  -d '{"name": "genestack-dashboards"}' | jq -r '.key')
```

The token value is only returned once, so store it somewhere safe (for example a
Kubernetes secret) if you need it again. Tokens never expire by default; add
`"secondsToLive": 604800` to the token request body to give it a lifetime.

### Required role

| Task                                  | Minimum role |
|---------------------------------------|--------------|
| Export dashboards                     | `Viewer`     |
| Import dashboards (creates folders)   | `Admin`      |

### Revoke a token

List the tokens on the service account to find the token id, then delete it:

```bash
curl -sS "${GRAFANA_URL}/api/serviceaccounts/${SA_ID}/tokens" \
  -u "admin:${GRAFANA_ADMIN_PASSWORD}"

curl -sS -X DELETE "${GRAFANA_URL}/api/serviceaccounts/${SA_ID}/tokens/${TOKEN_ID}" \
  -u "admin:${GRAFANA_ADMIN_PASSWORD}"
```

See the [Grafana service account HTTP API](https://grafana.com/docs/grafana/latest/developers/http_api/serviceaccount/)
for the full set of endpoints.

## Environment Variables
Set the following environment variables before running the script:

| Variable          | Required | Description                                           | Default                         |
|-------------------|----------|-------------------------------------------------------|---------------------------------|
| `GRAFANA_TOKEN`   | True     | Grafana service account token                         | None.                           |
| `GRAFANA_URL`     | False    | URL of your Grafana instance                          | `http://grafana.monitoring.svc.cluster.local:80` |

!!! warning "Basic auth is deprecated"

    If `GRAFANA_TOKEN` is not set, the scripts fall back to basic auth using
    `GRAFANA_PASSWORD` and `GRAFANA_USERNAME` (default `admin`) and print a
    warning. This path exists only so existing automation keeps working; use a
    service account token for anything new.


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
export GRAFANA_URL=`awk -F': ' '/custom_host/{print "https://" $2}' /etc/genestack/helm-configs/grafana/grafana-helm-overrides.yaml`
export GRAFANA_TOKEN=<your_service_account_token>
```

### Import all default dashboards

```bash
source /opt/genestack/scripts/genestack.rc
python3 /opt/genestack/scripts/import-grafana-dashboard.py --dir /opt/genestack/etc/grafana-dashboards/ --datasource Prometheus
```


### Import selected and or custom dashboards only

```bash
python3 /opt/genestack/scripts/import-grafana-dashboard.py \
  --dir <file_directory_path> \
  --file <some_grafana_dashboard_json> \
  --datasource Prometheus
```

The importer also converts Grafana `dashboard.grafana.app/v2beta1` dashboard
exports to the legacy format required by the dashboard import API.

## Exporting Dashboards

`export-grafana-dashboards.py` writes every dashboard currently in Grafana to a
directory as JSON, in the format the importer expects. It uses the same
environment variables, so a `Viewer` service account token is enough.

```bash
export GRAFANA_URL=`awk -F': ' '/custom_host/{print "https://" $2}' /etc/genestack/helm-configs/grafana/grafana-helm-overrides.yaml`
export GRAFANA_TOKEN=<your_service_account_token>

python3 /opt/genestack/scripts/export-grafana-dashboards.py --dir <output_directory_path>
```
