# Stale qdisc auditor

`find_orphan_qdisk.py` audits libvirt tap devices for stale ingress qdiscs
that can cause Nova/libvirt instance spawn failures like:

```text
tc qdisc add dev tap142d9788-2c ingress
Error: Exclusivity flag on, cannot modify.
```

The scanner runs from outside the libvirt pods and uses `kubectl exec` to
inspect each libvirt container. It treats a tap as stale only when:

- `tc -s qdisc show` reports an ingress qdisc on a `tap*` device.
- No running libvirt domain reports that tap through `virsh domiflist`.

Root qdiscs such as `fq_codel` and `noqueue` are not stale ingress qdisc
findings.

## Usage

Audit the whole cluster in dry-run mode:

```bash
ops-tools/find_orphan_qdisk/find_orphan_qdisk.py
```

Audit one Kubernetes node:

```bash
ops-tools/find_orphan_qdisk/find_orphan_qdisk.py --node compute-01
```

Audit one libvirt pod:

```bash
ops-tools/find_orphan_qdisk/find_orphan_qdisk.py --pod libvirt-libvirt-default-abcde
```

Check a specific tap from a Nova stacktrace:

```bash
ops-tools/find_orphan_qdisk/find_orphan_qdisk.py \
  --pod libvirt-libvirt-default-abcde \
  --tap tap142d9788-2c
```

Emit JSON for CronJob logs or downstream automation:

```bash
ops-tools/find_orphan_qdisk/find_orphan_qdisk.py --format json
```

Delete stale ingress qdiscs:

```bash
ops-tools/find_orphan_qdisk/find_orphan_qdisk.py --fix --yes-im-really-sure
```

`--fix` is rejected unless `--yes-im-really-sure` is also present.

## Useful Options

- `--namespace`: Kubernetes namespace containing libvirt pods. Default:
  `openstack`.
- `--label-selector`: libvirt pod selector. Default: `application=libvirt`.
- `--container`: container name used for `kubectl exec`. Default: `libvirt`.
- `--kubectl-request-timeout`: kubectl API request timeout. Default: `30s`.
- `--command-timeout`: local timeout per kubectl command in seconds. Default:
  `60`.
- `--format text|json`: output format. Default: `text`.
- `--pod`: audit one pod. Repeat to scan multiple pods.
- `--tap`: audit one tap device. Repeat to check multiple stacktrace taps.
- `--node`: audit libvirt pods scheduled to one Kubernetes node.

## Exit Codes

- `0`: no stale ingress qdiscs were found, or `--fix --yes-im-really-sure`
  completed without cleanup failures.
- `1`: scanner, kubectl, or pod inspection error.
- `2`: stale ingress qdiscs were found in dry-run mode.
- `3`: cleanup was attempted and at least one qdisc delete failed.

## Kubernetes CronJob

`manifests/cronjob.yaml` provides a suspended read-only CronJob that emits JSON
and retains completed Jobs for one week. The wrapper treats exit code `2` as a
completed scan with stale qdisc findings so the Job log can be retained for
operator review.

The safe default CronJob mode is read-only JSON output:

```bash
find_orphan_qdisk.py --format json
```

For automated remediation, use the explicit confirmation flag:

```bash
find_orphan_qdisk.py --format json --fix --yes-im-really-sure
```

Recommended CronJob settings:

```yaml
successfulJobsHistoryLimit: 7
failedJobsHistoryLimit: 7
ttlSecondsAfterFinished: 604800
restartPolicy: Never
```

The CronJob service account needs permission to list pods in the OpenStack
namespace and to exec into the libvirt container. The script does not require
`tc`, `virsh`, or `ovs-vsctl` in its own container; those commands are executed
inside the libvirt pods.

Install the suspended CronJob manifest:

```bash
kubectl apply -f ops-tools/find_orphan_qdisk/manifests/cronjob.yaml
```

Enable the schedule after service account and RBAC are ready:

```bash
kubectl -n openstack patch cronjob ops-tools-find-orphan-qdisk \
  --type merge \
  -p '{"spec":{"suspend":false}}'
```

Review retained scan logs:

```bash
kubectl -n openstack get jobs -l app.kubernetes.io/component=find-orphan-qdisk
kubectl -n openstack logs job/<job-name>
```

## Development

Run the unit tests with:

```bash
python3 -m unittest ops-tools/find_orphan_qdisk/test_find_orphan_qdisk.py
```

Run a syntax check with:

```bash
python3 -m py_compile \
  ops-tools/find_orphan_qdisk/find_orphan_qdisk.py \
  ops-tools/find_orphan_qdisk/test_find_orphan_qdisk.py
```
