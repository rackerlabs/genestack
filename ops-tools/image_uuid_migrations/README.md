# Image UUID migrations

`image_uuid_migrations.py` generates and optionally applies MariaDB SQL to move
Nova and Cinder references from old Glance image UUIDs to replacement image
UUIDs.

The tool is dry-run by default. In dry-run mode it connects to MariaDB and runs
read-only count queries that summarize the rows it would update. Use
`--offline` when you only want to print the SQL payload without connecting.

## Usage

Run a connected dry-run for the default Nova database and the Cinder database:

```bash
ops-tools/image_uuid_migrations/image_uuid_migrations.py \
  --map-file image_uuid_map.csv \
  --cinder-database cinder
```

Run a connected dry-run from outside the MariaDB pod:

```bash
MYSQL_PASSWORD='change-me'
ops-tools/image_uuid_migrations/image_uuid_migrations.py \
  --map-file image_uuid_map.csv \
  --mysql-host mariadb.example.net \
  --mysql-port 3306 \
  --mysql-user root \
  --mysql-password-env MYSQL_PASSWORD \
  --cinder-database cinder
```

Print the SQL without connecting:

```bash
ops-tools/image_uuid_migrations/image_uuid_migrations.py \
  --map-file image_uuid_map.csv \
  --cinder-database cinder \
  --offline
```

The tool defaults to the Nova database name `nova`. Override it only if the
deployment uses a different Nova database name, or repeat it only when you
intentionally want the same mapping applied to additional Nova databases:

```bash
ops-tools/image_uuid_migrations/image_uuid_migrations.py \
  --map-file image_uuid_map.csv \
  --nova-database nova_cell1 \
  --nova-database nova_cell2 \
  --cinder-database cinder
```

Apply from inside a MariaDB pod:

```bash
ops-tools/image_uuid_migrations/image_uuid_migrations.py \
  --map-file image_uuid_map.csv \
  --cinder-database cinder \
  --apply \
  --yes-im-really-sure
```

Validate a CSV file before generating or applying SQL:

```bash
ops-tools/image_uuid_migrations/image_uuid_migrations.py \
  --map-file image_uuid_map.csv \
  --validate-map-only
```

## CSV Format

The CSV file is read once, validated as a preflight step, and loaded into a
temporary MariaDB table in the generated SQL. The migration then uses set-based
SQL joins against that temporary table instead of applying one CSV line at a
time.

The CSV must include this exact header:

```text
image_name,old_image_uuid,new_image_uuid
```

Example:

```text
image_name,old_image_uuid,new_image_uuid
Ubuntu 24.04,11111111-1111-4111-8111-111111111111,22222222-2222-4222-8222-222222222222
Windows Server 2022 with SQL 2022 Std,33333333-3333-4333-8333-333333333333,44444444-4444-4444-8444-444444444444
```

The repository includes a generic example file at
`ops-tools/image_uuid_migrations/image_migration.csv`.

Rows where `old_image_uuid` and `new_image_uuid` are identical are valid. They
are useful when the CSV is copied directly from a complete image inventory, and
they are no-ops because the generated updates only touch rows where the UUIDs
actually differ.

CSV preflight verifies:

- Required columns are present.
- Each row has exactly three fields.
- `image_name`, `old_image_uuid`, and `new_image_uuid` are populated.
- UUID fields are valid UUID strings.
- `image_name` values are unique.
- `old_image_uuid` values are unique.

## What It Updates

- `instances.image_ref` in each supplied Nova database.
- `block_device_mapping.image_id` in each supplied Nova database, when the
  column exists. This accounts for boot-from-volume requests whose source was a
  Glance image.
- `instance_system_metadata.value` where `key = 'image_base_image_ref'`, when
  the table exists.
- `volume_glance_metadata.value` where `key = 'image_id'` in the optional Cinder
  database. This accounts for bootable volumes and copied snapshot image
  metadata.

## Useful Options

- `--nova-database`: Nova database to migrate. Default: `nova`. Repeat only
  when intentionally targeting additional Nova databases.
- `--cinder-database`: optional Cinder database containing
  `volume_glance_metadata`.
- `--map-file`: CSV mapping file for future migrations.
- `--validate-map-only`: validate a CSV mapping file and exit.
- `--include-deleted`: include rows marked deleted. Default only touches
  non-deleted rows.
- `--apply`: execute the generated SQL. Requires `--yes-im-really-sure`.
- `--format text|json`: dry-run plan output format. Default: `text`.
- `--mysql-command`: MariaDB client command. Default: `mariadb`.
- `--defaults-file`: optional MariaDB defaults file.
- `--mysql-host`: MariaDB server hostname or IP address.
- `--mysql-port`: MariaDB server TCP port.
- `--mysql-user`: MariaDB username.
- `--mysql-password`: MariaDB password. Dry-run output redacts the value.
- `--mysql-password-env`: environment variable containing the MariaDB password.
- `--mysql-socket`: MariaDB Unix socket path.
- `--offline`: do not connect during dry-run; print the SQL that apply mode
  would run.

## Exit Codes

- `0`: dry-run completed, validation completed, or apply completed successfully.
- `1`: argument, validation, CSV, or MariaDB client preflight error.
- `3`: apply mode was attempted and MariaDB returned an error.

## Safety Notes

The dry-run SQL only creates a temporary mapping table and runs count queries.
Apply mode generates separate update SQL and is gated by both `--apply` and
`--yes-im-really-sure`.

Run `--validate-map-only` for CSV migrations, then run the default connected
dry-run and review the update summary before applying.

## Development

Run unit tests with:

```bash
python3 -m unittest ops-tools/image_uuid_migrations/test_image_uuid_migrations.py
```

Run a syntax check with:

```bash
python3 -m py_compile \
  ops-tools/image_uuid_migrations/image_uuid_migrations.py \
  ops-tools/image_uuid_migrations/test_image_uuid_migrations.py
```
