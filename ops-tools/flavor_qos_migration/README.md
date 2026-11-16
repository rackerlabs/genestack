# Flavor QoS migration

`flavor_qos_migration.py` performs the one-time administrative cutover from
Nova `quota:vif_*` flavor shaping to Neutron flavor QoS. It creates the four
regional QoS policies, updates flavor extra specs, rewrites Nova's cached
flavor in every affected cell, and assigns the policy directly to existing
compute ports.

The tool is dry-run first and fails closed on conflicts. The runtime Nova and
Neutron flavor QoS plugins remain fail-open; that behavior is independent of
this administrative migration.

After applying the migration, validate that assigned policies survive the
instance lifecycle with the procedure in [VALIDATION.md](VALIDATION.md).

## Rate conversion

Nova's legacy values are kB/s while Neutron bandwidth-limit rules use kbps.
The maximum is multiplied by eight and then floored to a whole 1,000,000-kbps
increment. Burst values are multiplied by eight without rounding.

| Policy | Nova max | Raw kbps | Neutron `max_kbps` | `max_burst_kbps` |
| --- | ---: | ---: | ---: | ---: |
| `lite` | 150,000 | 1,200,000 | 1,000,000 | 2,000,000 |
| `plus` | 250,000 | 2,000,000 | 2,000,000 | 4,000,000 |
| `pro` | 375,000 | 3,000,000 | 3,000,000 | 6,000,000 |
| `elite` | 500,000 | 4,000,000 | 4,000,000 | 8,000,000 |

The lower `lite` maximum is intentional. Only egress rules are created;
legacy inbound properties are removed without replacement.

## Requirements

- Admin-scoped OpenStack credentials and a clouds.yaml entry.
- The `mariadb` client with read/write access to every affected Nova cell.
- `kubectl` access to the OpenStack namespace when using the built-in
  port-forward mode.
- Python dependencies from Genestack's `requirements.txt`.
- A quiesced control plane: do not create, rebuild, resize, live migrate, or
  cold migrate instances during apply or rollback.
- A backup of all affected Nova cell databases.

Every affected cell must be supplied with a repeatable `--nova-database`.
Missing a cell leaves its cached instance flavors unchanged.

## Validate and dry-run

Mapping validation is fully local and makes no OpenStack or database calls:

```bash
python3 ops-tools/flavor_qos_migration/flavor_qos_migration.py \
  --map-file ops-tools/flavor_qos_migration/flavor_qos_mapping.yaml \
  --validate-map-only
```

Run a preflight and retain the JSON report:

```bash
python3 ops-tools/flavor_qos_migration/flavor_qos_migration.py \
  --map-file ops-tools/flavor_qos_migration/flavor_qos_mapping.yaml \
  --region dfw-dev \
  --os-cloud dfw-dev-admin \
  --nova-database nova_cell0 \
  --nova-database nova \
  --defaults-file /secure/path/mariadb.cnf \
  --format json > flavor-qos-dry-run.json
```

Dry-run is the default. It returns exit code `2` when changes are required and
shows each flavor's legacy limit, exact conversion, rounded policy limit, and
percentage change. An inherited network policy is reported when the new port
policy will override it.

### Genestack MariaDB port-forward

When MariaDB is reachable only inside Kubernetes, the tool can create and
manage its own loopback-only port-forward. For DFW-dev, run the tool on the
overseer after using `flex-dfw-dev`:

```bash
python3 ops-tools/flavor_qos_migration/flavor_qos_migration.py \
  --map-file ops-tools/flavor_qos_migration/flavor_qos_mapping.yaml \
  --region dfw-dev \
  --os-cloud dfw-dev-admin \
  --nova-database nova_cell0 \
  --nova-database nova \
  --kubectl-port-forward \
  --format json > flavor-qos-dry-run.json
```

This mode uses these Genestack defaults:

- Namespace: `openstack`
- Primary service: `mariadb-cluster-primary`
- Secret: `mariadb`
- Secret key: `root-password`
- Database user: `root`

The password is decoded in memory and passed only to the MariaDB subprocess;
it is never written to a defaults file or included in the report. The tool
asks kubectl for an available local port, binds it to `127.0.0.1`, and uses
that endpoint for all Nova cell queries and updates.

