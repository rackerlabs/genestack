#!/usr/bin/env python3
"""Shared implementation for OVN/Neutron consistency ops tools."""

from __future__ import annotations

import argparse
import csv
import ipaddress
import json
import re
import shlex
import subprocess
import sys
from dataclasses import dataclass
from typing import Any, Iterable

EXIT_OK = 0
EXIT_ERROR = 1
EXIT_FINDINGS = 2
EXIT_REMEDIATION_FAILED = 3

UUID_RE = re.compile(
    r"^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$",
    re.IGNORECASE,
)
UUID_SEARCH_RE = re.compile(
    r"([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})",
    re.IGNORECASE,
)
NEUTRON_RESOURCE_RE = re.compile(
    r"^neutron-([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})$",
    re.IGNORECASE,
)
NEUTRON_LRP_RE = re.compile(
    r"^lrp-([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})$",
    re.IGNORECASE,
)


class OpsError(RuntimeError):
    """Runtime error that should be reported as a stable scanner failure."""


@dataclass
class CommandResult:
    args: list[str]
    stdout: str
    stderr: str
    returncode: int


def run_command(args: list[str], timeout: int) -> CommandResult:
    try:
        completed = subprocess.run(
            args,
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except FileNotFoundError as exc:
        raise OpsError(f"command not found: {args[0]}") from exc
    except subprocess.TimeoutExpired as exc:
        raise OpsError(f"command timed out after {timeout}s: {' '.join(args)}") from exc

    return CommandResult(
        args=args,
        stdout=completed.stdout,
        stderr=completed.stderr,
        returncode=completed.returncode,
    )


def checked(result: CommandResult) -> str:
    if result.returncode != 0:
        stderr = result.stderr.strip()
        detail = f": {stderr}" if stderr else ""
        raise OpsError(
            f"command failed ({result.returncode}): {' '.join(result.args)}{detail}"
        )
    return result.stdout


def split_command(command: str) -> list[str]:
    parts = shlex.split(command)
    if not parts:
        raise OpsError("command override cannot be empty")
    return parts


def emit_json(report: dict[str, Any]) -> None:
    print(json.dumps(report, indent=2, sort_keys=True))


def log(args: argparse.Namespace, message: str) -> None:
    if not getattr(args, "quiet", False):
        print(message, file=sys.stderr)


def add_common_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--format", choices=("text", "json"), default="text")
    parser.add_argument(
        "--quiet", action="store_true", help="suppress progress logs on stderr"
    )
    parser.add_argument(
        "--command-timeout",
        type=int,
        default=60,
        help="timeout in seconds for each external command",
    )


def add_kubectl_arg(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--kubectl-command", default="kubectl")


def add_openstack_arg(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--openstack-command", default="openstack")


def add_nbctl_arg(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--nbctl-command",
        default="kubectl ko nbctl",
        help="command used to run ovn-nbctl against the northbound DB",
    )


def add_fix_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--scan", action="store_true", help="compatibility no-op; scan is the default"
    )
    parser.add_argument("--fix", action="store_true", help="delete stale resources")
    parser.add_argument(
        "--yes-im-really-sure",
        action="store_true",
        help="required with --fix to confirm destructive remediation",
    )


def validate_fix_args(args: argparse.Namespace) -> None:
    if args.fix and not args.yes_im_really_sure:
        raise OpsError("--fix requires --yes-im-really-sure")


def kubectl(args: argparse.Namespace, extra: list[str]) -> str:
    return checked(
        run_command(split_command(args.kubectl_command) + extra, args.command_timeout)
    )


def openstack(args: argparse.Namespace, extra: list[str]) -> str:
    return checked(
        run_command(split_command(args.openstack_command) + extra, args.command_timeout)
    )


def nbctl(args: argparse.Namespace, extra: list[str]) -> str:
    return checked(
        run_command(split_command(args.nbctl_command) + extra, args.command_timeout)
    )


def ensure_nbctl(args: argparse.Namespace) -> None:
    nbctl(args, ["show"])


def load_json(stdout: str, source: str) -> Any:
    try:
        return json.loads(stdout)
    except json.JSONDecodeError as exc:
        raise OpsError(f"failed to parse JSON from {source}: {exc}") from exc


def parse_csv_rows(stdout: str) -> list[list[str]]:
    rows: list[list[str]] = []
    for row in csv.reader(stdout.splitlines()):
        if row:
            rows.append([field.strip().strip('"') for field in row])
    return rows


def valid_uuid(value: str) -> bool:
    return bool(UUID_RE.match(value or ""))


def extract_uuid(value: str) -> str | None:
    match = UUID_SEARCH_RE.search(value or "")
    return match.group(1).lower() if match else None


def extract_neutron_resource_uuid(value: str) -> str | None:
    match = NEUTRON_RESOURCE_RE.match(value or "")
    return match.group(1).lower() if match else None


def extract_neutron_lrp_uuid(value: str) -> str | None:
    match = NEUTRON_LRP_RE.match(value or "")
    return match.group(1).lower() if match else None


def valid_ipv4(value: str) -> bool:
    try:
        ipaddress.IPv4Address(value)
    except ValueError:
        return False
    return True


def render_section(title: str, lines: Iterable[str]) -> None:
    print(title)
    print("-" * len(title))
    for line in lines:
        print(line)
    print()


def finish_report(args: argparse.Namespace, report: dict[str, Any]) -> int:
    if args.format == "json":
        emit_json(report)
    else:
        render_text(report)

    summary = report["summary"]
    if summary.get("remediation_failed", 0):
        return EXIT_REMEDIATION_FAILED
    if summary.get("actionable_findings", 0):
        return EXIT_FINDINGS
    return EXIT_OK


def render_text(report: dict[str, Any]) -> None:
    tool = report["tool"]
    summary = report["summary"]
    print(f"=== {tool} ===")
    print(f"Fix mode: {'ON' if report.get('fix') else 'OFF (read-only)'}")
    print(f"Actionable findings: {summary.get('actionable_findings', 0)}")
    print()

    for section in report.get("sections", []):
        lines = section.get("lines", [])
        if not lines:
            lines = ["OK: no findings"]
        render_section(section["title"], lines)

    actions = report.get("remediation", [])
    if actions:
        render_section(
            "Remediation",
            [
                f"{item['resource_type']} {item['resource_id']}: "
                f"{'OK' if item.get('succeeded') else 'FAILED'}"
                + (f" ({item['error']})" if item.get("error") else "")
                for item in actions
            ],
        )


def build_report(tool: str, args: argparse.Namespace) -> dict[str, Any]:
    return {
        "tool": tool,
        "fix": bool(getattr(args, "fix", False)),
        "summary": {
            "actionable_findings": 0,
            "remediation_attempted": 0,
            "remediation_succeeded": 0,
            "remediation_failed": 0,
        },
        "sections": [],
        "remediation": [],
    }


def add_section(report: dict[str, Any], title: str, lines: list[str]) -> None:
    report["sections"].append({"title": title, "lines": lines})


def mark_findings(report: dict[str, Any], count: int) -> None:
    report["summary"]["actionable_findings"] += count


def destroy_ovn_resource(
    args: argparse.Namespace,
    report: dict[str, Any],
    resource_type: str,
    resource_id: str,
) -> None:
    report["summary"]["remediation_attempted"] += 1
    item = {
        "resource_type": resource_type,
        "resource_id": resource_id,
        "succeeded": False,
        "error": "",
    }
    if not valid_uuid(resource_id):
        item["error"] = "invalid UUID"
        report["summary"]["remediation_failed"] += 1
        report["remediation"].append(item)
        return

    try:
        nbctl(args, ["destroy", resource_type, resource_id])
    except OpsError as exc:
        item["error"] = str(exc)
        report["summary"]["remediation_failed"] += 1
    else:
        item["succeeded"] = True
        report["summary"]["remediation_succeeded"] += 1
    report["remediation"].append(item)


def delete_ip_crd(
    args: argparse.Namespace,
    report: dict[str, Any],
    name: str,
    namespace: str,
) -> None:
    report["summary"]["remediation_attempted"] += 1
    item = {
        "resource_type": "ip",
        "resource_id": f"{namespace}/{name}",
        "succeeded": False,
        "error": "",
    }
    if not name or not namespace:
        item["error"] = "missing IP CRD name or namespace"
        report["summary"]["remediation_failed"] += 1
        report["remediation"].append(item)
        return

    try:
        kubectl(args, ["delete", args.ip_crd_kind, name, "-n", namespace])
    except OpsError as exc:
        item["error"] = str(exc)
        report["summary"]["remediation_failed"] += 1
    else:
        item["succeeded"] = True
        report["summary"]["remediation_succeeded"] += 1
    report["remediation"].append(item)


def get_kube_json(
    args: argparse.Namespace, extra: list[str], source: str
) -> dict[str, Any]:
    return load_json(kubectl(args, extra), source)


def pod_set(args: argparse.Namespace) -> set[tuple[str, str]]:
    pods = get_kube_json(args, ["get", "pods", "-A", "-o", "json"], "kubectl get pods")
    return {
        (
            item.get("metadata", {}).get("namespace", ""),
            item.get("metadata", {}).get("name", ""),
        )
        for item in pods.get("items", [])
    }


def ip_crd_records(args: argparse.Namespace, extra: list[str]) -> list[dict[str, Any]]:
    data = get_kube_json(
        args, ["get", args.ip_crd_kind, *extra, "-o", "json"], "kubectl get ip"
    )
    return data.get("items", [])


def normalize_openstack_rows(stdout: str, source: str) -> list[dict[str, Any]]:
    data = load_json(stdout, source)
    if not isinstance(data, list):
        raise OpsError(f"expected JSON list from {source}")
    return [row for row in data if isinstance(row, dict)]


def neutron_fips(args: argparse.Namespace) -> dict[str, str]:
    rows = normalize_openstack_rows(
        openstack(
            args,
            [
                "floating",
                "ip",
                "list",
                "-f",
                "json",
                "-c",
                "ID",
                "-c",
                "Floating IP Address",
                "-c",
                "Fixed IP Address",
            ],
        ),
        "openstack floating ip list",
    )
    fips: dict[str, str] = {}
    for row in rows:
        floating_ip = str(row.get("Floating IP Address") or "").strip()
        fixed_ip = row.get("Fixed IP Address")
        fip_id = str(row.get("ID") or "").strip()
        if fip_id and floating_ip and fixed_ip not in (None, "", "None"):
            fips[floating_ip] = fip_id
    return fips


def neutron_ids(args: argparse.Namespace, command: list[str], source: str) -> set[str]:
    rows = normalize_openstack_rows(openstack(args, command), source)
    ids = {str(row.get("ID") or "").strip().lower() for row in rows}
    return {item for item in ids if valid_uuid(item)}


def neutron_port_ids(
    args: argparse.Namespace, device_owners: set[str] | None = None
) -> set[str]:
    rows = normalize_openstack_rows(
        openstack(
            args,
            ["port", "list", "--long", "-f", "json", "-c", "ID", "-c", "device_owner"],
        ),
        "openstack port list",
    )
    ids: set[str] = set()
    for row in rows:
        port_id = str(row.get("ID") or "").strip().lower()
        owner = str(row.get("device_owner") or row.get("Device Owner") or "").strip()
        if not valid_uuid(port_id):
            continue
        if device_owners is None:
            if owner != "network:floatingip":
                ids.add(port_id)
        elif owner in device_owners:
            ids.add(port_id)
    return ids


def ovn_uuid_map(
    args: argparse.Namespace, table: str, columns: list[str]
) -> list[list[str]]:
    return parse_csv_rows(
        nbctl(
            args,
            ["--columns=" + ",".join(columns), "--bare", "--format=csv", "find", table],
        )
    )


def ovn_nat_map(args: argparse.Namespace) -> dict[str, str]:
    items: dict[str, str] = {}
    for row in ovn_uuid_map(
        args, "NAT", ["_uuid", "type", "external_ip", "external_ids"]
    ):
        if len(row) >= 3 and row[1] == "dnat_and_snat" and valid_ipv4(row[2]):
            items[row[2]] = row[0]
    return items


def ovn_lsp_map(args: argparse.Namespace) -> dict[str, str]:
    items: dict[str, str] = {}
    for row in ovn_uuid_map(args, "Logical_Switch_Port", ["_uuid", "name"]):
        if len(row) >= 2 and valid_uuid(row[1].lower()):
            items[row[1].lower()] = row[0]
    return items


def ovn_lr_map(args: argparse.Namespace) -> dict[str, str]:
    items: dict[str, str] = {}
    for row in ovn_uuid_map(args, "Logical_Router", ["_uuid", "name"]):
        if len(row) >= 2:
            router_id = extract_neutron_resource_uuid(row[1])
            if router_id:
                items[router_id] = row[0]
    return items


def ovn_lrp_map(args: argparse.Namespace) -> dict[str, str]:
    items: dict[str, str] = {}
    for row in ovn_uuid_map(args, "Logical_Router_Port", ["_uuid", "name"]):
        if len(row) >= 2:
            port_id = extract_neutron_lrp_uuid(row[1])
            if port_id:
                items[port_id] = row[0]
    return items


def ovn_external_id_map(
    args: argparse.Namespace, table: str, key: str
) -> dict[str, str]:
    items: dict[str, str] = {}
    pattern = re.compile(re.escape(key) + r"=([a-f0-9-]+)", re.IGNORECASE)
    for row in ovn_uuid_map(args, table, ["_uuid", "external_ids"]):
        if len(row) >= 2:
            match = pattern.search(row[1])
            if match and valid_uuid(match.group(1)):
                items[match.group(1).lower()] = row[0]
    return items


def compare_sets(
    expected: dict[str, str] | set[str],
    actual: dict[str, str],
) -> tuple[list[tuple[str, str | None]], list[tuple[str, str]]]:
    expected_keys = (
        set(expected.keys()) if isinstance(expected, dict) else set(expected)
    )
    missing = [
        (item, expected[item] if isinstance(expected, dict) else None)
        for item in sorted(expected_keys - actual.keys())
    ]
    stale = [(item, actual[item]) for item in sorted(actual.keys() - expected_keys)]
    return missing, stale


def compare_report(
    args: argparse.Namespace,
    tool: str,
    expected_name: str,
    actual_name: str,
    expected: dict[str, str] | set[str],
    actual: dict[str, str],
    stale_resource_type: str,
) -> dict[str, Any]:
    report = build_report(tool, args)
    missing, stale = compare_sets(expected, actual)
    mark_findings(report, len(missing) + len(stale))

    add_section(
        report,
        f"Missing {actual_name}",
        [
            f"MISSING: {item}" + (f" ({value})" if value else "")
            for item, value in missing
        ],
    )
    add_section(
        report,
        f"Stale {actual_name}",
        [f"STALE: {item} (OVN UUID: {uuid})" for item, uuid in stale],
    )

    report["summary"].update(
        {
            "expected_count": len(expected),
            "actual_count": len(actual),
            "missing_count": len(missing),
            "stale_count": len(stale),
            "expected_source": expected_name,
            "actual_source": actual_name,
        }
    )

    if args.fix:
        for _item, uuid in stale:
            destroy_ovn_resource(args, report, stale_resource_type, uuid)
        if missing:
            report["summary"]["actionable_findings"] = len(missing)
        elif report["summary"]["remediation_failed"] == 0:
            report["summary"]["actionable_findings"] = 0
    return report


def main_duplicate_ip(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Find duplicate Kube-OVN IP CRD addresses."
    )
    add_common_args(parser)
    add_kubectl_arg(parser)
    parser.add_argument("--ip-crd-kind", default="ip")
    args = parser.parse_args(argv)

    report = build_report("find_ovn_duplicate_ip", args)
    try:
        records = ip_crd_records(args, ["-A"])
        pods = pod_set(args)
        by_ip: dict[str, list[dict[str, str]]] = {}
        for item in records:
            metadata = item.get("metadata", {})
            spec = item.get("spec", {})
            ip_addr = str(spec.get("ipAddress") or "").strip()
            if not ip_addr:
                continue
            by_ip.setdefault(ip_addr, []).append(
                {
                    "ip_address": ip_addr,
                    "ip_crd_name": str(metadata.get("name") or ""),
                    "ip_crd_namespace": str(metadata.get("namespace") or ""),
                    "pod_namespace": str(
                        spec.get("namespace") or metadata.get("namespace") or ""
                    ),
                    "pod_name": str(spec.get("podName") or ""),
                }
            )

        lines: list[str] = []
        duplicate_count = 0
        missing_pod_count = 0
        for ip_addr, items in sorted(by_ip.items()):
            if len(items) < 2:
                continue
            duplicate_count += 1
            lines.append(f"DUPLICATE IP: {ip_addr}")
            for row in items:
                exists = (row["pod_namespace"], row["pod_name"]) in pods
                if not exists:
                    missing_pod_count += 1
                status = "active pod" if exists else "missing pod"
                lines.append(
                    f"  {status}: {row['ip_crd_namespace']}/{row['ip_crd_name']} "
                    f"pod={row['pod_namespace']}/{row['pod_name']}"
                )

        mark_findings(report, duplicate_count)
        report["summary"].update(
            {
                "ip_crd_count": len(records),
                "duplicate_ip_count": duplicate_count,
                "missing_pod_count": missing_pod_count,
            }
        )
        add_section(report, "Duplicate IP CRDs", lines)
        return finish_report(args, report)
    except OpsError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return EXIT_ERROR


def main_stale_ip_crd(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Find stale Kube-OVN IP CRDs whose pods no longer exist."
    )
    add_common_args(parser)
    add_kubectl_arg(parser)
    add_fix_args(parser)
    parser.add_argument("--ip-crd-kind", default="ip")
    parser.add_argument("--subnet", default="ovn-default")
    parser.add_argument(
        "--run", action="store_true", help="compatibility alias for --fix"
    )
    args = parser.parse_args(argv)
    if args.run:
        args.fix = True

    report = build_report("find_ovn_stale_ip_crd", args)
    try:
        validate_fix_args(args)
        records = ip_crd_records(
            args, ["-A", "-l", f"ovn.kubernetes.io/subnet={args.subnet}"]
        )
        pods = pod_set(args)
        stale: list[dict[str, str]] = []
        manual: list[dict[str, str]] = []

        for item in records:
            metadata = item.get("metadata", {})
            spec = item.get("spec", {})
            row = {
                "ip_crd_name": str(metadata.get("name") or ""),
                "ip_crd_namespace": str(metadata.get("namespace") or ""),
                "pod_namespace": str(spec.get("namespace") or ""),
                "pod_name": str(spec.get("podName") or ""),
            }
            if not row["pod_namespace"] or not row["pod_name"]:
                manual.append(row)
            elif (row["pod_namespace"], row["pod_name"]) not in pods:
                stale.append(row)

        mark_findings(report, len(stale) + len(manual))
        add_section(
            report,
            "Stale IP CRDs",
            [
                f"STALE: {row['ip_crd_namespace']}/{row['ip_crd_name']} "
                f"pod={row['pod_namespace']}/{row['pod_name']}"
                for row in stale
            ],
        )
        add_section(
            report,
            "Manual Review IP CRDs",
            [
                f"REVIEW: {row['ip_crd_namespace']}/{row['ip_crd_name']} has missing pod metadata"
                for row in manual
            ],
        )
        report["summary"].update(
            {
                "ip_crd_count": len(records),
                "stale_count": len(stale),
                "manual_review_count": len(manual),
                "subnet": args.subnet,
            }
        )

        if args.fix:
            for row in stale:
                delete_ip_crd(args, report, row["ip_crd_name"], row["ip_crd_namespace"])
            report["summary"]["actionable_findings"] = len(manual)
        return finish_report(args, report)
    except OpsError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return EXIT_ERROR


def main_fips(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Compare assigned Neutron floating IPs with OVN NAT rules."
    )
    add_common_args(parser)
    add_openstack_arg(parser)
    add_nbctl_arg(parser)
    add_fix_args(parser)
    args = parser.parse_args(argv)
    try:
        validate_fix_args(args)
        ensure_nbctl(args)
        report = compare_report(
            args,
            "ovn_compare_neutron_fips_with_ovn_nat",
            "assigned Neutron floating IPs",
            "OVN dnat_and_snat NAT rules",
            neutron_fips(args),
            ovn_nat_map(args),
            "NAT",
        )
        return finish_report(args, report)
    except OpsError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return EXIT_ERROR


def main_ports(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Compare Neutron ports with OVN logical switch ports."
    )
    add_common_args(parser)
    add_openstack_arg(parser)
    add_nbctl_arg(parser)
    add_fix_args(parser)
    args = parser.parse_args(argv)
    try:
        validate_fix_args(args)
        ensure_nbctl(args)
        report = compare_report(
            args,
            "ovn_compare_neutron_ports_with_ovn_ports",
            "Neutron ports excluding floating IP ports",
            "OVN logical switch ports",
            neutron_port_ids(args),
            ovn_lsp_map(args),
            "Logical_Switch_Port",
        )
        return finish_report(args, report)
    except OpsError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return EXIT_ERROR


def main_routers(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Compare Neutron routers/router ports with OVN logical routers/router ports."
    )
    add_common_args(parser)
    add_openstack_arg(parser)
    add_nbctl_arg(parser)
    add_fix_args(parser)
    args = parser.parse_args(argv)
    try:
        validate_fix_args(args)
        ensure_nbctl(args)
        report = build_report("ovn_compare_neutron_routers_with_logical_routers", args)
        routers_missing, routers_stale = compare_sets(
            neutron_ids(
                args,
                ["router", "list", "-f", "json", "-c", "ID"],
                "openstack router list",
            ),
            ovn_lr_map(args),
        )
        rport_missing, rport_stale = compare_sets(
            neutron_port_ids(
                args, {"network:router_interface", "network:router_gateway"}
            ),
            ovn_lrp_map(args),
        )
        mark_findings(
            report,
            len(routers_missing)
            + len(routers_stale)
            + len(rport_missing)
            + len(rport_stale),
        )
        add_section(
            report,
            "Missing OVN Logical Routers",
            [f"MISSING: {item}" for item, _ in routers_missing],
        )
        add_section(
            report,
            "Stale OVN Logical Routers",
            [f"STALE: {item} (OVN UUID: {uuid})" for item, uuid in routers_stale],
        )
        add_section(
            report,
            "Missing OVN Logical Router Ports",
            [f"MISSING: {item}" for item, _ in rport_missing],
        )
        add_section(
            report,
            "Stale OVN Logical Router Ports",
            [f"STALE: {item} (OVN UUID: {uuid})" for item, uuid in rport_stale],
        )
        report["summary"].update(
            {
                "missing_routers": len(routers_missing),
                "stale_routers": len(routers_stale),
                "missing_router_ports": len(rport_missing),
                "stale_router_ports": len(rport_stale),
            }
        )
        if args.fix:
            for _item, uuid in rport_stale:
                destroy_ovn_resource(args, report, "Logical_Router_Port", uuid)
            for _item, uuid in routers_stale:
                destroy_ovn_resource(args, report, "Logical_Router", uuid)
            report["summary"]["actionable_findings"] = len(routers_missing) + len(
                rport_missing
            )
        return finish_report(args, report)
    except OpsError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return EXIT_ERROR


def main_security_groups(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Compare Neutron security groups/rules with OVN port groups/ACLs."
    )
    add_common_args(parser)
    add_openstack_arg(parser)
    add_nbctl_arg(parser)
    add_fix_args(parser)
    args = parser.parse_args(argv)
    try:
        validate_fix_args(args)
        ensure_nbctl(args)
        report = build_report("ovn_compare_neutron_security_groups_with_acl", args)
        rules_missing, rules_stale = compare_sets(
            neutron_ids(
                args,
                ["security", "group", "rule", "list", "-f", "json", "-c", "ID"],
                "openstack security group rule list",
            ),
            ovn_external_id_map(args, "ACL", "neutron:security_group_rule_id"),
        )
        sg_missing, sg_stale = compare_sets(
            neutron_ids(
                args,
                ["security", "group", "list", "-f", "json", "-c", "ID"],
                "openstack security group list",
            ),
            ovn_external_id_map(args, "Port_Group", "neutron:security_group_id"),
        )
        mark_findings(
            report,
            len(rules_missing) + len(rules_stale) + len(sg_missing) + len(sg_stale),
        )
        add_section(
            report,
            "Missing OVN ACLs",
            [f"MISSING: {item}" for item, _ in rules_missing],
        )
        add_section(
            report,
            "Stale OVN ACLs",
            [f"STALE: {item} (OVN UUID: {uuid})" for item, uuid in rules_stale],
        )
        add_section(
            report,
            "Missing OVN Port Groups",
            [f"MISSING: {item}" for item, _ in sg_missing],
        )
        add_section(
            report,
            "Stale OVN Port Groups",
            [f"STALE: {item} (OVN UUID: {uuid})" for item, uuid in sg_stale],
        )
        report["summary"].update(
            {
                "missing_rules": len(rules_missing),
                "stale_rules": len(rules_stale),
                "missing_security_groups": len(sg_missing),
                "stale_security_groups": len(sg_stale),
            }
        )
        if args.fix:
            for _item, uuid in rules_stale:
                destroy_ovn_resource(args, report, "ACL", uuid)
            for _item, uuid in sg_stale:
                destroy_ovn_resource(args, report, "Port_Group", uuid)
            report["summary"]["actionable_findings"] = len(rules_missing) + len(
                sg_missing
            )
        return finish_report(args, report)
    except OpsError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return EXIT_ERROR
