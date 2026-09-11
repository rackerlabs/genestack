#!/usr/bin/env python3
"""Generate or apply OpenStack image UUID reference migrations."""

from __future__ import annotations

import argparse
import csv
import json
import re
import shutil
import subprocess
import sys
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path

EXIT_OK = 0
EXIT_ERROR = 1
EXIT_APPLY_FAILED = 3

UUID_RE = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
    re.IGNORECASE,
)
DB_NAME_RE = re.compile(r"^[A-Za-z0-9_]+$")
CSV_COLUMNS = ("image_name", "old_image_uuid", "new_image_uuid")


@dataclass(frozen=True)
class ImageMapping:
    image_name: str
    old_uuid: str
    new_uuid: str


@dataclass
class MigrationPlan:
    apply: bool
    command: list[str]
    nova_databases: list[str]
    cinder_database: str | None
    mapping_count: int
    changed_mapping_count: int
    sql: str


class MigrationError(RuntimeError):
    pass


def sql_string(value: str) -> str:
    return "'" + value.replace("\\", "\\\\").replace("'", "''") + "'"


def quoted_db(name: str) -> str:
    if not DB_NAME_RE.match(name):
        raise MigrationError(f"invalid database name: {name}")
    return f"`{name}`"


def validate_mapping(mapping: ImageMapping) -> None:
    if not mapping.image_name:
        raise MigrationError("mapping row is missing image_name")
    if not UUID_RE.match(mapping.old_uuid):
        raise MigrationError(
            f"invalid old UUID for {mapping.image_name}: {mapping.old_uuid}"
        )
    if not UUID_RE.match(mapping.new_uuid):
        raise MigrationError(
            f"invalid new UUID for {mapping.image_name}: {mapping.new_uuid}"
        )


def validate_mappings(mappings: list[ImageMapping], source: str) -> None:
    if not mappings:
        raise MigrationError(f"no mappings found in {source}")
    names: dict[str, int] = {}
    old_uuids: dict[str, int] = {}
    errors: list[str] = []
    for line_number, mapping in enumerate(mappings, start=2):
        try:
            validate_mapping(mapping)
        except MigrationError as exc:
            errors.append(f"line {line_number}: {exc}")
            continue
        name_key = mapping.image_name.casefold()
        old_key = mapping.old_uuid.lower()
        if name_key in names:
            errors.append(
                f"line {line_number}: duplicate image_name {mapping.image_name!r}; first seen on line {names[name_key]}"
            )
        else:
            names[name_key] = line_number
        if old_key in old_uuids:
            errors.append(
                f"line {line_number}: duplicate old_image_uuid {mapping.old_uuid}; first seen on line {old_uuids[old_key]}"
            )
        else:
            old_uuids[old_key] = line_number
    if errors:
        raise MigrationError(
            f"CSV preflight failed for {source}:\n  - " + "\n  - ".join(errors)
        )


def load_csv_mappings(path: Path) -> list[ImageMapping]:
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        fieldnames = reader.fieldnames or []
        missing = [column for column in CSV_COLUMNS if column not in fieldnames]
        if missing:
            raise MigrationError(
                f"CSV preflight failed for {path}: missing required column(s): {', '.join(missing)}"
            )
        rows = []
        for line_number, row in enumerate(reader, start=2):
            if row.get(None):
                raise MigrationError(
                    f"CSV preflight failed for {path}: line {line_number} has too many columns"
                )
            rows.append(
                ImageMapping(
                    row["image_name"].strip(),
                    row["old_image_uuid"].strip(),
                    row["new_image_uuid"].strip(),
                )
            )
    validate_mappings(rows, str(path))
    return rows


def get_mappings(args: argparse.Namespace) -> list[ImageMapping]:
    if not args.map_file:
        raise MigrationError("--map-file is required")
    return load_csv_mappings(Path(args.map_file))


def mapping_sql(mappings: list[ImageMapping]) -> str:
    values = ",\n".join(
        f"({sql_string(row.image_name)}, {sql_string(row.old_uuid)}, {sql_string(row.new_uuid)})"
        for row in mappings
    )
    return f"""CREATE TEMPORARY TABLE image_uuid_map (
  image_name varchar(255) NOT NULL,
  old_uuid char(36) NOT NULL PRIMARY KEY,
  new_uuid char(36) NOT NULL
) ENGINE=MEMORY;

INSERT INTO image_uuid_map (image_name, old_uuid, new_uuid) VALUES
{values};
"""


