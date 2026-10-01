# Default password detector

`default_password_detector.py` scans Kubernetes Secrets referenced by
`bin/services/*.yaml` and reports values that still match the Helm chart
defaults for the chart version pinned in `helm-chart-versions.yaml`.

The tool is read-only and does not print secret values. It exits with `2` when
it finds chart-default credentials so install scripts can emit a loud warning
without blocking brownfield repairs.

## Usage

Scan one service:

```bash
python3 ops-tools/default_password_detector/default_password_detector.py \
  --service barbican
```

Scan all service descriptors:

```bash
python3 ops-tools/default_password_detector/default_password_detector.py
```

Use live chart values instead of the descriptor cache:

```bash
python3 ops-tools/default_password_detector/default_password_detector.py \
  --service nova \
  --refresh-chart
```

## Notes

By default the detector uses the `chart_secret_schema.sensitive_values` cache
written by `ops-tools/secret_schema_validator/secret_schema_validator.py
--update-cache` when the cached chart version matches the pinned chart version.
If that cache is absent or stale, it falls back to `helm show values`.

Run unit tests with:

```bash
python3 -m unittest ops-tools/default_password_detector/test_default_password_detector.py
```