The port-forward is always stopped when the process finishes, including after
a successful run, validation or apply failure, timeout, unexpected exception,
or Ctrl-C. If kubectl does not exit after termination, the tool kills the
port-forward process. A startup failure also cleans up any process that was
already created.

Override the defaults only when the deployment differs:

```bash
  --kube-context <context> \
  --kube-namespace openstack \
  --mariadb-service mariadb-cluster-primary \
  --mariadb-secret mariadb \
  --mariadb-secret-key root-password \
  --mariadb-secret-user root
```

`--kubectl-port-forward` is intentionally incompatible with
`--defaults-file`, `--mysql-host`, `--mysql-port`, `--mysql-user`, `--mysql-password`,
`--mysql-password-env`, and `--mysql-socket`; the tunnel owns those connection
settings. Without `--kubectl-port-forward`, the existing direct MariaDB
connection behavior is unchanged.

## Apply

Review the dry-run, quiesce instance lifecycle operations, take database
backups, and run the identical command with both mutation gates:

```bash
python3 ops-tools/flavor_qos_migration/flavor_qos_migration.py \
  --map-file ops-tools/flavor_qos_migration/flavor_qos_mapping.yaml \
  --region dfw-dev \
  --os-cloud dfw-dev-admin \
  --nova-database nova_cell0 \
  --nova-database nova \
  --kubectl-port-forward \
  --state-dir /secure/path/flavor-qos-state \
  --apply --yes-im-really-sure
```

The tool refuses non-null instance task states and instances in `resized`
state, conflicting explicit port policies, changed flavor properties,
mismatched live policies, and database compare-and-swap races. A
non-terminal row in Nova's `migrations` table does not block an otherwise
stable instance; it is reported as a stale-data warning in the text and JSON
reports. Cached `old` and `new` flavor objects are preserved, while only
`cur.nova_object.data.extra_specs` is changed. The database update rechecks
the instance task and VM states so a lifecycle operation starting after
preflight causes the transaction to roll back. Rerunning after success is a
no-op.

Do not pass database passwords on the command line. Prefer
`--defaults-file`, or set a restricted environment variable and name it with
`--mysql-password-env`.

## Rollback

Apply writes a mode-0600 JSON state file. Rollback uses that exact file and
compare-before-write checks:

```bash
python3 ops-tools/flavor_qos_migration/flavor_qos_migration.py \
  --os-cloud dfw-dev-admin \
  --kubectl-port-forward \
  --rollback-state /secure/path/flavor-qos-state/20261109T120000Z-dfw-dev.json \
  --apply --yes-im-really-sure
```

Rollback restores ports, cached flavor JSON, and flavor extra specs. Policies
created by the run are deleted only if they are unused and their rule remains
unchanged.

## Important options

- `--map-file`: versioned policy and regional flavor mapping.
- `--region`: one of `dfw-dev`, `dfw-prod`, `sjc-prod`, or `iad-prod`.
- `--os-cloud`: admin-scoped clouds.yaml entry.
- `--nova-database`: repeat once for every affected Nova cell.
- `--mysql-command`, `--mysql-host`, `--mysql-port`, `--mysql-user`,
  `--mysql-socket`, and `--defaults-file`: MariaDB connection controls.
- `--kubectl-port-forward`: create a loopback-only tunnel to the Kubernetes
  MariaDB primary and remove it on every exit path.
- `--kubectl-command`, `--kube-context`, `--kube-namespace`,
  `--mariadb-service`, `--mariadb-secret`, `--mariadb-secret-key`, and
  `--mariadb-secret-user`: Kubernetes tunnel and credential controls.
- `--port-forward-timeout`: maximum seconds to wait for tunnel readiness.
- `--api-timeout`: OpenStack API timeout in seconds.
- `--command-timeout`: MariaDB subprocess timeout in seconds.
- `--format text|json`: report format.
- `--quiet`: suppress progress messages on stderr.
- `--state-dir`: protected directory for apply state.

## Exit codes

- `0`: validation passed with no pending work, or apply/rollback succeeded.
- `1`: validation, preflight, or runtime error before mutation.
- `2`: dry-run completed and found pending changes.
- `3`: apply or rollback was requested and failed.

## Development

```bash
python3 -m unittest \
  ops-tools/flavor_qos_migration/test_flavor_qos_migration.py
python3 -m py_compile \
  ops-tools/flavor_qos_migration/flavor_qos_migration.py
```

