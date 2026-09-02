#!/usr/bin/env python3
"""Audit Nova instance directories that are no longer active in Nova."""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone

EXIT_OK = 0
EXIT_ERROR = 1
EXIT_ORPHANS_FOUND = 2
EXIT_DELETE_FAILED = 3

UUID_RE = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
    re.IGNORECASE,
)


@dataclass
class CommandResult:
    returncode: int
    stdout: str
    stderr: str
    timed_out: bool = False


@dataclass
class InstanceDir:
    uuid: str
    path: str
    size_kb: int
    active_in_openstack: bool = False
    active_in_database: bool | None = None
    orphan: bool = False
    backup_path: str | None = None
    delete_attempted: bool = False
    delete_succeeded: bool | None = None
    error: str | None = None


@dataclass
class HostResult:
    host: str
    status: str
    instance_dirs: list[InstanceDir] = field(default_factory=list)
    orphan_count: int = 0
    deleted_count: int = 0
    error: str | None = None


@dataclass
class AuditResult:
    delete_orphans: bool
    backup: bool
    started_at: str
    duration_seconds: float
    hosts_scanned: int
    orphan_count: int
    deleted_count: int
    error_count: int
    delete_failed_count: int
    potential_savings_kb: int
    results: list[HostResult]


class AuditError(RuntimeError):
    pass


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def run(cmd: list[str], timeout: int, input_text: str | None = None) -> CommandResult:
    try:
        proc = subprocess.run(
            cmd,
            input=input_text,
            text=True,
            capture_output=True,
            timeout=timeout,
            check=False,
        )
        return CommandResult(proc.returncode, proc.stdout, proc.stderr)
    except subprocess.TimeoutExpired as exc:
        stdout = exc.stdout if isinstance(exc.stdout, str) else ""
        stderr = exc.stderr if isinstance(exc.stderr, str) else ""
        return CommandResult(
            124,
            stdout,
            stderr or f"command timed out after {timeout}s",
            True,
        )


def checked(result: CommandResult, action: str) -> CommandResult:
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip() or "no output"
        if result.timed_out:
            detail = detail or "command timed out"
        raise AuditError(f"{action} failed: {detail}")
    return result


def require_command(name: str) -> None:
    if not shutil.which(name):
        raise AuditError(f"required command '{name}' is not installed or not in PATH")


def log(message: str, *, quiet: bool) -> None:
    if not quiet:
        print(
            f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {message}",
            file=sys.stderr,
        )


def debug(message: str, args: argparse.Namespace) -> None:
    if args.debug:
        log(f"DEBUG: {message}", quiet=args.quiet)


def expand_ssh_options(options: list[str]) -> list[str]:
    expanded: list[str] = []
    for option in options:
        expanded.extend(shlex.split(option))
    return expanded


def ssh_command(args: argparse.Namespace, host: str, remote_command: str) -> list[str]:
    return [
        args.ssh_command,
        "-q",
        "-o",
        "BatchMode=yes",
        "-o",
        f"ConnectTimeout={args.ssh_connect_timeout}",
        *expand_ssh_options(args.ssh_option),
        host,
        remote_command,
    ]


def shell_join(parts: list[str]) -> str:
    return shlex.join(parts)


def sudo_prefix(args: argparse.Namespace) -> list[str]:
    return [] if args.no_sudo else ["sudo", "-n"]


def openstack_base(args: argparse.Namespace) -> list[str]:
    cmd = [args.openstack_command]
    if args.os_cloud:
        cmd.extend(["--os-cloud", args.os_cloud])
    return cmd


def kubectl_base(args: argparse.Namespace) -> list[str]:
    return [
        args.kubectl_command,
        f"--request-timeout={args.kubectl_request_timeout}",
        "-n",
        args.namespace,
    ]


def verify_openstack_credentials(args: argparse.Namespace) -> None:
    if args.skip_credential_check:
        return
    if args.os_cloud or os.environ.get("OS_AUTH_URL"):
        return
    if os.path.exists(os.path.expanduser("~/.config/openstack/clouds.yaml")):
        return
    if os.path.exists("/etc/openstack/clouds.yaml"):
        return
    raise AuditError(
        "no OpenStack credentials detected; set OS_AUTH_URL, clouds.yaml, or --os-cloud"
    )


def discover_hosts(args: argparse.Namespace) -> list[str]:
    if args.node:
        return [host.strip() for host in args.node if host.strip()]
    cmd = [
        *openstack_base(args),
        "compute",
        "service",
        "list",
        "--service",
        "nova-compute",
        "-c",
        "Host",
        "-f",
        "value",
    ]
    result = checked(run(cmd, args.command_timeout), "nova-compute host discovery")
    hosts = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    if not hosts:
        raise AuditError("no nova-compute hosts found")
    return hosts


