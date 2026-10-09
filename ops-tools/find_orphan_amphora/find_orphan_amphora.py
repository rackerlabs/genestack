#!/usr/bin/env python3
"""Find Nova servers that appear to be orphaned Octavia amphorae."""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import shlex
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Iterable

EXIT_OK = 0
EXIT_ERROR = 1
EXIT_FINDINGS = 2
EXIT_REMEDIATION_FAILED = 3

UUID_RE = re.compile(
    r"^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$",
    re.IGNORECASE,
)

TSV_FIELDS = (
    "COMPUTE_ID",
    "NAME",
    "STATUS",
    "HOST",
    "CREATED",
    "MGMT_IP",
    "MAC",
    "PORT_ID",
    "PORT_NAME",
)


class OpsError(RuntimeError):
    """Runtime error that should be reported as a stable scanner failure."""


@dataclass
class CommandResult:
    args: list[str]
    stdout: str
    stderr: str
    returncode: int


@dataclass
class AuditPaths:
    root: Path
    servers: Path
    ports: Path
    octavia_ids: Path
    mgmt_server_ids: Path
    reported_ids: Path
    orphans_tsv: Path
    cleanup: Path
    report_json: Path


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


def valid_uuid(value: str) -> bool:
    return bool(UUID_RE.match(value or ""))


def log(args: argparse.Namespace, message: str) -> None:
    if not args.quiet:
        print(message, file=sys.stderr)


def openstack_command(args: argparse.Namespace, extra: list[str]) -> list[str]:
    command = split_command(args.openstack_command)
    if args.os_cloud:
        command.append(f"--os-cloud={args.os_cloud}")
    command.extend(extra)
    return command


def openstack(args: argparse.Namespace, extra: list[str]) -> str:
    return checked(run_command(openstack_command(args, extra), args.command_timeout))


def openstack_optional(
    args: argparse.Namespace,
    extra: list[str],
    *,
    warn: bool = False,
) -> str | None:
    result = run_command(openstack_command(args, extra), args.command_timeout)
    if result.returncode == 0:
        return result.stdout
    if warn:
        detail = result.stderr.strip() or f"exit {result.returncode}"
        log(args, f"WARNING: {' '.join(result.args)}: {detail}")
    return None


def load_json(stdout: str, source: str) -> Any:
    try:
        return json.loads(stdout)
    except json.JSONDecodeError as exc:
        raise OpsError(f"failed to parse JSON from {source}: {exc}") from exc


def json_rows(stdout: str, source: str) -> list[dict[str, Any]]:
    data = load_json(stdout, source)
    if not isinstance(data, list):
        raise OpsError(f"expected JSON list from {source}")
    return [row for row in data if isinstance(row, dict)]


def json_object(stdout: str, source: str) -> dict[str, Any]:
    data = load_json(stdout, source)
    if not isinstance(data, dict):
        raise OpsError(f"expected JSON object from {source}")
    return data


def get_value(row: dict[str, Any], *keys: str) -> Any:
    for key in keys:
        value = row.get(key)
        if value not in (None, ""):
            return value
    return ""


def string_value(row: dict[str, Any], *keys: str) -> str:
    value = get_value(row, *keys)
    if value in (None, ""):
        return ""
    return str(value).strip()


def normalize_fixed_ips(value: Any) -> str:
    if value in (None, ""):
        return ""
    if isinstance(value, list):
        addresses: list[str] = []
        for item in value:
            if isinstance(item, dict):
                address = item.get("ip_address") or item.get("ip")
                if address:
                    addresses.append(str(address))
            elif item not in (None, ""):
                addresses.append(str(item))
        return ",".join(addresses)
    return str(value)


def normalize_string_list(value: Any) -> list[str]:
    if value in (None, ""):
        return []
    if isinstance(value, list):
        return [str(item).strip() for item in value if str(item).strip()]
    if isinstance(value, tuple):
        return [str(item).strip() for item in value if str(item).strip()]
    if isinstance(value, str):
        text = value.strip()
        if not text:
            return []
        if text.startswith("["):
            try:
                parsed = json.loads(text.replace("'", '"'))
            except json.JSONDecodeError:
                parsed = None
            if isinstance(parsed, list):
                return [str(item).strip() for item in parsed if str(item).strip()]
        return [item.strip() for item in text.split(",") if item.strip()]
    return [str(value).strip()]


