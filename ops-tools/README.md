# Genestack ops tools

`ops-tools/` contains operator-facing diagnostics and remediators that are
useful during Genestack support, upgrades, and incident response. Each tool
lives in its own directory with a README, its executable entry point, and any
tests or deployment assets needed to operate it safely.

## Tool Index

| Tool | Purpose | Default mode |
| --- | --- | --- |
| `check_octavia_ovn` | Checks Amphora load balancer VIP port bindings in OVN and can fail over unhealthy load balancers. | Dry-run from the script, apply from the provided systemd unit |
| `find_orphan_instances` | Finds Nova instance directories that are no longer active in Nova. | Read-only |
| `find_orphan_qdisk` | Finds stale libvirt tap ingress qdiscs that can block Nova instance spawns. | Read-only |
| `ovn` | Compares Neutron, Kube-OVN IP CRD, and OVN NBDB state for stale or missing networking resources. | Read-only |
| `rogue_pod_scanner` | Compares CRI pod sandboxes on a node with pods reported by Kubernetes. | Read-only |

## Directory Standard

Every ops tool directory should include:

- `README.md` with purpose, requirements, usage examples, options, exit codes,
  safety notes, and development/test commands.
- One primary executable named after the tool, preferably Python for new tools
  that need structured output, tests, and future container or CronJob use.
- Focused unit tests for parsing, mode validation, exit code behavior, and
  destructive-action gating.
- Deployment assets only when they are part of the supported operating model,
  such as systemd units or future Kubernetes CronJob manifests.
- A Reno release note under `releasenotes/notes/` whenever the tool is added or
  its behavior changes.

## Kubernetes CronJob Manifests

Runnable Python tools may include a `manifests/` directory with a suspended
CronJob manifest. These manifests are intended as release-ready starting points
for periodic read-only scans.

CronJob manifests should:

- set `suspend: true` by default;
- run the shared ops-tools image;
- keep read-only or dry-run mode as the default command;
- use `concurrencyPolicy: Forbid`;
- set `successfulJobsHistoryLimit: 7` and `failedJobsHistoryLimit: 7`;
- set `ttlSecondsAfterFinished: 604800` to retain finished Jobs for one week;
- normalize exit code `2` to `0` only for read-only scans where actionable
  findings should leave a completed Job log for review;
- leave scanner/runtime errors and remediation failures as non-zero exits.

Clusters must provide the service account, RBAC, kubeconfig, OpenStack
credentials, SSH credentials, or other runtime identity required by each tool
before unsuspending a CronJob.

Install a Python tool CronJob from its tool directory:

```bash
kubectl apply -f ops-tools/<tool>/manifests/
kubectl -n openstack patch cronjob <cronjob-name> \
  --type merge \
  -p '{"spec":{"suspend":false}}'
```

`check_octavia_ovn` is the exception: it is installed as a systemd unit and
timer with `ops-tools/check_octavia_ovn/install_check_octavia_ovn_systemd.sh`.

## CLI Standard

New and substantially rewritten tools should follow these conventions:

- Default to read-only or dry-run behavior.
- Use `argparse` for Python command lines.
- Support `--format text|json` when output may be consumed by automation.
- Write machine-readable report data to stdout and progress/debug logs to
  stderr.
- Support `--quiet` to suppress progress logs.
- Provide bounded command execution with configurable timeouts.
- Keep external command names configurable when practical, for example
  `--kubectl-command`, `--openstack-command`, or `--ssh-command`.
- Return stable exit codes:
  - `0`: completed successfully with no actionable findings, or remediation
    completed successfully.
  - `1`: scanner/runtime error.
  - `2`: actionable findings were detected in read-only mode.
  - `3`: remediation was attempted and at least one action failed.
- Document any intentional exceptions to the standard in the tool README.

Existing shell tools do not need to be rewritten just to satisfy the standard,
but new work should move them in this direction when behavior is touched.

## Remediation Standard

Any tool that can change infrastructure state must:

- Make read-only mode the default unless the tool README clearly documents why
  an existing deployment wrapper intentionally runs in apply mode.
- Require an explicit action flag such as `--fix`, `--apply`, or
  `--delete-orphans`.
- Require `--yes-im-really-sure` for destructive or irreversible actions.
- Validate resource identifiers before using them in delete, failover, or SQL
  operations.
- Be idempotent where possible, and track state when repeated remediation would
  be harmful.
- Report both attempted and successful remediation counts.

## Output Standard

Text output should be readable in a terminal or retained Job log. JSON output
should include:

- top-level summary counts;
- per-target results;
- explicit errors per target;
- whether remediation was enabled;
- whether each remediation action was attempted and succeeded.

The JSON schema does not need to be identical for every tool, but field names
should be stable once released.

## Security And Credentials

Tools should not print secrets. Prefer existing operator credentials such as
OpenStack environment variables, `clouds.yaml`, kubeconfig, or Kubernetes
service account identity. If a secret must be passed to an external command,
keep it scoped to the subprocess and avoid echoing the full command in normal
logs.

## Release Notes

Each ops tool directory must have release notes for Genestack releases where it
is introduced or meaningfully changed. Use Reno YAML files in
`releasenotes/notes/` and include the tool directory name in the filename or
note body.

For the `2026.3.0` release, every current directory under `ops-tools/` has a
corresponding note.