def get_active_instance_uuids(args: argparse.Namespace, host: str) -> set[str]:
    cmd = [
        *openstack_base(args),
        "server",
        "list",
        "--all",
        "--host",
        host,
        "-c",
        "ID",
        "-f",
        "value",
    ]
    result = checked(
        run(cmd, args.command_timeout), f"active instance lookup for {host}"
    )
    return {
        line.strip().lower()
        for line in result.stdout.splitlines()
        if UUID_RE.match(line.strip())
    }


def get_database_password(args: argparse.Namespace) -> str:
    env_password = os.environ.get(args.mariadb_password_env)
    if env_password:
        return env_password

    cmd = [
        *kubectl_base(args),
        "get",
        "secret",
        args.mariadb_secret,
        "-o",
        "jsonpath={.data.root-password}",
    ]
    result = checked(run(cmd, args.command_timeout), "MariaDB password lookup")
    encoded = result.stdout.strip()
    try:
        return base64.b64decode(encoded).decode()
    except (
        Exception
    ) as exc:  # noqa: BLE001 - include decode failure detail for operators.
        raise AuditError(f"failed to decode MariaDB password secret: {exc}") from exc


def active_uuids_in_database(
    args: argparse.Namespace,
    db_password: str,
    uuids: set[str],
) -> set[str]:
    valid_uuids = sorted({uuid.lower() for uuid in uuids if UUID_RE.match(uuid)})
    if not valid_uuids:
        return set()

    values = ",".join(f"'{uuid}'" for uuid in valid_uuids)
    sql = f"SELECT uuid FROM instances WHERE deleted=0 AND uuid IN ({values});"
    cmd = [
        *kubectl_base(args),
        "exec",
        "-i",
        args.mariadb_pod,
        "--",
        "sh",
        "-c",
        (
            "IFS= read -r MYSQL_PWD; export MYSQL_PWD; "
            'exec mariadb -u "$1" -D "$2" -N -s -e "$3"'
        ),
        "mariadb-query",
        args.mariadb_user,
        args.nova_database,
        sql,
    ]
    result = checked(
        run(cmd, args.command_timeout, input_text=f"{db_password}\n"),
        "Nova instance database lookup",
    )
    return {
        line.strip().lower()
        for line in result.stdout.splitlines()
        if UUID_RE.match(line.strip())
    }


def parse_instance_dirs(output: str) -> list[InstanceDir]:
    dirs: list[InstanceDir] = []
    for line in output.splitlines():
        fields = line.strip().split(maxsplit=1)
        if len(fields) != 2:
            continue
        size_raw, path = fields
        uuid = path.rstrip("/").rsplit("/", 1)[-1].lower()
        if not UUID_RE.match(uuid):
            continue
        try:
            size_kb = int(size_raw)
        except ValueError:
            continue
        dirs.append(InstanceDir(uuid=uuid, path=path, size_kb=size_kb))
    return dirs


def list_instance_dirs(args: argparse.Namespace, host: str) -> list[InstanceDir]:
    uuid_pattern = r".*/[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$"
    remote = shell_join(
        [
            *sudo_prefix(args),
            "find",
            args.instances_path,
            "-maxdepth",
            "1",
            "-mindepth",
            "1",
            "-type",
            "d",
            "-regextype",
            "posix-extended",
            "-regex",
            uuid_pattern,
            "-exec",
            "du",
            "-sk",
            "{}",
            "+",
        ]
    )
    result = checked(
        run(
            ssh_command(args, host, f"{remote} 2>/dev/null"),
            args.command_timeout,
        ),
        f"instance directory scan for {host}",
    )
    return parse_instance_dirs(result.stdout)


def backup_instance_dir(args: argparse.Namespace, host: str, item: InstanceDir) -> str:
    backup_dir = f"{args.instances_path.rstrip('/')}/_orphaned_backups"
    backup_name = f"{item.uuid}_{datetime.now().strftime('%Y-%m-%d')}.tar.gz"
    backup_path = f"{backup_dir}/{backup_name}"
    remote = " && ".join(
        [
            shell_join([*sudo_prefix(args), "mkdir", "-p", backup_dir]),
            shell_join(
                [
                    *sudo_prefix(args),
                    "tar",
                    "-czf",
                    backup_path,
                    "-C",
                    args.instances_path.rstrip("/"),
                    item.uuid,
                ]
            ),
        ]
    )
    checked(
        run(ssh_command(args, host, remote), args.command_timeout),
        f"backup {item.uuid} on {host}",
    )
    return backup_path