def prepare_audit_paths(output_dir: str | None) -> AuditPaths:
    if output_dir:
        root = Path(output_dir)
    else:
        timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        root = Path(f"/tmp/octavia-orphan-audit-{timestamp}")

    servers = root / "servers"
    ports = root / "ports"
    servers.mkdir(parents=True, exist_ok=True)
    ports.mkdir(parents=True, exist_ok=True)

    return AuditPaths(
        root=root,
        servers=servers,
        ports=ports,
        octavia_ids=root / "octavia-compute-ids.txt",
        mgmt_server_ids=root / "mgmt-server-ids.txt",
        reported_ids=root / "reported-ids.txt",
        orphans_tsv=root / "orphans.tsv",
        cleanup=root / "cleanup.sh",
        report_json=root / "report.json",
    )


def write_lines(path: Path, values: Iterable[str]) -> None:
    items = sorted({value for value in values if value})
    content = "".join(f"{item}\n" for item in items)
    path.write_text(content, encoding="utf-8")


def write_tsv(path: Path, candidates: list[dict[str, Any]]) -> None:
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow(TSV_FIELDS)
        for item in candidates:
            writer.writerow(
                [
                    item["compute_id"],
                    item["name"],
                    item["status"],
                    item["host"],
                    item["created"],
                    item["management_ip"],
                    item["mac_address"],
                    item["port_id"],
                    item["port_name"],
                ]
            )


def cleanup_cli(args: argparse.Namespace) -> str:
    command = split_command(args.openstack_command)
    if args.os_cloud:
        command.append(f"--os-cloud={args.os_cloud}")
    return shlex.join(command)


def write_cleanup(
    path: Path,
    args: argparse.Namespace,
    candidates: list[dict[str, Any]],
) -> None:
    cli = cleanup_cli(args)
    lines = [
        "#!/usr/bin/env bash",
        "",
        "# Octavia orphan cleanup commands",
        "#",
        "# REVIEW EVERY ENTRY BEFORE RUNNING.",
        "# Nothing below is enabled automatically.",
        "# Re-run the scanner immediately before deleting any server.",
        "",
    ]

    for item in candidates:
        lines.extend(
            [
                "########################################################################",
                f"# Candidate: {item['compute_id']}",
                f"# Name: {item['name']}",
                f"# Host: {item['host']}",
                f"# Mgmt IP: {item['management_ip']}",
                f"# Port: {item['port_id']}",
                f"# Source: {item['source']}",
                f"# Automatic fix eligible: {'yes' if item['fixable'] else 'no'}",
                "#",
                "# Verify Octavia does NOT reference this compute_id:",
                f"# {cli} loadbalancer amphora list --long -f json",
                f"# Expected absent compute_id: {item['compute_id']}",
                "#",
                "# Delete the Nova server only after verification:",
                f"# {cli} server delete {shlex.quote(item['compute_id'])}",
                "########################################################################",
                "",
            ]
        )

    path.write_text("\n".join(lines), encoding="utf-8")
    path.chmod(0o755)


def octavia_compute_ids(args: argparse.Namespace) -> set[str]:
    rows = json_rows(
        openstack(
            args,
            ["loadbalancer", "amphora", "list", "--long", "-f", "json"],
        ),
        "openstack loadbalancer amphora list",
    )
    values = {
        string_value(row, "compute_id", "Compute ID").lower()
        for row in rows
        if string_value(row, "compute_id", "Compute ID")
    }
    return values


def management_network_id(args: argparse.Namespace) -> str:
    row = json_object(
        openstack(
            args,
            ["network", "show", args.management_network, "-f", "json"],
        ),
        "openstack network show",
    )
    network_id = string_value(row, "id", "ID")
    if not network_id:
        raise OpsError(
            f"management network {args.management_network!r} returned no network ID"
        )
    return network_id.lower()


