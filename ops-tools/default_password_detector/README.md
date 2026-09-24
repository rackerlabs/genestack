# Default Password Detector

`default_password_detector.py` checks enabled OpenStack services for live
Kubernetes secrets that still contain credentials shipped as defaults by the
deployed OpenStack Helm chart version.

The scanner renders each chart with its defaults, extracts sensitive-looking
keys from rendered `Secret` resources, and compares those values with the same
keys in live secrets. It never prints secret values.

## Requirements

- Python 3 with the repository requirements installed (`ruamel.yaml` is used
  for YAML parsing; PyYAML is also supported).
- Helm with network access to the configured chart repository.
- `kubectl` access that can read secrets in the target namespace.
- The Genestack `openstack-components.yaml` and `helm-chart-versions.yaml`
  files, either from this repository or from `/etc/genestack`.

## Usage

Scan every enabled service using files in the current directory:

```bash
ops-tools/default_password_detector/default_password_detector.py
```

Scan an installed Genestack configuration:

```bash
ops-tools/default_password_detector/default_password_detector.py \
  --components-file /etc/genestack/openstack-components.yaml \
  --chart-versions-file /etc/genestack/helm-chart-versions.yaml
```

Limit the scan and emit JSON:

```bash
ops-tools/default_password_detector/default_password_detector.py \
  --service cinder \
  --service nova \
  --format json \
  --quiet
```

## Options

- `--components-file`: component configuration. Default:
  `openstack-components.yaml`.
- `--chart-versions-file`: pinned chart versions. Default:
  `helm-chart-versions.yaml`.
- `--namespace`: Kubernetes namespace. Default: `openstack`.
- `--helm-repo-name`: Helm repository alias. Default: `openstack-helm`.
- `--helm-repo-url`: fallback repository URL when the alias is unavailable.
- `--helm-command` and `--kubectl-command`: command names or paths.
- `--command-timeout`: timeout for each Helm or kubectl call. Default: `120`.
- `--service`: scan only a named enabled service. Repeat as needed.
- `--format text|json`: report format. Default: `text`.
- `--quiet`: suppress progress messages on stderr.

## Exit Codes

- `0`: scan completed and no chart-default credentials were found.
- `1`: configuration, chart rendering, command, or Kubernetes error.
- `2`: one or more live secret values match chart defaults.

Warnings for rendered secrets or keys that are absent from the cluster do not
make the scan fail. These commonly occur when deployment overrides disable or
replace optional chart resources.

## Detection And Safety

Only keys whose names contain a password, passwd, passphrase, secret, token, or
key segment are compared. For example, `OS_PASSWORD` is checked and
`OS_AUTH_URL` is ignored. Both `data` and `stringData` in rendered secrets are
supported. Empty defaults and undecodable rendered or live values are skipped
with warnings.

The tool is read-only with respect to Kubernetes. Helm may download chart
archives into its local cache. Reports contain service, chart version,
namespace, secret name, and key name, but never the default or live value.

## Remediation

Generate non-default credentials through `bin/create-secrets.sh` and apply the
resulting secrets, or rotate the reported Kubernetes secret manually. Restart
or redeploy affected workloads after rotation so they consume the new value.

Run the scanner again and confirm it exits `0`.

## Development

```bash
python3 -m unittest \
  ops-tools/default_password_detector/test_default_password_detector.py

python3 -m py_compile \
  ops-tools/default_password_detector/default_password_detector.py \
  ops-tools/default_password_detector/test_default_password_detector.py
```