def delete_instance_dir(args: argparse.Namespace, host: str, item: InstanceDir) -> None:
    if not UUID_RE.match(item.uuid):
        raise AuditError(f"refusing to delete invalid UUID path component: {item.uuid}")
    path = f"{args.instances_path.rstrip('/')}/{item.uuid}"
    remote = shell_join([*sudo_prefix(args), "rm", "-rf", "--", path])
    checked(
        run(ssh_command(args, host, remote), args.command_timeout),
        f"delete {item.uuid} on {host}",
    )


def scan_host(args: argparse.Namespace, host: str, db_password: str) -> HostResult:
    log(f"{host}: scanning Nova instance directories", quiet=args.quiet)
    active_api = get_active_instance_uuids(args, host)
    debug(f"{host}: active instances from OpenStack API={len(active_api)}", args)
    instance_dirs = list_instance_dirs(args, host)
    debug(f"{host}: UUID-shaped directories on disk={len(instance_dirs)}", args)
    candidates = {item.uuid for item in instance_dirs if item.uuid not in active_api}
    debug(f"{host}: directories missing from host API={len(candidates)}", args)
    active_db = active_uuids_in_database(args, db_password, candidates)
    debug(
        f"{host}: missing-from-host directories still active in DB={len(active_db)}",
        args,
    )

    orphan_count = 0
    deleted_count = 0
    delete_failed = False
    for item in instance_dirs:
        item.active_in_openstack = item.uuid in active_api
        if not item.active_in_openstack:
            item.active_in_database = item.uuid in active_db
        item.orphan = not item.active_in_openstack and item.active_in_database is False
        if not item.orphan:
            continue

        orphan_count += 1
        if not args.delete_orphans:
            continue

        item.delete_attempted = True
        try:
            if args.backup:
                item.backup_path = backup_instance_dir(args, host, item)
            delete_instance_dir(args, host, item)
            item.delete_succeeded = True
            deleted_count += 1
        except AuditError as exc:
            item.delete_succeeded = False
            item.error = str(exc)
            delete_failed = True

    log(
        f"{host}: complete, dirs={len(instance_dirs)}, orphans={orphan_count}",
        quiet=args.quiet,
    )
    return HostResult(
        host=host,
        status="cleanup_failed" if delete_failed else "ok",
        instance_dirs=instance_dirs,
        orphan_count=orphan_count,
        deleted_count=deleted_count,
    )


def build_audit_result(args: argparse.Namespace) -> AuditResult:
    started = datetime.now()
    started_at = now_iso()
    db_password = get_database_password(args)
    results: list[HostResult] = []
    for host in discover_hosts(args):
        try:
            results.append(scan_host(args, host, db_password))
        except AuditError as exc:
            results.append(HostResult(host=host, status="error", error=str(exc)))

    orphans = sum(result.orphan_count for result in results)
    deleted = sum(result.deleted_count for result in results)
    errors = sum(1 for result in results if result.error)
    delete_failed = sum(
        1
        for result in results
        for item in result.instance_dirs
        if item.delete_attempted and item.delete_succeeded is False
    )
    savings = sum(
        item.size_kb
        for result in results
        for item in result.instance_dirs
        if item.orphan and (not args.delete_orphans or item.delete_succeeded)
    )
    return AuditResult(
        delete_orphans=args.delete_orphans,
        backup=args.backup,
        started_at=started_at,
        duration_seconds=round((datetime.now() - started).total_seconds(), 3),
        hosts_scanned=len(results),
        orphan_count=orphans,
        deleted_count=deleted,
        error_count=errors,
        delete_failed_count=delete_failed,
        potential_savings_kb=savings,
        results=results,
    )