def port_json(
    args: argparse.Namespace,
    port_id: str,
    *,
    warn: bool = False,
) -> dict[str, Any] | None:
    stdout = openstack_optional(
        args,
        ["port", "show", port_id, "-f", "json"],
        warn=warn,
    )
    if stdout is None:
        return None
    return json_object(stdout, f"openstack port show {port_id}")


def server_json(
    args: argparse.Namespace,
    server_id: str,
    *,
    warn: bool = False,
) -> dict[str, Any] | None:
    stdout = openstack_optional(
        args,
        ["server", "show", server_id, "-f", "json"],
        warn=warn,
    )
    if stdout is None:
        return None
    return json_object(stdout, f"openstack server show {server_id}")


def save_yaml_artifact(
    args: argparse.Namespace,
    resource: str,
    resource_id: str,
    path: Path,
) -> None:
    stdout = openstack(args, [resource, "show", resource_id, "-f", "yaml"])
    path.write_text(stdout, encoding="utf-8")


def candidate_from_rows(
    compute_id: str,
    source: str,
    server: dict[str, Any],
    port_id: str,
    port: dict[str, Any] | None,
    mgmt_network_id: str,
) -> dict[str, Any]:
    port_network_id = (
        string_value(port, "network_id", "Network ID").lower() if port else ""
    )
    fixed_ips = get_value(port, "fixed_ips", "Fixed IP Addresses") if port else ""
    return {
        "compute_id": compute_id.lower(),
        "name": string_value(server, "name", "Name"),
        "status": string_value(server, "status", "Status"),
        "host": string_value(server, "OS-EXT-SRV-ATTR:host", "host", "Host"),
        "created": string_value(server, "created", "Created"),
        "management_ip": normalize_fixed_ips(fixed_ips),
        "mac_address": string_value(port, "mac_address", "MAC Address") if port else "",
        "port_id": port_id.lower() if port_id else "",
        "port_name": string_value(port, "name", "Name") if port else "",
        "port_network_id": port_network_id,
        "source": source,
        "fixable": bool(port_id and port and port_network_id == mgmt_network_id),
    }


def record_candidate(
    args: argparse.Namespace,
    paths: AuditPaths,
    candidates: dict[str, dict[str, Any]],
    compute_id: str,
    port_id: str,
    source: str,
    mgmt_network_id: str,
    *,
    preloaded_server: dict[str, Any] | None = None,
    preloaded_port: dict[str, Any] | None = None,
) -> None:
    compute_id = compute_id.lower()
    if compute_id in candidates:
        return

    server = preloaded_server or server_json(args, compute_id, warn=True)
    if server is None:
        log(args, f"WARNING: Nova server disappeared before inspection: {compute_id}")
        return

    save_yaml_artifact(
        args,
        "server",
        compute_id,
        paths.servers / f"{compute_id}.yaml",
    )

    port = preloaded_port
    if port_id and port is None:
        port = port_json(args, port_id, warn=True)
    if port_id and port is not None:
        save_yaml_artifact(
            args,
            "port",
            port_id,
            paths.ports / f"{port_id}.yaml",
        )

    candidates[compute_id] = candidate_from_rows(
        compute_id,
        source,
        server,
        port_id,
        port,
        mgmt_network_id,
    )


def management_port_ids(args: argparse.Namespace) -> list[str]:
    rows = json_rows(
        openstack(
            args,
            [
                "port",
                "list",
                "--network",
                args.management_network,
                "-f",
                "json",
                "-c",
                "ID",
            ],
        ),
        "openstack port list --network",
    )
    return [
        string_value(row, "ID", "id").lower()
        for row in rows
        if string_value(row, "ID", "id")
    ]


def aggregate_hosts(args: argparse.Namespace) -> list[str]:
    row = json_object(
        openstack(args, ["aggregate", "show", args.aggregate, "-f", "json"]),
        "openstack aggregate show",
    )
    return normalize_string_list(get_value(row, "hosts", "Hosts"))