def nova_sql(database: str, include_deleted: bool) -> str:
    db = quoted_db(database)
    instance_filter = "" if include_deleted else "AND i.deleted = 0"
    bdm_filter = "" if include_deleted else "AND b.deleted = 0"
    ism_filter = "" if include_deleted else "AND i.deleted = 0"
    return f"""USE {db};

SELECT {sql_string(database + ':instances_to_update')} AS item, COUNT(*) AS count
FROM instances i
JOIN image_uuid_map m ON i.image_ref = m.old_uuid
WHERE i.image_ref <> m.new_uuid
{instance_filter};

SET @has_bdm_image_id = EXISTS (
  SELECT 1 FROM information_schema.columns
  WHERE table_schema = {sql_string(database)}
    AND table_name = 'block_device_mapping'
    AND column_name = 'image_id'
);
SET @bdm_count_sql = IF(
  @has_bdm_image_id,
  {sql_string("SELECT " + sql_string(database + ":block_device_mapping_to_update") + " AS item, COUNT(*) AS count FROM block_device_mapping b JOIN image_uuid_map m ON b.image_id = m.old_uuid WHERE b.image_id <> m.new_uuid " + bdm_filter)},
  {sql_string("SELECT " + sql_string(database + ":block_device_mapping_to_update") + " AS item, 0 AS count")}
);
PREPARE bdm_count_stmt FROM @bdm_count_sql;
EXECUTE bdm_count_stmt;
DEALLOCATE PREPARE bdm_count_stmt;

SET @has_instance_system_metadata = EXISTS (
  SELECT 1 FROM information_schema.columns
  WHERE table_schema = {sql_string(database)}
    AND table_name = 'instance_system_metadata'
    AND column_name = 'value'
);
SET @ism_count_sql = IF(
  @has_instance_system_metadata,
  {sql_string("SELECT " + sql_string(database + ":instance_system_metadata_to_update") + " AS item, COUNT(*) AS count FROM instance_system_metadata ism JOIN image_uuid_map m ON ism.value = m.old_uuid JOIN instances i ON i.uuid = ism.instance_uuid WHERE ism.`key` = 'image_base_image_ref' AND ism.value <> m.new_uuid " + ism_filter)},
  {sql_string("SELECT " + sql_string(database + ":instance_system_metadata_to_update") + " AS item, 0 AS count")}
);
PREPARE ism_count_stmt FROM @ism_count_sql;
EXECUTE ism_count_stmt;
DEALLOCATE PREPARE ism_count_stmt;

UPDATE instances i
JOIN image_uuid_map m ON i.image_ref = m.old_uuid
SET i.image_ref = m.new_uuid,
    i.updated_at = UTC_TIMESTAMP()
WHERE i.image_ref <> m.new_uuid
{instance_filter};
SET @instances_updated = ROW_COUNT();

SET @bdm_sql = IF(
  @has_bdm_image_id,
  {sql_string("UPDATE block_device_mapping b JOIN image_uuid_map m ON b.image_id = m.old_uuid SET b.image_id = m.new_uuid, b.updated_at = UTC_TIMESTAMP() WHERE b.image_id <> m.new_uuid " + bdm_filter)},
  'SELECT 0'
);
PREPARE bdm_stmt FROM @bdm_sql;
EXECUTE bdm_stmt;
SET @bdm_updated = IF(@has_bdm_image_id, ROW_COUNT(), 0);
DEALLOCATE PREPARE bdm_stmt;

SET @ism_sql = IF(
  @has_instance_system_metadata,
  {sql_string("UPDATE instance_system_metadata ism JOIN image_uuid_map m ON ism.value = m.old_uuid JOIN instances i ON i.uuid = ism.instance_uuid SET ism.value = m.new_uuid, ism.updated_at = UTC_TIMESTAMP() WHERE ism.`key` = 'image_base_image_ref' AND ism.value <> m.new_uuid " + ism_filter)},
  'SELECT 0'
);
PREPARE ism_stmt FROM @ism_sql;
EXECUTE ism_stmt;
SET @ism_updated = IF(@has_instance_system_metadata, ROW_COUNT(), 0);
DEALLOCATE PREPARE ism_stmt;

SELECT {sql_string(database + ':instances_updated')} AS item, @instances_updated AS count
UNION ALL
SELECT {sql_string(database + ':block_device_mapping_updated')} AS item, @bdm_updated AS count
UNION ALL
SELECT {sql_string(database + ':instance_system_metadata_updated')} AS item, @ism_updated AS count;
"""