def print_text(result: AuditResult) -> None:
    print("=== Nova orphan instance directory audit ===")
    print(f"Mode: {'DELETE' if result.delete_orphans else 'READ-ONLY/DRY-RUN'}")
    print(f"Backup: {'ON' if result.backup else 'OFF'}")
    print("")

    for host in result.results:
        print(f"--- {host.host} ---")
        if host.error:
            print(f"ERROR: {host.error}")
            continue
        orphans = [item for item in host.instance_dirs if item.orphan]
        if not orphans:
            print("OK: No orphan instance directories found")
            continue
        for item in orphans:
            size_mb = item.size_kb // 1024
            print(f"ORPHAN: {item.uuid} (~{size_mb} MB)")
            if item.backup_path:
                print(f"  backup: {item.backup_path}")
        if item.delete_attempted:
            status = (
                "deleted" if item.delete_succeeded else f"delete failed: {item.error}"
            )
            print(f"  cleanup: {status}")

    label = "space_freed_mb" if result.delete_orphans else "potential_savings_mb"
    print("")
    print("=== Summary ===")
    print(f"hosts_scanned={result.hosts_scanned}")
    print(f"orphans_found={result.orphan_count}")
    print(f"orphans_deleted={result.deleted_count}")
    print(f"errors={result.error_count}")
    print(f"{label}={result.potential_savings_kb // 1024}")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Find Nova instance directories that are absent from active Nova records."
    )
    parser.add_argument(
        "--node",
        action="append",
        help="Compute host to scan. Repeat for multiple hosts.",
    )
    parser.add_argument(
        "--delete-orphans",
        action="store_true",
        help="Delete confirmed orphan directories.",
    )
    parser.add_argument(
        "--yes-im-really-sure",
        action="store_true",
        help="Required with --delete-orphans.",
    )
    parser.add_argument(
        "--backup",
        action="store_true",
        help="Create a tar.gz backup before deleting.",
    )
    parser.add_argument(
        "--format",
        choices=["text", "json"],
        default="text",
        help="Output format. Default: text.",
    )
    parser.add_argument(
        "--quiet", action="store_true", help="Suppress progress logs on stderr."
    )
    parser.add_argument(
        "--debug", action="store_true", help="Include extra diagnostic progress logs."
    )
    parser.add_argument(
        "--ssh-option",
        action="append",
        default=[],
        help="Extra SSH option. Repeat as needed.",
    )
    parser.add_argument(
        "--ssh-command", default="ssh", help="SSH command. Default: ssh."
    )
    parser.add_argument(
        "--ssh-connect-timeout",
        type=int,
        default=5,
        help="SSH connect timeout in seconds.",
    )
    parser.add_argument(
        "--command-timeout",
        type=int,
        default=120,
        help="Timeout per external command in seconds.",
    )
    parser.add_argument(
        "--instances-path",
        default="/var/lib/nova/instances",
        help="Remote Nova instances path.",
    )
    parser.add_argument(
        "--no-sudo",
        action="store_true",
        help="Do not prefix remote commands with sudo -n.",
    )
    parser.add_argument(
        "--namespace",
        default="openstack",
        help="Kubernetes namespace for MariaDB. Default: openstack.",
    )
    parser.add_argument(
        "--mariadb-pod", default="mariadb-cluster-0", help="MariaDB pod name."
    )
    parser.add_argument(
        "--mariadb-secret",
        default="mariadb",
        help="Secret containing .data.root-password.",
    )
    parser.add_argument(
        "--mariadb-password-env",
        default="MYSQL_PWD",
        help="Environment variable containing the MariaDB password. Default: MYSQL_PWD.",
    )
    parser.add_argument(
        "--mariadb-user", default="root", help="MariaDB user. Default: root."
    )
    parser.add_argument(
        "--nova-database", default="nova", help="Nova database name. Default: nova."
    )
    parser.add_argument(
        "--kubectl-command",
        default="kubectl",
        help="kubectl command. Default: kubectl.",
    )
    parser.add_argument(
        "--kubectl-request-timeout",
        default="30s",
        help="kubectl request timeout. Default: 30s.",
    )
    parser.add_argument(
        "--openstack-command",
        default="openstack",
        help="OpenStack CLI command. Default: openstack.",
    )
    parser.add_argument(
        "--os-cloud", help="OpenStack cloud name to pass as --os-cloud."
    )
    parser.add_argument(
        "--skip-credential-check",
        action="store_true",
        help="Skip local OpenStack credential preflight.",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    if args.debug:
        args.quiet = False
    if args.delete_orphans and not args.yes_im_really_sure:
        print("ERROR: --delete-orphans requires --yes-im-really-sure", file=sys.stderr)
        return EXIT_ERROR
    if args.backup and not args.delete_orphans:
        print("ERROR: --backup requires --delete-orphans", file=sys.stderr)
        return EXIT_ERROR

    try:
        require_command(args.ssh_command)
        require_command(args.openstack_command)
        require_command(args.kubectl_command)
        verify_openstack_credentials(args)
        result = build_audit_result(args)
    except AuditError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return EXIT_ERROR

    if args.format == "json":
        print(json.dumps(asdict(result), indent=2, sort_keys=True))
    else:
        print_text(result)

    if result.error_count:
        return EXIT_ERROR
    if result.delete_failed_count:
        return EXIT_DELETE_FAILED
    if result.orphan_count and not args.delete_orphans:
        return EXIT_ORPHANS_FOUND
    return EXIT_OK


if __name__ == "__main__":
    raise SystemExit(main())