def servers_on_host(args: argparse.Namespace, host: str) -> list[str]:
    rows = json_rows(
        openstack(
            args,
            [
                "server",
                "list",
                "--all-projects",
                "--host",
                host,
                "-f",
                "json",
                "-c",
                "ID",
            ],
        ),
        f"openstack server list --host {host}",
    )
    return [
        string_value(row, "ID", "id").lower()
        for row in rows
        if string_value(row, "ID", "id")
    ]


def server_port_ids(args: argparse.Namespace, server_id: str) -> list[str]:
    rows = json_rows(
        openstack(
            args,
            [
                "port",
                "list",
                "--device-id",
                server_id,
                "-f",
                "json",
                "-c",
                "ID",
            ],
        ),
        f"openstack port list --device-id {server_id}",
    )
    return [
        string_value(row, "ID", "id").lower()
        for row in rows
        if string_value(row, "ID", "id")
    ]


def find_management_port(
    args: argparse.Namespace,
    server_id: str,
    mgmt_network_id: str,
) -> tuple[str, dict[str, Any] | None]:
    for port_id in server_port_ids(args, server_id):
        port = port_json(args, port_id)
        if port is None:
            continue
        network_id = string_value(port, "network_id", "Network ID").lower()
        if network_id == mgmt_network_id:
            return port_id, port
    return "", None


def scan(args: argparse.Namespace, paths: AuditPaths) -> dict[str, Any]:
    log(args, "Collecting current Octavia amphora records...")
    octavia_ids = octavia_compute_ids(args)
    log(args, f"Current Octavia compute IDs: {len(octavia_ids)}")

    mgmt_network_id = management_network_id(args)
    mgmt_server_ids: set[str] = set()
    candidates: dict[str, dict[str, Any]] = {}

    log(args, f"Scanning Neutron management network: {args.management_network}")
    for port_id in management_port_ids(args):
        port = port_json(args, port_id)
        if port is None:
            continue
        device_id = string_value(port, "device_id", "Device ID").lower()
        if not device_id:
            continue

        # Health-manager/worker/controller plumbing can have device IDs that are
        # not Nova servers. A successful server show proves this is a VM.
        server = server_json(args, device_id)
        if server is None:
            continue

        mgmt_server_ids.add(device_id)
        if device_id in octavia_ids:
            continue

        record_candidate(
            args,
            paths,
            candidates,
            device_id,
            port_id,
            f"management-network:{args.management_network}",
            mgmt_network_id,
            preloaded_server=server,
            preloaded_port=port,
        )

    aggregate_server_count = 0
    if args.aggregate:
        log(args, f"Scanning dedicated aggregate: {args.aggregate}")
        for host in aggregate_hosts(args):
            log(args, f"  Host: {host}")
            for server_id in servers_on_host(args, host):
                aggregate_server_count += 1
                if server_id in octavia_ids or server_id in candidates:
                    continue
                port_id, port = find_management_port(
                    args,
                    server_id,
                    mgmt_network_id,
                )
                record_candidate(
                    args,
                    paths,
                    candidates,
                    server_id,
                    port_id,
                    f"aggregate:{args.aggregate}",
                    mgmt_network_id,
                    preloaded_port=port,
                )

    candidate_list = [candidates[key] for key in sorted(candidates)]
    manual_review_count = sum(1 for item in candidate_list if not item["fixable"])

    write_lines(paths.octavia_ids, octavia_ids)
    write_lines(paths.mgmt_server_ids, mgmt_server_ids)
    write_lines(paths.reported_ids, candidates.keys())
    write_tsv(paths.orphans_tsv, candidate_list)
    write_cleanup(paths.cleanup, args, candidate_list)

    return {
        "tool": "find_orphan_amphora",
        "fix": bool(args.fix),
        "summary": {
            "actionable_findings": len(candidate_list),
            "remediation_attempted": 0,
            "remediation_succeeded": 0,
            "remediation_failed": 0,
            "octavia_compute_id_count": len(octavia_ids),
            "management_server_count": len(mgmt_server_ids),
            "aggregate_server_count": aggregate_server_count,
            "orphan_candidate_count": len(candidate_list),
            "manual_review_count": manual_review_count,
            "management_network": args.management_network,
            "management_network_id": mgmt_network_id,
            "aggregate": args.aggregate or "",
            "os_cloud": args.os_cloud or "",
        },
        "candidates": candidate_list,
        "remediation": [],
        "artifacts": {
            "audit_directory": str(paths.root),
            "octavia_compute_ids": str(paths.octavia_ids),
            "management_server_ids": str(paths.mgmt_server_ids),
            "reported_ids": str(paths.reported_ids),
            "candidate_report": str(paths.orphans_tsv),
            "cleanup_commands": str(paths.cleanup),
            "json_report": str(paths.report_json),
            "server_details_directory": str(paths.servers),
            "port_details_directory": str(paths.ports),
        },
    }