def cinder_sql(database: str, include_deleted: bool) -> str:
    db = quoted_db(database)
    vgm_filter = "" if include_deleted else "AND vgm.deleted = 0"
    return f"""SET @has_cinder_volume_glance_metadata = EXISTS (
  SELECT 1 FROM information_schema.columns
  WHERE table_schema = {sql_string(database)}
    AND table_name = 'volume_glance_metadata'
    AND column_name = 'value'
);
SET @cinder_vgm_count_sql = IF(
  @has_cinder_volume_glance_metadata,
  {sql_string("SELECT " + sql_string(database + ":volume_glance_metadata_to_update") + f" AS item, COUNT(*) AS count FROM {db}.volume_glance_metadata vgm JOIN image_uuid_map m ON vgm.value = m.old_uuid WHERE vgm.`key` = 'image_id' AND vgm.value <> m.new_uuid " + vgm_filter)},
  {sql_string("SELECT " + sql_string(database + ":volume_glance_metadata_to_update") + " AS item, 0 AS count")}
);
PREPARE cinder_vgm_count_stmt FROM @cinder_vgm_count_sql;
EXECUTE cinder_vgm_count_stmt;
DEALLOCATE PREPARE cinder_vgm_count_stmt;

SET @cinder_vgm_sql = IF(
  @has_cinder_volume_glance_metadata,
  {sql_string(f"UPDATE {db}.volume_glance_metadata vgm JOIN image_uuid_map m ON vgm.value = m.old_uuid SET vgm.value = m.new_uuid, vgm.updated_at = UTC_TIMESTAMP() WHERE vgm.`key` = 'image_id' AND vgm.value <> m.new_uuid " + vgm_filter)},
  'SELECT 0'
);
PREPARE cinder_vgm_stmt FROM @cinder_vgm_sql;
EXECUTE cinder_vgm_stmt;
SET @cinder_vgm_updated = IF(@has_cinder_volume_glance_metadata, ROW_COUNT(), 0);
DEALLOCATE PREPARE cinder_vgm_stmt;

SELECT {sql_string(database + ':volume_glance_metadata_updated')} AS item, @cinder_vgm_updated AS count;
"""


def build_sql(
    mappings: list[ImageMapping],
    nova_databases: list[str],
    cinder_database: str | None,
    include_deleted: bool,
) -> str:
    for database in nova_databases:
        quoted_db(database)
    if cinder_database:
        quoted_db(cinder_database)
    validate_mappings(mappings, "migration mapping")
    sections = [
        "-- Generated by ops-tools/image_uuid_migrations/image_uuid_migrations.py",
        f"-- generated_at_utc={datetime.now(timezone.utc).replace(microsecond=0).isoformat()}",
        "START TRANSACTION;",
        mapping_sql(mappings),
        "SELECT 'mapping_rows' AS item, COUNT(*) AS count FROM image_uuid_map;",
    ]
    sections.extend(nova_sql(database, include_deleted) for database in nova_databases)
    if cinder_database:
        sections.append(cinder_sql(cinder_database, include_deleted))
    sections.append("COMMIT;")
    return "\n\n".join(sections) + "\n"


def command_for(args: argparse.Namespace) -> list[str]:
    command = [args.mysql_command, "--table"]
    if args.defaults_file:
        command.insert(1, f"--defaults-file={args.defaults_file}")
    return command


def build_plan(args: argparse.Namespace) -> MigrationPlan:
    mappings = get_mappings(args)
    nova_databases = args.nova_database or ["nova"]
    sql = build_sql(
        mappings, nova_databases, args.cinder_database, args.include_deleted
    )
    return MigrationPlan(
        apply=args.apply,
        command=command_for(args),
        nova_databases=nova_databases,
        cinder_database=args.cinder_database,
        mapping_count=len(mappings),
        changed_mapping_count=sum(
            1 for row in mappings if row.old_uuid.lower() != row.new_uuid.lower()
        ),
        sql=sql,
    )


