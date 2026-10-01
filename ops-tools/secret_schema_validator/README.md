# Secret schema validator

`secret_schema_validator.py` compares the generated service secret descriptors
in `bin/services/*.yaml` with the sensitive value paths exposed by the Helm
chart versions pinned in `helm-chart-versions.yaml`.

Use it after changing a chart version to see whether the service descriptor is
missing newly introduced password, token, secret, or key values.

## Requirements

- Python 3
- `helm`
- `ruamel.yaml` or `PyYAML`
- access to the chart repositories referenced by the service descriptors

## Usage

Validate every service descriptor:

```bash
python3 ops-tools/secret_schema_validator/secret_schema_validator.py
```

Validate one service:

```bash
python3 ops-tools/secret_schema_validator/secret_schema_validator.py --service nova
```

Write the generated chart-observed schema cache back into the descriptor:

```bash
python3 ops-tools/secret_schema_validator/secret_schema_validator.py \
  --service nova \
  --update-cache
```

`--update-cache` updates only the `chart_secret_schema` metadata block,
including the sensitive chart paths and their chart-provided default values. It
does not add entries to `.secrets`, because Helm values do not identify the
Kubernetes secret name, namespace, ownership, rotation policy, or data key that
Genestack should use. The default password detector uses this cache when it is
current for the pinned chart version.

## Exit Codes

- `0`: validation completed without missing descriptor paths
- `1`: runtime error
- `2`: chart-sensitive value paths are missing from `.secrets`

Descriptor paths that are not observed in chart values are reported but do not
cause a non-zero exit. Some Genestack values are intentionally assembled from
templates or supplied by install-specific logic.

## Options

- `--services-dir`: service descriptor directory, default `bin/services`
- `--chart-versions-file`: chart version file, default `helm-chart-versions.yaml`
- `--service`: validate one service; repeat to validate several services
- `--helm-command`: Helm executable, default `helm`
- `--command-timeout`: timeout per Helm command, default 120 seconds
- `--ignore-path`: glob for a Helm value path to ignore; repeatable
- `--update-cache`: write `chart_secret_schema` metadata to descriptors
- `--format text|json`: output format, default `text`

## Development

Run unit tests:

```bash
python3 -m unittest ops-tools/secret_schema_validator/test_secret_schema_validator.py
```
