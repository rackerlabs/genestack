#!/usr/bin/env python3
"""Migrate Nova flavor bandwidth extra specs to Neutron QoS policies."""

from __future__ import annotations

import argparse
import base64
import copy
import json
import os
import re
import selectors
import subprocess
import sys
import tempfile
import time
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from ruamel.yaml import YAML


EXIT_OK = 0
EXIT_ERROR = 1
EXIT_FINDINGS = 2
EXIT_APPLY_FAILED = 3

EXPECTED_POLICIES = {"lite", "plus", "pro", "elite"}
EXPECTED_POLICY_SOURCES = {
    "lite": (150000, 250000),
    "plus": (250000, 500000),
    "pro": (375000, 750000),
    "elite": (500000, 1000000),
}
LEGACY_KEYS = (
    "quota:vif_outbound_average",
    "quota:vif_outbound_burst",
    "quota:vif_outbound_peak",
    "quota:vif_inbound_average",
    "quota:vif_inbound_burst",
    "quota:vif_inbound_peak",
)
POLICY_EXTRA_SPEC = "flavor_qos:policy_id"
DB_NAME_RE = re.compile(r"^[A-Za-z0-9_]+$")
UUID_RE = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
    re.IGNORECASE,
)
PORT_FORWARD_RE = re.compile(r"Forwarding from 127\.0\.0\.1:(\d+) -> 3306")
TERMINAL_MIGRATION_STATES = {
    "completed",
    "confirmed",
    "done",
    "error",
    "failed",
    "reverted",
}
OTHER_QOS_RULE_COLLECTIONS = (
    "qos_dscp_marking_rules",
    "qos_minimum_bandwidth_rules",
    "qos_minimum_packet_rate_rules",
    "qos_packet_rate_limit_rules",
)
EXPECTED_REGION_COUNTS = {
    "dfw-dev": 16,
    "dfw-prod": 23,
    "sjc-prod": 24,
    "iad-prod": 17,
}


class MigrationError(RuntimeError):
    """Raised when migration preflight or execution cannot continue safely."""


