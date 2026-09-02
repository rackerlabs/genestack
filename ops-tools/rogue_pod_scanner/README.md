# Rogue Pod Scanner

`rogue_pod_scanner.py` SSHes into a Kubernetes node, reads the local CRI pod
sandbox list with `crictl pods -o json`, and compares those pod UIDs with the
pods reported by the Kubernetes API for that same node.

This is intended for finding rogue or orphaned pod sandboxes that exist on a
node but are no longer visible through Kubernetes.

## Usage

```bash
ops-tools/rogue_pod_scanner/rogue_pod_scanner.py node-01
ops-tools/rogue_pod_scanner/rogue_pod_scanner.py ubuntu@10.0.0.12 --node-name node-01 --sudo
ops-tools/rogue_pod_scanner/rogue_pod_scanner.py node-01 --format json
ops-tools/rogue_pod_scanner/rogue_pod_scanner.py --all-nodes --ssh-user ubuntu --sudo
```

Useful options:

- `--all-nodes`: build the SSH inventory from `kubectl get nodes -o json` and
  scan every node.
- `--ssh-user`: SSH user to prepend to Kubernetes node addresses in
  `--all-nodes` mode.
- `--node-address-type`: preferred Kubernetes Node address type for SSH. Repeat
  to set the order. The default order is `InternalIP`, `ExternalIP`, `Hostname`.
- `--node-name`: Kubernetes node name when it differs from the SSH target.
- `--sudo`: run `sudo -n crictl pods -o json` on the remote node.
- `--ssh-option`: pass additional SSH options. Repeat as needed.
- `--ssh-connect-timeout`: SSH connect timeout in seconds. Default: `10`.
- `--command-timeout`: timeout per local or SSH command in seconds. Default:
  `120`.
- `--include-notready`: include non-ready CRI sandboxes in the comparison.
- `--kubeconfig` and `--context`: select the Kubernetes API target.
- `--format text|json`: output format. Default: `text`.
- `--json`: compatibility alias for `--format json`.
- `--quiet`: suppress progress logs.
- `--no-fail`: report findings but always exit `0`.

## Exit Codes

- `0`: no rogue CRI pod sandboxes were found.
- `2`: at least one CRI pod sandbox exists on the node but not in Kubernetes.
- Other non-zero exits indicate command, SSH, or JSON parsing failures.

## Comparison Key

The scanner compares Kubernetes pod UIDs:

- CRI side: `io.kubernetes.pod.uid` from `crictl pods -o json` labels.
- Kubernetes side: `.metadata.uid` from `kubectl get pods --all-namespaces`.

For static/mirror pods, Kubernetes may expose the API object UID separately
from the local static pod config hash used by CRI. The scanner also treats these
annotations as valid Kubernetes-side match IDs:

- `kubernetes.io/config.mirror`
- `kubernetes.io/config.hash`

By default, only `SANDBOX_READY` CRI pod sandboxes are considered. Use
`--include-notready` when investigating startup, teardown, or stuck sandbox
states.

## Progress Logs

The scanner writes timestamped progress logs to stderr while it works. This
includes Kubernetes inventory discovery, selected SSH targets, node scan starts,
remote `crictl` collection, Kubernetes pod lookups, per-node comparison totals,
and the final scan summary.

Example log lines:

```text
[2026-08-21 15:42:00] Kubernetes inventory: querying node list
[2026-08-21 15:42:01] Kubernetes inventory: node-01 -> ubuntu@10.0.0.12 (InternalIP)
[2026-08-21 15:42:01] node-01: starting scan via ubuntu@10.0.0.12
[2026-08-21 15:42:01] SSH ubuntu@10.0.0.12: running sudo -n crictl pods -o json
[2026-08-21 15:42:03] node-01: comparison complete, rogue=0, k8s_missing_on_node=0
```

Logs are sent to stderr so `--json` output remains parseable on stdout. Use
`--quiet` when embedding the scanner somewhere that should produce only the
report body.

## Kubernetes Inventory Mode

When `--all-nodes` is used, the scanner reads all Kubernetes Nodes and chooses
an SSH address from `.status.addresses`. The scanner still compares each node by
the Kubernetes Node name from `.metadata.name`; the selected IP or hostname is
only used as the SSH target.

The default address preference is:

1. `InternalIP`
2. `ExternalIP`
3. `Hostname`

Override that order when needed:

```bash
ops-tools/rogue_pod_scanner/rogue_pod_scanner.py \
  --all-nodes \
  --ssh-user ubuntu \
  --node-address-type ExternalIP \
  --node-address-type InternalIP
```

## Kubernetes CronJob

`manifests/cronjob.yaml` provides a suspended read-only CronJob that emits JSON
and retains completed Jobs for one week. The manifest uses `--no-fail` so rogue
pod findings are captured in a completed Job log for operator review.

Install the suspended CronJob manifest:

```bash
kubectl apply -f ops-tools/rogue_pod_scanner/manifests/cronjob.yaml
```

Enable the schedule after service account, RBAC, and SSH credentials are ready:

```bash
kubectl -n openstack patch cronjob ops-tools-rogue-pod-scanner \
  --type merge \
  -p '{"spec":{"suspend":false}}'
```

Review retained scan logs:

```bash
kubectl -n openstack get jobs -l app.kubernetes.io/component=rogue-pod-scanner
kubectl -n openstack logs job/<job-name>
```

## Development

Run unit tests with:

```bash
python3 -m unittest ops-tools/rogue_pod_scanner/test_rogue_pod_scanner.py
```

Run a syntax check with:

```bash
python3 -m py_compile \
  ops-tools/rogue_pod_scanner/rogue_pod_scanner.py \
  ops-tools/rogue_pod_scanner/test_rogue_pod_scanner.py
```
