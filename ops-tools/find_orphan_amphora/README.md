# Octavia ops tools

`ops-tools/find_orphan_amphora/` contains read-only-by-default diagnostics for Octavia
operational consistency checks. The tools are Python replacements for legacy
shell workflows under `scripts/`.

## Tools

| Tool | Purpose | Remediation |
| --- | --- | --- |
| `find_orphan_amphora.py` | Finds Nova servers that appear to be orphaned Octavia amphorae by comparing Octavia `compute_id` values with the load-balancer management network and, optionally, a dedicated Amphora compute aggregate. | Deletes only candidates that still own a port on the configured management network with `--fix --yes-im-really-sure`. Aggregate-only candidates without management-port evidence remain manual review. |

## Requirements

- Python 3.10 or newer.
- OpenStack CLI credentials with access to Octavia, Neutron, and Nova.
- Access to list all-project Nova servers when `--aggregate` is used.

## Usage

Read-only scan using the default `lb-mgmt-net` management network:

```bash
./ops-tools/find_orphan_amphora/find_orphan_amphora.py --os-cloud sjc
```

Include a dedicated Amphora compute aggregate:

```bash
./ops-tools/find_orphan_amphora/find_orphan_amphora.py \
  --os-cloud sjc \
  --aggregate octavia
```

Emit machine-readable output:

```bash
./ops-tools/find_orphan_amphora/find_orphan_amphora.py \
  --os-cloud sjc \
  --format json
```

Remove automatically fixable candidates after a fresh safety re-check:

```bash
./ops-tools/find_orphan_amphora/find_orphan_amphora.py \
  --os-cloud sjc \
  --aggregate octavia \
  --fix \
  --yes-im-really-sure
```

The tool supports:

- `--format text|json`
- `--quiet`
- `--command-timeout <seconds>`
- `--openstack-command <command>`
- `--os-cloud <cloud>`
- `--management-network <name-or-id>`
- `--aggregate <name-or-id>`
- `--output-dir <path>`
- `--scan` as a compatibility no-op; scanning is the default
- `--fix --yes-im-really-sure` for guarded remediation

Environment variables from the legacy workflow remain supported as defaults:

- `OS_CLOUD`
- `MGMT_NET`
- `AGGREGATE`
- `OUTPUT_DIR`

## Audit Output

Each run writes a timestamped audit directory under `/tmp` unless
`--output-dir` is supplied. The bundle contains:

- `octavia-compute-ids.txt`
- `mgmt-server-ids.txt`
- `reported-ids.txt`
- `orphans.tsv`
- `cleanup.sh`
- `report.json`
- `servers/<compute-id>.yaml`
- `ports/<port-id>.yaml`

`cleanup.sh` is intentionally commented out and is provided for manual review.

## Safety

Read-only mode is the default. Automatic deletion requires both `--fix` and
`--yes-im-really-sure`.

Before deleting a candidate, the tool refreshes the Octavia amphora inventory
and verifies that the recorded management port still belongs to the same Nova
server on the configured management network. Candidates found only through the
aggregate scan and lacking management-port evidence are never automatically
deleted.

## Exit Codes

- `0`: completed with no actionable findings, or all automatically fixable
  findings were remediated successfully and no manual-review findings remain.
- `1`: scanner/runtime error.
- `2`: actionable findings remain in read-only mode, or manual-review findings
  remain after fix mode.
- `3`: remediation was attempted and at least one action failed.

## Development

```bash
PYTHONPYCACHEPREFIX=/tmp/genestack-ops-tools-pycache \
  python3 -m py_compile \
  ops-tools/find_orphan_amphora/find_orphan_amphora.py \
  ops-tools/find_orphan_amphora/test_find_orphan_amphora.py

PYTHONPYCACHEPREFIX=/tmp/genestack-ops-tools-pycache \
  python3 -m unittest ops-tools/find_orphan_amphora/test_find_orphan_amphora.py
```