def validate_fix_args(args: argparse.Namespace) -> None:
    if args.fix and not args.yes_im_really_sure:
        raise OpsError("--fix requires --yes-im-really-sure")


def mark_remediation_failure(
    report: dict[str, Any],
    compute_id: str,
    error: str,
) -> None:
    report["summary"]["remediation_attempted"] += 1
    report["summary"]["remediation_failed"] += 1
    report["remediation"].append(
        {
            "resource_type": "server",
            "resource_id": compute_id,
            "succeeded": False,
            "error": error,
        }
    )


def delete_candidate(
    args: argparse.Namespace,
    report: dict[str, Any],
    candidate: dict[str, Any],
) -> None:
    compute_id = candidate["compute_id"]
    port_id = candidate["port_id"]
    mgmt_network_id = report["summary"]["management_network_id"]

    if not valid_uuid(compute_id):
        mark_remediation_failure(report, compute_id, "invalid Nova server UUID")
        return

    # Re-read Octavia immediately before deletion to avoid deleting an amphora
    # that became referenced after the initial scan.
    if compute_id in octavia_compute_ids(args):
        mark_remediation_failure(
            report,
            compute_id,
            "server is now referenced by Octavia; refusing deletion",
        )
        return

    # Only automatically delete candidates that still own a port on the
    # configured management network. Aggregate-only candidates without this
    # evidence remain manual-review findings.
    port = port_json(args, port_id, warn=True) if port_id else None
    if port is None:
        mark_remediation_failure(
            report,
            compute_id,
            "management port is missing; refusing automatic deletion",
        )
        return

    device_id = string_value(port, "device_id", "Device ID").lower()
    network_id = string_value(port, "network_id", "Network ID").lower()
    if device_id != compute_id or network_id != mgmt_network_id:
        mark_remediation_failure(
            report,
            compute_id,
            "management port no longer matches the candidate; refusing deletion",
        )
        return

    report["summary"]["remediation_attempted"] += 1
    item = {
        "resource_type": "server",
        "resource_id": compute_id,
        "succeeded": False,
        "error": "",
    }
    try:
        openstack(args, ["server", "delete", compute_id])
    except OpsError as exc:
        item["error"] = str(exc)
        report["summary"]["remediation_failed"] += 1
    else:
        item["succeeded"] = True
        report["summary"]["remediation_succeeded"] += 1
    report["remediation"].append(item)


def remediate(args: argparse.Namespace, report: dict[str, Any]) -> None:
    manual_review = 0
    for candidate in report["candidates"]:
        if not candidate["fixable"]:
            manual_review += 1
            continue
        delete_candidate(args, report, candidate)

    report["summary"]["manual_review_count"] = manual_review
    report["summary"]["actionable_findings"] = manual_review


def render_section(title: str, lines: Iterable[str]) -> None:
    print(title)
    print("-" * len(title))
    for line in lines:
        print(line)
    print()


