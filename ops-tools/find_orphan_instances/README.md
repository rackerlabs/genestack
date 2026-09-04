# Nova orphan instance directory auditor

`find_orphan_instances.py` audits compute hosts for UUID-shaped directories
under `/var/lib/nova/instances` that are not active according to Nova.

The tool is read-only by default. A directory is treated as orphaned only when:

- the directory name is a valid instance UUID;
- `openstack server list --all --host <host>` does not report that UUID on the
  compute host;
- the Nova database does not contain a non-deleted row for that UUID.

## Usage

Audit every `nova-compute` host:

```bash
ops-tools/find_orphan_instances/find_orphan_instances.py
```

Audit selected hosts:

```bash
ops-tools/find_orphan_instances/find_orphan_instances.py --node compute-01 --node compute-02
```

Emit JSON for job logs or downstream processing:

```bash
ops-tools/find_orphan_instances/find_orphan_instances.py --format json
```

Delete confirmed orphan directories:

```bash
ops-tools/find_orphan_instances/find_orphan_instances.py \
  --delete-orphans \
  --yes-im-really-sure
```

Create backups before deleting:

```bash
ops-tools/find_orphan_instances/find_orphan_instances.py \
  --delete-orphans \
  --yes-im-really-sure \
  --backup
```

`--delete-orphans` is rejected unless `--yes-im-really-sure` is also present.
`--backup` is rejected unless delete mode is enabled.

## Useful Options

- `--node`: compute host to scan. Repeat for multiple hosts.
- `--format text|json`: output format. Default: `text`.
- `--quiet`: suppress progress logs on stderr.
- `--ssh-option`: pass additional SSH options. Repeat as needed.
- `--command-timeout`: timeout per local command in seconds. Default: `120`.
- `--instances-path`: remote Nova instances directory. Default:
  `/var/lib/nova/instances`.
- `--no-sudo`: do not prefix remote find, backup, and delete commands with
  `sudo -n`.
- `--namespace`: Kubernetes namespace containing MariaDB. Default: `openstack`.
- `--mariadb-pod`: MariaDB pod name. Default: `mariadb-cluster-0`.
- `--mariadb-secret`: secret containing `.data.root-password`. Default:
  `mariadb`.
- `--mariadb-password-env`: environment variable containing the MariaDB
  password. Default: `MYSQL_PWD`. When unset, the script falls back to reading
  `--mariadb-secret`.
- `--os-cloud`: OpenStack cloud name to pass to the OpenStack CLI.

## Exit Codes

- `0`: no orphan directories were found, or delete mode completed without
  deletion failures.
- `1`: scanner, SSH, OpenStack, Kubernetes, or database error.
- `2`: orphan directories were found in dry-run mode.
- `3`: delete mode was enabled and at least one delete failed.

## Safety Notes

The scanner validates UUID path components before they are used in database
queries or delete commands. Database confirmation is batched per host and only
returns rows where `deleted=0`, so recently deleted records and missing records
are both treated as eligible orphan candidates.

Backups are written on the remote compute host under:

```text
/var/lib/nova/instances/_orphaned_backups/
```

## Kubernetes CronJob

`manifests/cronjob.yaml` provides a suspended read-only CronJob that emits JSON
and retains completed Jobs for one week. The CronJob sources `MYSQL_PWD` from
the `mariadb` Secret and keeps the password out of the `kubectl exec` command
arguments. The wrapper treats exit code `2` as a completed scan with orphan
findings so the Job log can be retained for operator review.

Install the suspended CronJob manifest:

```bash
kubectl apply -f ops-tools/find_orphan_instances/manifests/cronjob.yaml
```

Enable the schedule after service account, RBAC, OpenStack credentials, MariaDB
access, and SSH credentials are ready:

```bash
kubectl -n openstack patch cronjob ops-tools-find-orphan-instances \
  --type merge \
  -p '{"spec":{"suspend":false}}'
```

Review retained scan logs:

```bash
kubectl -n openstack get jobs -l app.kubernetes.io/component=find-orphan-instances
kubectl -n openstack logs job/<job-name>
```

## Development

Run unit tests with:

```bash
python3 -m unittest ops-tools/find_orphan_instances/test_find_orphan_instances.py
```

Run a syntax check with:

```bash
python3 -m py_compile \
  ops-tools/find_orphan_instances/find_orphan_instances.py \
  ops-tools/find_orphan_instances/test_find_orphan_instances.py
```