@dataclass(frozen=True)
class PolicySpec:
    name: str
    max_kbytes_per_second: int
    burst_kbytes: int

    @property
    def raw_max_kbps(self) -> int:
        return self.max_kbytes_per_second * 8

    @property
    def max_kbps(self) -> int:
        return (self.raw_max_kbps // 1_000_000) * 1_000_000

    @property
    def max_burst_kbps(self) -> int:
        return self.burst_kbytes * 8


@dataclass(frozen=True)
class FlavorSpec:
    name: str
    policy: str
    legacy: dict[str, int | None]


@dataclass(frozen=True)
class RegionSpec:
    name: str
    flavors: tuple[FlavorSpec, ...]


@dataclass(frozen=True)
class MappingSpec:
    policies: dict[str, PolicySpec]
    regions: dict[str, RegionSpec]
    expected_flavor_count: int


@dataclass
class PolicyPlan:
    name: str
    raw_max_kbps: int
    max_kbps: int
    max_burst_kbps: int
    policy_id: str | None = None
    action: str = "create"


@dataclass
class FlavorPlan:
    name: str
    flavor_id: str
    policy: str
    policy_id: str | None
    old_extra_specs: dict[str, str]
    new_extra_specs: dict[str, str]
    legacy_average_kbytes_per_second: int | None
    legacy_raw_max_kbps: int | None
    policy_max_kbps: int
    percent_change: float | None
    action: str


@dataclass
class InstancePlan:
    database: str
    instance_uuid: str
    flavor_name: str
    flavor_id: str
    policy: str
    policy_id: str | None
    old_hex: str
    new_hex: str | None
    action: str
    warning: str | None = None


@dataclass
class PortPlan:
    port_id: str
    instance_uuid: str
    flavor_name: str
    policy: str
    policy_id: str | None
    old_policy_id: str | None
    inherited_network_policy_id: str | None
    revision_number: int | None
    action: str


@dataclass
class RunPlan:
    region: str
    apply: bool
    policies: list[PolicyPlan] = field(default_factory=list)
    flavors: list[FlavorPlan] = field(default_factory=list)
    instances: list[InstancePlan] = field(default_factory=list)
    ports: list[PortPlan] = field(default_factory=list)
    conflicts: list[str] = field(default_factory=list)

    def planned_count(self) -> int:
        return sum(
            item.action not in {"noop", "reuse"}
            for group in (self.policies, self.flavors, self.instances, self.ports)
            for item in group
        )


def require_positive_integer(value: Any, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        raise MigrationError(f"{label} must be a positive integer")
    if value > (2**63 - 1) // 8:
        raise MigrationError(f"{label} is too large to convert safely")
    return value


def calculate_policy_rates(
    max_kbytes_per_second: Any, burst_kbytes: Any
) -> tuple[int, int, int]:
    maximum = require_positive_integer(max_kbytes_per_second, "max_kbytes_per_second")
    burst = require_positive_integer(burst_kbytes, "burst_kbytes")
    raw_max = maximum * 8
    rounded_max = (raw_max // 1_000_000) * 1_000_000
    if rounded_max == 0:
        raise MigrationError(
            "max_kbytes_per_second converts to less than 1,000,000 kbps "
            "and would round to zero"
        )
    return raw_max, rounded_max, burst * 8


def load_mapping(path: Path) -> MappingSpec:
    yaml = YAML(typ="safe")
    try:
        data = yaml.load(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise MigrationError(f"unable to read mapping {path}: {exc}") from exc
    if not isinstance(data, dict):
        raise MigrationError("mapping root must be an object")
    if data.get("schema_version") != 1:
        raise MigrationError("mapping schema_version must be 1")

    raw_policies = data.get("policies")
    if not isinstance(raw_policies, dict):
        raise MigrationError("mapping policies must be an object")
    if set(raw_policies) != EXPECTED_POLICIES:
        raise MigrationError(
            "mapping must define exactly these policies: "
            + ", ".join(sorted(EXPECTED_POLICIES))
        )
    policies: dict[str, PolicySpec] = {}
    for name, raw in raw_policies.items():
        if not isinstance(raw, dict):
            raise MigrationError(f"policy {name} must be an object")
        raw_max, rounded_max, converted_burst = calculate_policy_rates(
            raw.get("max_kbytes_per_second"), raw.get("burst_kbytes")
        )
        policy = PolicySpec(
            name=name,
            max_kbytes_per_second=raw["max_kbytes_per_second"],
            burst_kbytes=raw["burst_kbytes"],
        )
        if (
            policy.max_kbytes_per_second,
            policy.burst_kbytes,
        ) != EXPECTED_POLICY_SOURCES[name]:
            raise MigrationError(
                f"policy {name} source values must be "
                f"{EXPECTED_POLICY_SOURCES[name]}"
            )
        if (
            policy.raw_max_kbps != raw_max
            or policy.max_kbps != rounded_max
            or policy.max_burst_kbps != converted_burst
        ):
            raise MigrationError(f"internal conversion error for policy {name}")
        policies[name] = policy

    expected_count = require_positive_integer(
        data.get("expected_flavor_count"), "expected_flavor_count"
    )
    raw_regions = data.get("regions")
    if not isinstance(raw_regions, dict):
        raise MigrationError("mapping regions must be an object")
    if set(raw_regions) != set(EXPECTED_REGION_COUNTS):
        raise MigrationError(
            "mapping must define exactly these regions: "
            + ", ".join(sorted(EXPECTED_REGION_COUNTS))
        )
    regions: dict[str, RegionSpec] = {}
    all_flavors: set[tuple[str, str]] = set()
    total = 0
    for region_name, raw_region in raw_regions.items():
        if not isinstance(raw_region, dict):
            raise MigrationError(f"region {region_name} must be an object")
        raw_flavors = raw_region.get("flavors")
        if not isinstance(raw_flavors, dict) or not raw_flavors:
            raise MigrationError(f"region {region_name} has no flavors")
        expected_region_count = require_positive_integer(
            raw_region.get("expected_flavor_count"),
            f"regions.{region_name}.expected_flavor_count",
        )
        if expected_region_count != EXPECTED_REGION_COUNTS[region_name]:
            raise MigrationError(
                f"region {region_name} must declare "
                f"{EXPECTED_REGION_COUNTS[region_name]} flavors"
            )
        if len(raw_flavors) != expected_region_count:
            raise MigrationError(
                f"region {region_name} expected {expected_region_count} flavors "
                f"but contains {len(raw_flavors)}"
            )
        flavors: list[FlavorSpec] = []
        for flavor_name, raw_flavor in raw_flavors.items():
            if not isinstance(flavor_name, str) or not flavor_name:
                raise MigrationError(f"region {region_name} has an invalid flavor name")
            if not isinstance(raw_flavor, dict):
                raise MigrationError(
                    f"flavor {region_name}/{flavor_name} must be an object"
                )
            policy_name = raw_flavor.get("policy")
            if policy_name not in policies:
                raise MigrationError(
                    f"flavor {region_name}/{flavor_name} references unknown "
                    f"policy {policy_name!r}"
                )
            raw_legacy = raw_flavor.get("legacy", {})
            if not isinstance(raw_legacy, dict):
                raise MigrationError(
                    f"flavor {region_name}/{flavor_name} legacy must be an object"
                )
            unknown = set(raw_legacy) - set(LEGACY_KEYS)
            if unknown:
                raise MigrationError(
                    f"flavor {region_name}/{flavor_name} has unsupported legacy "
                    f"keys: {', '.join(sorted(unknown))}"
                )
            legacy: dict[str, int | None] = {}
            for key in LEGACY_KEYS:
                value = raw_legacy.get(key)
                if value is not None:
                    value = require_positive_integer(
                        value, f"{region_name}/{flavor_name}/{key}"
                    )
                legacy[key] = value
            marker = (region_name.casefold(), flavor_name.casefold())
            if marker in all_flavors:
                raise MigrationError(
                    f"duplicate flavor mapping {region_name}/{flavor_name}"
                )
            all_flavors.add(marker)
            flavors.append(FlavorSpec(flavor_name, policy_name, legacy))
        total += len(flavors)
        regions[region_name] = RegionSpec(region_name, tuple(flavors))
    if total != expected_count:
        raise MigrationError(
            f"mapping expected {expected_count} total flavors but contains {total}"
        )
    return MappingSpec(policies, regions, expected_count)


def quoted_database(name: str) -> str:
    if not DB_NAME_RE.fullmatch(name):
        raise MigrationError(f"invalid database name: {name}")
    return f"`{name}`"


def sql_string(value: str) -> str:
    return "'" + value.replace("\\", "\\\\").replace("'", "''") + "'"


def flavor_data(primitive: dict[str, Any]) -> dict[str, Any]:
    try:
        current = primitive["cur"]
        data = current["nova_object.data"]
    except (KeyError, TypeError) as exc:
        raise MigrationError(
            "cached flavor does not contain cur.nova_object.data"
        ) from exc
    if not isinstance(data, dict):
        raise MigrationError("cached flavor cur.nova_object.data is not an object")
    return data


def cached_flavor_id(primitive: dict[str, Any]) -> str:
    value = flavor_data(primitive).get("flavorid")
    if value is None:
        raise MigrationError("cached flavor is missing flavorid")
    return str(value)


def migrate_cached_flavor(serialized: str, policy_id: str) -> tuple[str, bool]:
    if not UUID_RE.fullmatch(policy_id):
        raise MigrationError(f"invalid QoS policy UUID: {policy_id}")
    try:
        primitive = json.loads(serialized)
    except json.JSONDecodeError as exc:
        raise MigrationError(f"cached flavor is invalid JSON: {exc}") from exc
    if not isinstance(primitive, dict):
        raise MigrationError("cached flavor JSON root is not an object")
    updated = copy.deepcopy(primitive)
    data = flavor_data(updated)
    extra_specs = data.get("extra_specs")
    if extra_specs is None:
        extra_specs = {}
        data["extra_specs"] = extra_specs
    if not isinstance(extra_specs, dict):
        raise MigrationError("cached flavor extra_specs is not an object")
    before = copy.deepcopy(extra_specs)
    for key in LEGACY_KEYS:
        extra_specs.pop(key, None)
    extra_specs[POLICY_EXTRA_SPEC] = policy_id
    changed = before != extra_specs
    if not changed:
        return serialized, False
    return json.dumps(updated, ensure_ascii=False), True


class MariaDBClient:
    def __init__(self, args: argparse.Namespace):
        self.args = args

    def command(self) -> tuple[list[str], dict[str, str]]:
        command = [self.args.mysql_command]
        if self.args.defaults_file:
            command.append(f"--defaults-extra-file={self.args.defaults_file}")
        command.extend(["--batch", "--raw", "--skip-column-names"])
        if self.args.mysql_host:
            command.extend(["--host", self.args.mysql_host])
        if self.args.mysql_port:
            command.extend(["--port", str(self.args.mysql_port)])
        if self.args.mysql_user:
            command.extend(["--user", self.args.mysql_user])
        if self.args.mysql_socket:
            command.extend(["--socket", self.args.mysql_socket])
        env = os.environ.copy()
        password = self.args.mysql_password
        if self.args.mysql_password_env:
            password = os.environ.get(self.args.mysql_password_env)
            if password is None:
                raise MigrationError(
                    f"environment variable {self.args.mysql_password_env} is not set"
                )
        if password:
            env["MYSQL_PWD"] = password
        return command, env

    def execute(self, sql: str) -> str:
        command, env = self.command()
        try:
            result = subprocess.run(
                command,
                input=sql,
                text=True,
                capture_output=True,
                timeout=self.args.command_timeout,
                env=env,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise MigrationError(f"MariaDB command failed: {exc}") from exc
        if result.returncode:
            detail = result.stderr.strip() or f"exit code {result.returncode}"
            raise MigrationError(f"MariaDB command failed: {detail}")
        return result.stdout

    def read_instances(self, database: str) -> list[tuple[str, str, str, str]]:
        db = quoted_database(database)
        sql = f"""
SELECT i.uuid, IFNULL(i.vm_state, ''), IFNULL(i.task_state, ''), HEX(ie.flavor)
FROM {db}.instances AS i
JOIN {db}.instance_extra AS ie ON ie.instance_uuid = i.uuid
WHERE i.deleted = 0 AND ie.deleted = 0 AND ie.flavor IS NOT NULL;
"""
        rows = []
        for line in self.execute(sql).splitlines():
            parts = line.split("\t")
            if len(parts) != 4:
                raise MigrationError(f"unexpected MariaDB instance row: {line!r}")
            rows.append((parts[0], parts[1], parts[2], parts[3]))
        return rows

    def active_migrations(self, database: str) -> dict[str, list[str]]:
        db = quoted_database(database)
        terminal = ", ".join(sql_string(value) for value in TERMINAL_MIGRATION_STATES)
        sql = f"""
SELECT instance_uuid, id, IFNULL(migration_type, ''), IFNULL(status, ''),
       IFNULL(updated_at, created_at)
FROM {db}.migrations
WHERE deleted = 0
  AND instance_uuid IS NOT NULL
  AND LOWER(IFNULL(status, '')) NOT IN ({terminal})
ORDER BY instance_uuid, id;
"""
        migrations: dict[str, list[str]] = {}
        for line in self.execute(sql).splitlines():
            parts = line.split("\t")
            if len(parts) != 5:
                raise MigrationError(f"unexpected MariaDB migration row: {line!r}")
            instance_uuid, migration_id, migration_type, status, updated_at = parts
            migrations.setdefault(instance_uuid, []).append(
                f"id={migration_id} type={migration_type or 'unknown'} "
                f"status={status or 'unknown'} updated_at={updated_at}"
            )
        return migrations

    def apply_cached_flavors(
        self, database: str, changes: list[InstancePlan], reverse: bool = False
    ) -> None:
        actionable = [change for change in changes if change.action == "update"]
        if not actionable:
            return
        db = quoted_database(database)
        values = []
        for change in actionable:
            old_hex = change.new_hex if reverse else change.old_hex
            new_hex = change.old_hex if reverse else change.new_hex
            if not old_hex or not new_hex:
                raise MigrationError(
                    f"missing cached flavor state for {change.instance_uuid}"
                )
            values.append(
                f"({sql_string(change.instance_uuid)}, {sql_string(old_hex)}, "
                f"{sql_string(new_hex)})"
            )
        joined_values = ",\n".join(values)
        sql = f"""
USE {db};
CREATE TEMPORARY TABLE flavor_qos_updates (
  instance_uuid varchar(36) PRIMARY KEY,
  old_hex longtext NOT NULL,
  new_hex longtext NOT NULL
) ENGINE=InnoDB;
INSERT INTO flavor_qos_updates (instance_uuid, old_hex, new_hex) VALUES
{joined_values};
START TRANSACTION;
UPDATE {db}.instance_extra AS ie
JOIN {db}.instances AS i
  ON i.uuid = ie.instance_uuid AND i.deleted = 0
JOIN flavor_qos_updates AS u ON u.instance_uuid = ie.instance_uuid
SET ie.flavor = CONVERT(UNHEX(u.new_hex) USING utf8mb4),
    ie.updated_at = UTC_TIMESTAMP()
WHERE ie.deleted = 0
  AND i.task_state IS NULL
  AND LOWER(IFNULL(i.vm_state, '')) <> 'resized'
  AND HEX(ie.flavor) = u.old_hex;
SET @flavor_qos_changed = ROW_COUNT();
SET @flavor_qos_tx = IF(
  @flavor_qos_changed = {len(actionable)}, 'COMMIT', 'ROLLBACK'
);
PREPARE flavor_qos_tx_stmt FROM @flavor_qos_tx;
EXECUTE flavor_qos_tx_stmt;
DEALLOCATE PREPARE flavor_qos_tx_stmt;
SELECT CONCAT('__FLAVOR_QOS_CHANGED__', @flavor_qos_changed);
"""
        output = self.execute(sql)
        marker = "__FLAVOR_QOS_CHANGED__"
        counts = [
            line[len(marker) :]
            for line in output.splitlines()
            if line.startswith(marker)
        ]
        if counts != [str(len(actionable))]:
            actual = counts[0] if counts else "unknown"
            raise MigrationError(
                f"cached flavor compare-and-swap failed in {database}: "
                f"expected {len(actionable)} rows, matched {actual}; transaction rolled back"
            )


class KubectlMariaDBTunnel:
    """Manage an ephemeral kubectl port-forward and database credentials."""

    def __init__(self, args: argparse.Namespace):
        self.args = args
        self.process: subprocess.Popen[str] | None = None
        self.original = {
            "mysql_host": args.mysql_host,
            "mysql_port": args.mysql_port,
            "mysql_user": args.mysql_user,
            "mysql_password": args.mysql_password,
        }

    def kubectl_base(self) -> list[str]:
        command = [self.args.kubectl_command]
        if self.args.kube_context:
            command.extend(["--context", self.args.kube_context])
        command.extend(["--namespace", self.args.kube_namespace])
        return command

    def read_password(self) -> str:
        command = self.kubectl_base() + [
            "get",
            "secret",
            self.args.mariadb_secret,
            "--output",
            f"jsonpath={{.data.{self.args.mariadb_secret_key}}}",
        ]
        try:
            result = subprocess.run(
                command,
                text=True,
                capture_output=True,
                timeout=self.args.command_timeout,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise MigrationError(
                f"unable to read MariaDB Kubernetes Secret: {exc}"
            ) from exc
        if result.returncode:
            detail = result.stderr.strip() or f"exit code {result.returncode}"
            raise MigrationError(f"unable to read MariaDB Kubernetes Secret: {detail}")
        try:
            password = base64.b64decode(result.stdout.strip(), validate=True).decode(
                "utf-8"
            )
        except (ValueError, UnicodeDecodeError) as exc:
            raise MigrationError(
                "MariaDB Kubernetes Secret contains an invalid base64 password"
            ) from exc
        if not password:
            raise MigrationError("MariaDB Kubernetes Secret password is empty")
        return password

    def wait_until_ready(self) -> int:
        if not self.process or not self.process.stdout:
            raise MigrationError("kubectl port-forward did not expose an output stream")
        deadline = time.monotonic() + self.args.port_forward_timeout
        selector = selectors.DefaultSelector()
        selector.register(self.process.stdout, selectors.EVENT_READ)
        try:
            while time.monotonic() < deadline:
                if self.process.poll() is not None:
                    detail = self.process.stdout.read().strip()
                    raise MigrationError(
                        "kubectl port-forward exited before becoming ready"
                        + (f": {detail}" if detail else "")
                    )
                remaining = max(0.0, deadline - time.monotonic())
                if not selector.select(timeout=min(0.25, remaining)):
                    continue
                line = self.process.stdout.readline()
                match = PORT_FORWARD_RE.search(line)
                if match:
                    return int(match.group(1))
            raise MigrationError(
                f"kubectl port-forward was not ready within "
                f"{self.args.port_forward_timeout} seconds"
            )
        finally:
            selector.close()

    def start(self) -> None:
        password = self.read_password()
        command = self.kubectl_base() + [
            "port-forward",
            f"service/{self.args.mariadb_service}",
            ":3306",
            "--address",
            "127.0.0.1",
        ]
        log(
            self.args,
            f"Starting MariaDB port-forward to service/{self.args.mariadb_service}",
        )
        try:
            self.process = subprocess.Popen(
                command,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                bufsize=1,
            )
            port = self.wait_until_ready()
            self.args.mysql_host = "127.0.0.1"
            self.args.mysql_port = port
            self.args.mysql_user = self.args.mariadb_secret_user
            self.args.mysql_password = password
            log(self.args, f"MariaDB port-forward is ready on 127.0.0.1:{port}")
        except Exception:
            self.stop()
            raise

    def stop(self) -> None:
        process = self.process
        self.process = None
        if process is not None and process.poll() is None:
            try:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
            except (OSError, subprocess.TimeoutExpired) as exc:
                log(self.args, f"Warning: unable to reap MariaDB port-forward: {exc}")
        for name, value in self.original.items():
            setattr(self.args, name, value)
        if process is not None:
            log(self.args, "MariaDB port-forward stopped")


def connect_openstack(cloud: str, timeout: int):
    try:
        import openstack
    except ImportError as exc:
        raise MigrationError("openstacksdk is required") from exc
    try:
        return openstack.connect(cloud=cloud, timeout=timeout)
    except Exception as exc:  # SDK exception hierarchy varies by release.
        raise MigrationError(
            f"unable to connect to OpenStack cloud {cloud}: {exc}"
        ) from exc


def require_admin_scope(conn: Any) -> None:
    """Fail closed unless the current token contains an admin role."""
    try:
        access = conn.session.auth.get_access(conn.session)
        role_names = {
            str(role).casefold() for role in getattr(access, "role_names", [])
        }
    except Exception as exc:
        raise MigrationError(
            f"unable to validate OpenStack token roles: {exc}"
        ) from exc
    if "admin" not in role_names:
        displayed = ", ".join(sorted(role_names)) or "none"
        raise MigrationError(
            f"admin-scoped OpenStack credentials are required; token roles: {displayed}"
        )
    if not getattr(conn, "current_project_id", None):
        raise MigrationError("OpenStack token is not scoped to a project")


def resource_value(resource: Any, name: str, default: Any = None) -> Any:
    value = getattr(resource, name, default)
    return default if value is None else value


def find_policies(conn: Any, mapping: MappingSpec) -> list[PolicyPlan]:
    current_project_id = getattr(conn, "current_project_id", None)
    plans: list[PolicyPlan] = []
    for spec in mapping.policies.values():
        candidates = [
            policy
            for policy in conn.network.qos_policies(name=spec.name)
            if not current_project_id
            or resource_value(policy, "project_id") == current_project_id
        ]
        if len(candidates) > 1:
            raise MigrationError(
                f"multiple QoS policies named {spec.name!r} exist in the scoped project"
            )
        plan = PolicyPlan(
            spec.name,
            spec.raw_max_kbps,
            spec.max_kbps,
            spec.max_burst_kbps,
        )
        if not candidates:
            plans.append(plan)
            continue
        policy = candidates[0]
        if bool(resource_value(policy, "is_shared", False)):
            raise MigrationError(
                f"QoS policy {spec.name} is shared; expected non-shared"
            )
        if bool(resource_value(policy, "is_default", False)):
            raise MigrationError(
                f"QoS policy {spec.name} is default; expected non-default"
            )
        rules = list(conn.network.qos_bandwidth_limit_rules(policy))
        if len(rules) != 1:
            raise MigrationError(
                f"QoS policy {spec.name} must have exactly one bandwidth-limit rule"
            )
        rule = rules[0]
        actual = (
            int(resource_value(rule, "max_kbps", 0)),
            int(resource_value(rule, "max_burst_kbps", 0)),
            resource_value(rule, "direction"),
        )
        expected = (spec.max_kbps, spec.max_burst_kbps, "egress")
        if actual != expected:
            raise MigrationError(
                f"QoS policy {spec.name} rule mismatch: expected {expected}, got {actual}"
            )
        for collection_name in OTHER_QOS_RULE_COLLECTIONS:
            collection = getattr(conn.network, collection_name, None)
            if collection is not None and list(collection(policy)):
                raise MigrationError(
                    f"QoS policy {spec.name} has an unexpected rule type "
                    f"reported by {collection_name}"
                )
        plan.policy_id = str(policy.id)
        plan.action = "reuse"
        plans.append(plan)
    return plans


def create_missing_policies(conn: Any, plans: list[PolicyPlan]) -> None:
    for plan in plans:
        if plan.policy_id:
            continue
        policy = conn.network.create_qos_policy(
            name=plan.name,
            project_id=conn.current_project_id,
            is_shared=False,
            is_default=False,
        )
        if (
            resource_value(policy, "project_id") != conn.current_project_id
            or bool(resource_value(policy, "is_shared", False))
            or bool(resource_value(policy, "is_default", False))
        ):
            raise MigrationError(
                f"created QoS policy {plan.name} has wrong ownership or flags"
            )
        rule = conn.network.create_qos_bandwidth_limit_rule(
            policy,
            max_kbps=plan.max_kbps,
            max_burst_kbps=plan.max_burst_kbps,
            direction="egress",
        )
        if (
            int(resource_value(rule, "max_kbps", 0)) != plan.max_kbps
            or int(resource_value(rule, "max_burst_kbps", 0)) != plan.max_burst_kbps
            or resource_value(rule, "direction") != "egress"
        ):
            raise MigrationError(
                f"created QoS rule for {plan.name} failed verification"
            )
        plan.policy_id = str(policy.id)
        plan.action = "created"


def policy_ids(plans: list[PolicyPlan]) -> dict[str, str | None]:
    return {plan.name: plan.policy_id for plan in plans}


def resolve_flavors(
    conn: Any,
    region: RegionSpec,
    mapping: MappingSpec,
    ids: dict[str, str | None],
) -> list[FlavorPlan]:
    plans: list[FlavorPlan] = []
    flavors_by_name: dict[str, list[Any]] = {}
    for flavor in conn.compute.flavors(is_public=None):
        flavors_by_name.setdefault(str(resource_value(flavor, "name")), []).append(
            flavor
        )
    for spec in region.flavors:
        candidates = flavors_by_name.get(spec.name, [])
        if len(candidates) != 1:
            raise MigrationError(
                f"expected exactly one flavor named {spec.name!r}; found {len(candidates)}"
            )
        flavor = candidates[0]
        fetched = conn.compute.fetch_flavor_extra_specs(flavor)
        old_specs = dict(resource_value(fetched, "extra_specs", {}) or {})
        target_id = ids[spec.policy]
        existing_policy = old_specs.get(POLICY_EXTRA_SPEC)
        if existing_policy and (not target_id or existing_policy != target_id):
            raise MigrationError(
                f"flavor {spec.name} has conflicting {POLICY_EXTRA_SPEC}={existing_policy}"
            )
        for key, expected in spec.legacy.items():
            actual = old_specs.get(key)
            if actual is None:
                if expected is not None and existing_policy != target_id:
                    raise MigrationError(
                        f"flavor {spec.name} is missing expected {key}={expected!r}"
                    )
                continue
            if expected is None or str(actual) != str(expected):
                raise MigrationError(
                    f"flavor {spec.name} has unexpected {key}={actual!r}; "
                    f"mapping expects {expected!r}"
                )
        new_specs = dict(old_specs)
        for key in LEGACY_KEYS:
            new_specs.pop(key, None)
        if target_id:
            new_specs[POLICY_EXTRA_SPEC] = target_id
        legacy_average = spec.legacy.get("quota:vif_outbound_average")
        policy = mapping.policies[spec.policy]
        legacy_raw_max = None
        percent = None
        if legacy_average:
            legacy_raw_max = legacy_average * 8
            percent = ((policy.max_kbps - legacy_raw_max) / legacy_raw_max) * 100
        action = "noop" if old_specs == new_specs and target_id else "update"
        plans.append(
            FlavorPlan(
                spec.name,
                str(flavor.id),
                spec.policy,
                target_id,
                old_specs,
                new_specs,
                legacy_average,
                legacy_raw_max,
                policy.max_kbps,
                percent,
                action,
            )
        )
    return plans


def apply_flavors(conn: Any, plans: list[FlavorPlan]) -> None:
    for plan in plans:
        if plan.action == "noop":
            continue
        if not plan.policy_id:
            raise MigrationError(f"policy ID is unavailable for flavor {plan.name}")
        current = conn.compute.fetch_flavor_extra_specs(plan.flavor_id)
        actual = dict(resource_value(current, "extra_specs", {}) or {})
        if actual != plan.old_extra_specs:
            raise MigrationError(
                f"flavor {plan.name} changed after preflight; refusing to overwrite it"
            )
        conn.compute.create_flavor_extra_specs(
            plan.flavor_id, {POLICY_EXTRA_SPEC: plan.policy_id}
        )
        for key in LEGACY_KEYS:
            if key in actual:
                conn.compute.delete_flavor_extra_specs_property(plan.flavor_id, key)
        verified = conn.compute.fetch_flavor_extra_specs(plan.flavor_id)
        if (
            dict(resource_value(verified, "extra_specs", {}) or {})
            != plan.new_extra_specs
        ):
            raise MigrationError(f"flavor {plan.name} failed post-update verification")


def plan_instances(
    client: MariaDBClient,
    databases: list[str],
    flavors: list[FlavorPlan],
) -> list[InstancePlan]:
    by_id = {plan.flavor_id: plan for plan in flavors}
    plans: list[InstancePlan] = []
    seen: set[str] = set()
    for database in databases:
        active_migrations = client.active_migrations(database)
        for instance_uuid, vm_state, task_state, flavor_hex in client.read_instances(
            database
        ):
            try:
                serialized = bytes.fromhex(flavor_hex).decode("utf-8")
                primitive = json.loads(serialized)
                flavor_id = cached_flavor_id(primitive)
            except (
                ValueError,
                UnicodeDecodeError,
                json.JSONDecodeError,
                MigrationError,
            ) as exc:
                raise MigrationError(
                    f"unable to inspect cached flavor for {database}/{instance_uuid}: {exc}"
                ) from exc
            flavor = by_id.get(flavor_id)
            if not flavor:
                continue
            if instance_uuid in seen:
                raise MigrationError(
                    f"instance {instance_uuid} appears in multiple cells"
                )
            seen.add(instance_uuid)
            if task_state:
                raise MigrationError(
                    f"instance {instance_uuid} has active task_state {task_state!r}"
                )
            if vm_state.casefold() == "resized":
                raise MigrationError(
                    f"instance {instance_uuid} has vm_state 'resized' and is awaiting "
                    "resize confirm or revert"
                )
            migration_rows = active_migrations.get(instance_uuid, [])
            warning = None
            if migration_rows:
                warning = (
                    "ignored stale non-terminal migration row(s) because the instance "
                    f"has vm_state={vm_state!r} and no task_state: "
                    + "; ".join(migration_rows)
                )
            if not flavor.policy_id:
                new_serialized = None
                changed = True
            else:
                try:
                    new_serialized, changed = migrate_cached_flavor(
                        serialized, flavor.policy_id
                    )
                except MigrationError as exc:
                    raise MigrationError(
                        f"unable to migrate cached flavor for {database}/{instance_uuid}: {exc}"
                    ) from exc
            plans.append(
                InstancePlan(
                    database,
                    instance_uuid,
                    flavor.name,
                    flavor.flavor_id,
                    flavor.policy,
                    flavor.policy_id,
                    flavor_hex.upper(),
                    (
                        new_serialized.encode("utf-8").hex().upper()
                        if new_serialized is not None
                        else None
                    ),
                    "update" if changed else "noop",
                    warning,
                )
            )
    return plans


def plan_ports(conn: Any, instances: list[InstancePlan]) -> list[PortPlan]:
    plans: list[PortPlan] = []
    network_cache: dict[str, str | None] = {}
    for instance in instances:
        ports = list(conn.network.ports(device_id=instance.instance_uuid))
        for port in ports:
            owner = str(resource_value(port, "device_owner", ""))
            if not owner.startswith("compute:"):
                continue
            old_policy = resource_value(port, "qos_policy_id")
            target = instance.policy_id
            if old_policy and (not target or old_policy != target):
                raise MigrationError(
                    f"port {port.id} on instance {instance.instance_uuid} has "
                    f"conflicting qos_policy_id {old_policy}"
                )
            network_id = str(resource_value(port, "network_id", ""))
            inherited = None
            if not old_policy and network_id:
                if network_id not in network_cache:
                    network = conn.network.get_network(network_id)
                    network_cache[network_id] = resource_value(network, "qos_policy_id")
                inherited = network_cache[network_id]
            action = "noop" if target and old_policy == target else "update"
            plans.append(
                PortPlan(
                    str(port.id),
                    instance.instance_uuid,
                    instance.flavor_name,
                    instance.policy,
                    target,
                    old_policy,
                    inherited,
                    resource_value(port, "revision_number"),
                    action,
                )
            )
    return plans


def apply_instances(client: MariaDBClient, plans: list[InstancePlan]) -> None:
    databases = sorted({plan.database for plan in plans})
    for database in databases:
        client.apply_cached_flavors(
            database, [plan for plan in plans if plan.database == database]
        )


def apply_ports(conn: Any, plans: list[PortPlan]) -> None:
    for plan in plans:
        if plan.action == "noop":
            continue
        if not plan.policy_id:
            raise MigrationError(f"policy ID is unavailable for port {plan.port_id}")
        current = conn.network.get_port(plan.port_id)
        current_policy = resource_value(current, "qos_policy_id")
        if current_policy != plan.old_policy_id:
            raise MigrationError(
                f"port {plan.port_id} changed after preflight; refusing to overwrite it"
            )
        conn.network.update_port(
            current,
            if_revision=resource_value(current, "revision_number"),
            qos_policy_id=plan.policy_id,
        )
        stored = conn.network.get_port(plan.port_id)
        if resource_value(stored, "qos_policy_id") != plan.policy_id:
            raise MigrationError(f"port {plan.port_id} failed post-update verification")


def state_payload(plan: RunPlan, cloud: str, status: str) -> dict[str, Any]:
    return {
        "schema_version": 1,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "status": status,
        "cloud": cloud,
        "region": plan.region,
        "policies": [asdict(item) for item in plan.policies],
        "flavors": [asdict(item) for item in plan.flavors],
        "instances": [asdict(item) for item in plan.instances],
        "ports": [asdict(item) for item in plan.ports],
    }


def write_state(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        "w", encoding="utf-8", dir=path.parent, delete=False
    ) as handle:
        json.dump(payload, handle, indent=2, sort_keys=True)
        handle.write("\n")
        temporary = Path(handle.name)
    os.chmod(temporary, 0o600)
    temporary.replace(path)


def rollback(
    args: argparse.Namespace, conn: Any, client: MariaDBClient, state_path: Path
) -> int:
    try:
        payload = json.loads(state_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise MigrationError(f"unable to read rollback state: {exc}") from exc
    if payload.get("schema_version") != 1:
        raise MigrationError("unsupported rollback state schema")
    ports = [PortPlan(**item) for item in payload.get("ports", [])]
    instances = [InstancePlan(**item) for item in payload.get("instances", [])]
    flavors = [FlavorPlan(**item) for item in payload.get("flavors", [])]
    policies = [PolicyPlan(**item) for item in payload.get("policies", [])]

    for plan in reversed(ports):
        if plan.action == "noop" or not plan.policy_id:
            continue
        current = conn.network.get_port(plan.port_id)
        if resource_value(current, "qos_policy_id") != plan.policy_id:
            raise MigrationError(
                f"port {plan.port_id} no longer matches applied state; rollback stopped"
            )
        conn.network.update_port(
            current,
            if_revision=resource_value(current, "revision_number"),
            qos_policy_id=plan.old_policy_id,
        )
        restored = conn.network.get_port(plan.port_id)
        if resource_value(restored, "qos_policy_id") != plan.old_policy_id:
            raise MigrationError(f"port {plan.port_id} failed rollback verification")
    for database in sorted({plan.database for plan in instances}):
        client.apply_cached_flavors(
            database,
            [plan for plan in instances if plan.database == database],
            reverse=True,
        )
    for plan in reversed(flavors):
        if plan.action == "noop":
            continue
        current = conn.compute.fetch_flavor_extra_specs(plan.flavor_id)
        actual = dict(resource_value(current, "extra_specs", {}) or {})
        if actual != plan.new_extra_specs:
            raise MigrationError(
                f"flavor {plan.name} no longer matches applied state; rollback stopped"
            )
        if plan.old_extra_specs:
            conn.compute.create_flavor_extra_specs(plan.flavor_id, plan.old_extra_specs)
        for key in set(plan.new_extra_specs) - set(plan.old_extra_specs):
            conn.compute.delete_flavor_extra_specs_property(plan.flavor_id, key)
        restored = conn.compute.fetch_flavor_extra_specs(plan.flavor_id)
        if (
            dict(resource_value(restored, "extra_specs", {}) or {})
            != plan.old_extra_specs
        ):
            raise MigrationError(f"flavor {plan.name} failed rollback verification")
    for plan in reversed(policies):
        if plan.action != "created" or not plan.policy_id:
            continue
        if any(
            resource_value(port, "qos_policy_id") == plan.policy_id
            for port in conn.network.ports()
        ):
            raise MigrationError(f"created policy {plan.name} is still used by a port")
        if any(
            resource_value(network, "qos_policy_id") == plan.policy_id
            for network in conn.network.networks()
        ):
            raise MigrationError(
                f"created policy {plan.name} is still used by a network"
            )
        policy = conn.network.get_qos_policy(plan.policy_id)
        if (
            resource_value(policy, "name") != plan.name
            or resource_value(policy, "project_id") != conn.current_project_id
            or bool(resource_value(policy, "is_shared", False))
            or bool(resource_value(policy, "is_default", False))
        ):
            raise MigrationError(f"created policy {plan.name} changed after apply")
        rules = list(conn.network.qos_bandwidth_limit_rules(policy))
        if len(rules) != 1:
            raise MigrationError(f"created policy {plan.name} changed after apply")
        rule = rules[0]
        actual = (
            int(resource_value(rule, "max_kbps", 0)),
            int(resource_value(rule, "max_burst_kbps", 0)),
            resource_value(rule, "direction"),
        )
        if actual != (plan.max_kbps, plan.max_burst_kbps, "egress"):
            raise MigrationError(f"created policy {plan.name} changed after apply")
        for flavor in conn.compute.flavors(is_public=None):
            current = conn.compute.fetch_flavor_extra_specs(flavor)
            specs = dict(resource_value(current, "extra_specs", {}) or {})
            if specs.get(POLICY_EXTRA_SPEC) == plan.policy_id:
                raise MigrationError(
                    f"created policy {plan.name} is still used by flavor "
                    f"{resource_value(flavor, 'name', flavor.id)}"
                )
        conn.network.delete_qos_bandwidth_limit_rule(rule, policy)
        conn.network.delete_qos_policy(policy)
    payload["status"] = "rolled_back"
    payload["rolled_back_at"] = datetime.now(timezone.utc).isoformat()
    write_state(state_path, payload)
    return EXIT_OK


def report_dict(plan: RunPlan) -> dict[str, Any]:
    warnings = [item.warning for item in plan.instances if item.warning]
    return {
        "summary": {
            "region": plan.region,
            "apply": plan.apply,
            "planned_actions": plan.planned_count(),
            "policy_count": len(plan.policies),
            "flavor_count": len(plan.flavors),
            "instance_count": len(plan.instances),
            "port_count": len(plan.ports),
            "conflict_count": len(plan.conflicts),
            "warning_count": len(warnings),
        },
        "policies": [asdict(item) for item in plan.policies],
        "flavors": [asdict(item) for item in plan.flavors],
        "instances": [asdict(item) for item in plan.instances],
        "ports": [asdict(item) for item in plan.ports],
        "conflicts": plan.conflicts,
        "warnings": warnings,
    }


def print_report(plan: RunPlan, output_format: str) -> None:
    report = report_dict(plan)
    if output_format == "json":
        print(json.dumps(report, indent=2, sort_keys=True))
        return
    summary = report["summary"]
    print(
        f"region={summary['region']} apply={str(summary['apply']).lower()} "
        f"planned_actions={summary['planned_actions']} policies={summary['policy_count']} "
        f"flavors={summary['flavor_count']} instances={summary['instance_count']} "
        f"ports={summary['port_count']}"
    )
    print("\nPolicies:")
    for item in plan.policies:
        print(
            f"  {item.name}: raw_max_kbps={item.raw_max_kbps} "
            f"max_kbps={item.max_kbps} max_burst_kbps={item.max_burst_kbps} "
            f"action={item.action} id={item.policy_id or '<create>'}"
        )
    print("\nFlavors:")
    for item in plan.flavors:
        before = (
            f"{item.legacy_average_kbytes_per_second} kB/s"
            if item.legacy_average_kbytes_per_second is not None
            else "none"
        )
        change = (
            f"{item.percent_change:+.1f}%" if item.percent_change is not None else "n/a"
        )
        print(
            f"  {item.name}: policy={item.policy} legacy_average={before} "
            f"legacy_raw_max={item.legacy_raw_max_kbps if item.legacy_raw_max_kbps is not None else 'n/a'} kbps "
            f"rounded_policy_max={item.policy_max_kbps} kbps "
            f"change={change} action={item.action}"
        )
    inherited = sum(bool(item.inherited_network_policy_id) for item in plan.ports)
    print(
        f"\nCached instances: {len(plan.instances)}; ports: {len(plan.ports)}; "
        f"ports overriding inherited network QoS: {inherited}"
    )
    warnings = [item.warning for item in plan.instances if item.warning]
    if warnings:
        print("\nWarnings:")
        for warning in warnings:
            print(f"  {warning}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Migrate Nova flavor bandwidth extra specs to Neutron QoS"
    )
    parser.add_argument("--map-file", type=Path, required=False)
    parser.add_argument("--region")
    parser.add_argument("--os-cloud")
    parser.add_argument("--nova-database", action="append", default=[])
    parser.add_argument("--validate-map-only", action="store_true")
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--yes-im-really-sure", action="store_true")
    parser.add_argument("--rollback-state", type=Path)
    parser.add_argument("--state-dir", type=Path, default=Path("flavor-qos-state"))
    parser.add_argument("--format", choices=("text", "json"), default="text")
    parser.add_argument("--quiet", action="store_true")
    parser.add_argument("--api-timeout", type=int, default=60)
    parser.add_argument("--command-timeout", type=int, default=120)
    parser.add_argument("--mysql-command", default="mariadb")
    parser.add_argument("--defaults-file")
    parser.add_argument("--mysql-host")
    parser.add_argument("--mysql-port", type=int)
    parser.add_argument("--mysql-user")
    parser.add_argument("--mysql-password")
    parser.add_argument("--mysql-password-env")
    parser.add_argument("--mysql-socket")
    parser.add_argument("--kubectl-port-forward", action="store_true")
    parser.add_argument("--kubectl-command", default="kubectl")
    parser.add_argument("--kube-context")
    parser.add_argument("--kube-namespace", default="openstack")
    parser.add_argument("--mariadb-service", default="mariadb-cluster-primary")
    parser.add_argument("--mariadb-secret", default="mariadb")
    parser.add_argument("--mariadb-secret-key", default="root-password")
    parser.add_argument("--mariadb-secret-user", default="root")
    parser.add_argument("--port-forward-timeout", type=int, default=30)
    return parser


def validate_args(args: argparse.Namespace, parser: argparse.ArgumentParser) -> None:
    for option in ("api_timeout", "command_timeout", "port_forward_timeout"):
        if getattr(args, option) <= 0:
            parser.error(f"--{option.replace('_', '-')} must be positive")
    if args.apply and not args.yes_im_really_sure:
        parser.error("--apply requires --yes-im-really-sure")
    if args.kubectl_port_forward:
        conflicts = {
            "--defaults-file": args.defaults_file,
            "--mysql-host": args.mysql_host,
            "--mysql-port": args.mysql_port,
            "--mysql-user": args.mysql_user,
            "--mysql-password": args.mysql_password,
            "--mysql-password-env": args.mysql_password_env,
            "--mysql-socket": args.mysql_socket,
        }
        selected = [name for name, value in conflicts.items() if value]
        if selected:
            parser.error(
                "--kubectl-port-forward cannot be combined with " + ", ".join(selected)
            )
    if args.rollback_state and not (args.apply and args.yes_im_really_sure):
        parser.error("--rollback-state requires --apply --yes-im-really-sure")
    if args.rollback_state:
        if not args.os_cloud:
            parser.error("--rollback-state requires --os-cloud")
        return
    if not args.map_file:
        parser.error("--map-file is required")
    if args.validate_map_only:
        return
    for option in ("region", "os_cloud"):
        if not getattr(args, option):
            parser.error(f"--{option.replace('_', '-')} is required")
    if not args.nova_database:
        parser.error("at least one --nova-database is required")
    if len(set(args.nova_database)) != len(args.nova_database):
        parser.error("--nova-database values must be unique")
    for database in args.nova_database:
        quoted_database(database)


def log(args: argparse.Namespace, message: str) -> None:
    if not args.quiet:
        print(message, file=sys.stderr)


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    mutation_started = False
    tunnel: KubectlMariaDBTunnel | None = None
    try:
        validate_args(args, parser)
        if args.kubectl_port_forward and not args.validate_map_only:
            tunnel = KubectlMariaDBTunnel(args)
            tunnel.start()
        if args.rollback_state:
            conn = connect_openstack(args.os_cloud, args.api_timeout)
            require_admin_scope(conn)
            mutation_started = True
            return rollback(args, conn, MariaDBClient(args), args.rollback_state)
        mapping = load_mapping(args.map_file)
        if args.validate_map_only:
            output = {
                "valid": True,
                "policies": len(mapping.policies),
                "regions": len(mapping.regions),
                "flavors": sum(len(r.flavors) for r in mapping.regions.values()),
            }
            if args.format == "json":
                print(json.dumps(output, sort_keys=True))
            else:
                print(
                    f"valid mapping: {output['policies']} policies, "
                    f"{output['regions']} regions, {output['flavors']} flavors"
                )
            return EXIT_OK
        if args.region not in mapping.regions:
            raise MigrationError(
                f"unknown region {args.region!r}; choose from "
                + ", ".join(sorted(mapping.regions))
            )
        log(args, f"Connecting to OpenStack cloud {args.os_cloud}")
        conn = connect_openstack(args.os_cloud, args.api_timeout)
        require_admin_scope(conn)
        client = MariaDBClient(args)
        policy_plans = find_policies(conn, mapping)
        ids = policy_ids(policy_plans)
        flavor_plans = resolve_flavors(conn, mapping.regions[args.region], mapping, ids)
        instance_plans = plan_instances(client, args.nova_database, flavor_plans)
        port_plans = plan_ports(conn, instance_plans)
        plan = RunPlan(
            args.region,
            args.apply,
            policy_plans,
            flavor_plans,
            instance_plans,
            port_plans,
        )
        print_report(plan, args.format)
        if not args.apply:
            return EXIT_FINDINGS if plan.planned_count() else EXIT_OK

        state_path = args.state_dir / (
            datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
            + f"-{args.region}.json"
        )
        write_state(state_path, state_payload(plan, args.os_cloud, "preflight"))
        try:
            mutation_started = True
            create_missing_policies(conn, plan.policies)
            ids = policy_ids(plan.policies)
            plan.flavors = resolve_flavors(
                conn, mapping.regions[args.region], mapping, ids
            )
            plan.instances = plan_instances(client, args.nova_database, plan.flavors)
            plan.ports = plan_ports(conn, plan.instances)
            write_state(state_path, state_payload(plan, args.os_cloud, "applying"))
            apply_flavors(conn, plan.flavors)
            apply_instances(client, plan.instances)
            apply_ports(conn, plan.ports)
            # Re-run every verification path against live state.
            verified_policies = find_policies(conn, mapping)
            verified_flavors = resolve_flavors(
                conn,
                mapping.regions[args.region],
                mapping,
                policy_ids(verified_policies),
            )
            verified_instances = plan_instances(
                client, args.nova_database, verified_flavors
            )
            verified_ports = plan_ports(conn, verified_instances)
            if any(item.action != "noop" for item in verified_flavors):
                raise MigrationError(
                    "flavor verification still reports pending updates"
                )
            if any(item.action != "noop" for item in verified_instances):
                raise MigrationError(
                    "cached flavor verification still reports pending updates"
                )
            if any(item.action != "noop" for item in verified_ports):
                raise MigrationError("port verification still reports pending updates")
            write_state(state_path, state_payload(plan, args.os_cloud, "complete"))
            log(args, f"Migration state written to {state_path}")
            return EXIT_OK
        except Exception:
            write_state(state_path, state_payload(plan, args.os_cloud, "failed"))
            raise
    except MigrationError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return EXIT_APPLY_FAILED if mutation_started else EXIT_ERROR
    except KeyboardInterrupt:
        print("error: interrupted", file=sys.stderr)
        return EXIT_APPLY_FAILED if mutation_started else EXIT_ERROR
    except Exception as exc:
        print(f"error: unexpected failure: {exc}", file=sys.stderr)
        return EXIT_APPLY_FAILED if mutation_started else EXIT_ERROR
    finally:
        if tunnel is not None:
            tunnel.stop()


if __name__ == "__main__":
    sys.exit(main())