def print_validation_summary(
    mappings: list[ImageMapping], source: str, output_format: str
) -> None:
    changed = sum(1 for row in mappings if row.old_uuid.lower() != row.new_uuid.lower())
    summary = {
        "source": source,
        "rows": len(mappings),
        "changed_rows": changed,
        "unchanged_rows": len(mappings) - changed,
        "status": "passed",
    }
    if output_format == "json":
        print(json.dumps(summary, indent=2, sort_keys=True))
        return
    print(f"CSV preflight passed: {source}")
    print(f"Rows: {summary['rows']}")
    print(f"Rows with old_uuid != new_uuid: {summary['changed_rows']}")
    print(f"No-op rows with old_uuid == new_uuid: {summary['unchanged_rows']}")


def print_text(plan: MigrationPlan) -> None:
    mode = "APPLY" if plan.apply else "DRY-RUN"
    print(f"=== Image UUID migration plan ({mode}) ===")
    print("Command:" if plan.apply else "Would run:")
    print("  " + " ".join(plan.command) + " <<'SQL'")
    print("")
    print(plan.sql, end="")
    if not plan.apply:
        print("SQL")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate or apply Nova/Cinder image UUID reference migrations."
    )
    parser.add_argument(
        "--map-file",
        help="CSV file with image_name,old_image_uuid,new_image_uuid columns.",
    )
    parser.add_argument(
        "--validate-map-only",
        action="store_true",
        help="Validate --map-file and exit without generating or applying SQL.",
    )
    parser.add_argument(
        "--nova-database",
        action="append",
        help="Nova database to migrate. Default: nova. Repeat only when intentionally targeting additional Nova databases.",
    )
    parser.add_argument(
        "--cinder-database",
        help="Optional Cinder database containing volume_glance_metadata.",
    )
    parser.add_argument(
        "--include-deleted",
        action="store_true",
        help="Include deleted Nova/Cinder rows.",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Execute the generated SQL. Default only prints the command and SQL.",
    )
    parser.add_argument(
        "--yes-im-really-sure", action="store_true", help="Required with --apply."
    )
    parser.add_argument(
        "--format",
        choices=["text", "json"],
        default="text",
        help="Output format for dry-run plan. Default: text.",
    )
    parser.add_argument(
        "--quiet", action="store_true", help="Suppress progress logs on stderr."
    )
    parser.add_argument(
        "--mysql-command",
        default="mariadb",
        help="MariaDB client command. Default: mariadb.",
    )
    parser.add_argument(
        "--defaults-file",
        help="Optional MariaDB defaults file, passed as --defaults-file=PATH.",
    )
    return parser.parse_args(argv)


def log(message: str, quiet: bool) -> None:
    if not quiet:
        print(
            f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {message}",
            file=sys.stderr,
        )


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    if args.apply and not args.yes_im_really_sure:
        print("ERROR: --apply requires --yes-im-really-sure", file=sys.stderr)
        return EXIT_ERROR
    if args.validate_map_only and not args.map_file:
        print("ERROR: --validate-map-only requires --map-file", file=sys.stderr)
        return EXIT_ERROR
    if args.validate_map_only:
        try:
            mappings = load_csv_mappings(Path(args.map_file))
        except (OSError, MigrationError) as exc:
            print(f"ERROR: {exc}", file=sys.stderr)
            return EXIT_ERROR
        print_validation_summary(mappings, args.map_file, args.format)
        return EXIT_OK
    try:
        plan = build_plan(args)
    except (OSError, MigrationError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return EXIT_ERROR
    if not args.apply:
        if args.format == "json":
            print(json.dumps(asdict(plan), indent=2, sort_keys=True))
        else:
            print_text(plan)
        return EXIT_OK
    if not shutil.which(args.mysql_command):
        print(
            f"ERROR: required command '{args.mysql_command}' is not installed or not in PATH",
            file=sys.stderr,
        )
        return EXIT_ERROR
    log("applying image UUID migration SQL", args.quiet)
    result = subprocess.run(plan.command, input=plan.sql, text=True, check=False)
    return EXIT_OK if result.returncode == 0 else EXIT_APPLY_FAILED


if __name__ == "__main__":
    raise SystemExit(main())