def render_text(report: dict[str, Any]) -> None:
    summary = report["summary"]
    print("=== find_orphan_amphora ===")
    print(f"Fix mode: {'ON' if report['fix'] else 'OFF (read-only)'}")
    print(f"Actionable findings: {summary['actionable_findings']}")
    print()

    render_section(
        "Summary",
        [
            f"Octavia compute IDs: {summary['octavia_compute_id_count']}",
            f"Nova servers via {summary['management_network']}: {summary['management_server_count']}",
            f"Nova servers scanned via aggregate: {summary['aggregate_server_count']}",
            f"Orphan candidates: {summary['orphan_candidate_count']}",
            f"Manual-review candidates: {summary['manual_review_count']}",
            f"Audit directory: {report['artifacts']['audit_directory']}",
            f"Candidate report: {report['artifacts']['candidate_report']}",
            f"Cleanup commands: {report['artifacts']['cleanup_commands']}",
        ],
    )

    candidate_lines = []
    for item in report["candidates"]:
        state = "FIXABLE" if item["fixable"] else "REVIEW"
        candidate_lines.append(
            f"{state}: {item['compute_id']} name={item['name'] or '-'} "
            f"status={item['status'] or '-'} host={item['host'] or '-'} "
            f"mgmt_ip={item['management_ip'] or '-'} port={item['port_id'] or '-'} "
            f"source={item['source']}"
        )
    render_section(
        "Orphan Amphora Candidates",
        candidate_lines or ["OK: no findings"],
    )

    if report["remediation"]:
        render_section(
            "Remediation",
            [
                f"server {item['resource_id']}: "
                f"{'OK' if item['succeeded'] else 'FAILED'}"
                + (f" ({item['error']})" if item["error"] else "")
                for item in report["remediation"]
            ],
        )


def finish_report(args: argparse.Namespace, report: dict[str, Any]) -> int:
    if args.format == "json":
        print(json.dumps(report, indent=2, sort_keys=True))
    else:
        render_text(report)

    summary = report["summary"]
    if summary["remediation_failed"]:
        return EXIT_REMEDIATION_FAILED
    if summary["actionable_findings"]:
        return EXIT_FINDINGS
    return EXIT_OK


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Find Nova servers that look like orphaned Octavia amphorae by "
            "comparing Octavia inventory with the load-balancer management "
            "network and, optionally, a dedicated compute aggregate."
        )
    )
    parser.add_argument("--format", choices=("text", "json"), default="text")
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="suppress progress logs on stderr",
    )
    parser.add_argument(
        "--command-timeout",
        type=int,
        default=60,
        help="timeout in seconds for each external command",
    )
    parser.add_argument(
        "--openstack-command",
        default="openstack",
        help="OpenStack CLI command; may include fixed wrapper arguments",
    )
    parser.add_argument(
        "--os-cloud",
        default=os.environ.get("OS_CLOUD", "Default"),
        help="cloud from clouds.yaml (default: OS_CLOUD or Default)",
    )
    parser.add_argument(
        "--management-network",
        default=os.environ.get("MGMT_NET", "lb-mgmt-net"),
        help="Octavia management network name or ID",
    )
    parser.add_argument(
        "--aggregate",
        default=os.environ.get("AGGREGATE", ""),
        help="optional dedicated Amphora compute aggregate to scan",
    )
    parser.add_argument(
        "--output-dir",
        default=os.environ.get("OUTPUT_DIR") or None,
        help="audit output directory (default: timestamped directory under /tmp)",
    )
    parser.add_argument(
        "--scan",
        action="store_true",
        help="compatibility no-op; scanning is the default",
    )
    parser.add_argument(
        "--fix",
        action="store_true",
        help="delete confirmed orphan Nova servers that still own a management-network port",
    )
    parser.add_argument(
        "--yes-im-really-sure",
        action="store_true",
        help="required with --fix to confirm destructive remediation",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    try:
        validate_fix_args(args)
        paths = prepare_audit_paths(args.output_dir)
        report = scan(args, paths)
        if args.fix:
            remediate(args, report)
        paths.report_json.write_text(
            json.dumps(report, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        return finish_report(args, report)
    except OpsError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return EXIT_ERROR


if __name__ == "__main__":
    raise SystemExit(main())
