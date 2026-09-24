#!/usr/bin/env python3
"""Detect OpenStack Helm default credentials in live Kubernetes secrets."""

from __future__ import annotations

import argparse
import base64
import binascii
import json
import re
import subprocess
import sys
from dataclasses import asdict, dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any, Iterable

try:
    from ruamel.yaml import YAML

    def load_yaml_documents(raw: str) -> list[Any]:
        return list(YAML(typ="safe").load_all(raw))

except ImportError:  # pragma: no cover - exercised on hosts without ruamel.yaml
    try:
        import yaml

        def load_yaml_documents(raw: str) -> list[Any]:
            return list(yaml.safe_load_all(raw))

    except ImportError as exc:  # pragma: no cover - depends on host packaging
        raise SystemExit(
            "a YAML parser is required; install dependencies from requirements.txt"
        ) from exc


EXIT_OK = 0
EXIT_ERROR = 1
EXIT_FINDINGS = 2

DEFAULT_COMPONENTS_FILE = "openstack-components.yaml"
DEFAULT_CHART_VERSIONS_FILE = "helm-chart-versions.yaml"
DEFAULT_NAMESPACE = "openstack"
DEFAULT_HELM_REPO_NAME = "openstack-helm"
DEFAULT_HELM_REPO_URL = "https://tarballs.opendev.org/openstack/openstack-helm"

SENSITIVE_KEY_RE = re.compile(
    r"(?:^|[._-])(?:password|passwd|passphrase|secret|token|key)(?:$|[._-])",
    re.IGNORECASE,
)


class ScannerError(RuntimeError):
    """Raised when configuration or an external command prevents a scan."""


@dataclass(frozen=True)
class CommandResult:
    returncode: int
    stdout: str
    stderr: str
    timed_out: bool = False


@dataclass(frozen=True)
class DefaultSecretValue:
    secret_name: str
    key: str
    value: bytes


@dataclass(frozen=True)
class Finding:
    service: str
    chart_version: str
    namespace: str
    secret_name: str
    key: str
    recommendation: str = (
        "Generate non-default credentials with create-secrets.sh or rotate the "
        "Kubernetes secret manually, then restart affected workloads."
    )


@dataclass(frozen=True)
class ScanWarning:
    service: str
    secret_name: str
    key: str
    message: str


@dataclass
class ServiceResult:
    service: str
    chart_version: str
    defaults_checked: int = 0
    live_secrets_checked: int = 0
    findings: list[Finding] = field(default_factory=list)
    warnings: list[ScanWarning] = field(default_factory=list)
    error: str | None = None


@dataclass
class ScanReport:
    namespace: str
    services_scanned: int
    defaults_checked: int
    live_secrets_checked: int
    findings_count: int
    warning_count: int
    error_count: int
    results: list[ServiceResult]


def log(message: str, *, quiet: bool) -> None:
    if not quiet:
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        print(f"[{timestamp}] {message}", file=sys.stderr, flush=True)


def run_command(command: list[str], *, timeout: int) -> CommandResult:
    try:
        completed = subprocess.run(
            command,
            text=True,
            capture_output=True,
            timeout=timeout,
            check=False,
        )
    except FileNotFoundError as exc:
        raise ScannerError(f"required command not found: {command[0]}") from exc
    except subprocess.TimeoutExpired as exc:
        stdout = exc.stdout if isinstance(exc.stdout, str) else ""
        stderr = exc.stderr if isinstance(exc.stderr, str) else ""
        return CommandResult(
            returncode=124,
            stdout=stdout,
            stderr=stderr or f"command timed out after {timeout}s",
            timed_out=True,
        )
    return CommandResult(
        returncode=completed.returncode,
        stdout=completed.stdout,
        stderr=completed.stderr,
    )


def checked(result: CommandResult, action: str) -> str:
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip() or "no output"
        raise ScannerError(f"{action} failed: {detail}")
    return result.stdout


def read_yaml_mapping(path: str, top_level_key: str) -> dict[str, Any]:
    source = Path(path)
    try:
        raw = source.read_text(encoding="utf-8")
    except OSError as exc:
        raise ScannerError(f"cannot read {source}: {exc}") from exc

    try:
        documents = load_yaml_documents(raw)
    except Exception as exc:
        raise ScannerError(f"cannot parse YAML from {source}: {exc}") from exc

    document = next((item for item in documents if item is not None), None)
    if not isinstance(document, dict):
        raise ScannerError(f"expected a YAML mapping in {source}")
    values = document.get(top_level_key)
    if not isinstance(values, dict):
        raise ScannerError(f"expected '{top_level_key}' mapping in {source}")
    return dict(values)


def load_enabled_services(path: str) -> list[str]:
    components = read_yaml_mapping(path, "components")
    return sorted(str(name) for name, enabled in components.items() if enabled is True)


def load_chart_versions(path: str) -> dict[str, str]:
    charts = read_yaml_mapping(path, "charts")
    versions: dict[str, str] = {}
    for name, version in charts.items():
        if version is not None:
            versions[str(name)] = str(version)
    return versions


def select_services(enabled: list[str], requested: list[str] | None) -> list[str]:
    if not requested:
        return enabled
    requested_unique = list(dict.fromkeys(requested))
    disabled = sorted(set(requested_unique) - set(enabled))
    if disabled:
        raise ScannerError(
            "requested services are not enabled in the components file: "
            + ", ".join(disabled)
        )
    return requested_unique


def is_sensitive_key(key: str) -> bool:
    return bool(SENSITIVE_KEY_RE.search(key))


def decode_base64_value(value: Any) -> bytes:
    if not isinstance(value, str):
        raise ValueError("base64 value is not a string")
    try:
        return base64.b64decode(value, validate=True)
    except (binascii.Error, ValueError) as exc:
        raise ValueError("value is not valid base64") from exc


def extract_default_secret_values(
    rendered_yaml: str,
    service: str,
) -> tuple[list[DefaultSecretValue], list[ScanWarning]]:
    try:
        documents = load_yaml_documents(rendered_yaml)
    except Exception as exc:
        raise ScannerError(f"cannot parse rendered YAML for {service}: {exc}") from exc

    defaults: dict[tuple[str, str], DefaultSecretValue] = {}
    warnings: list[ScanWarning] = []
    for document in documents:
        if not isinstance(document, dict) or document.get("kind") != "Secret":
            continue
        metadata = document.get("metadata")
        if not isinstance(metadata, dict) or not isinstance(metadata.get("name"), str):
            continue
        secret_name = metadata["name"]

        data = document.get("data")
        if isinstance(data, dict):
            for key, encoded_value in data.items():
                key = str(key)
                if not is_sensitive_key(key):
                    continue
                try:
                    value = decode_base64_value(encoded_value)
                except ValueError as exc:
                    warnings.append(
                        ScanWarning(service, secret_name, key, str(exc))
                    )
                    continue
                if value:
                    defaults[(secret_name, key)] = DefaultSecretValue(
                        secret_name, key, value
                    )

        string_data = document.get("stringData")
        if isinstance(string_data, dict):
            for key, plain_value in string_data.items():
                key = str(key)
                if not is_sensitive_key(key):
                    continue
                if not isinstance(plain_value, str):
                    warnings.append(
                        ScanWarning(
                            service,
                            secret_name,
                            key,
                            "stringData value is not a string",
                        )
                    )
                    continue
                value = plain_value.encode("utf-8")
                if value:
                    defaults[(secret_name, key)] = DefaultSecretValue(
                        secret_name, key, value
                    )

    return list(defaults.values()), warnings


def render_chart(
    service: str,
    version: str,
    args: argparse.Namespace,
) -> str:
    chart_reference = f"{args.helm_repo_name}/{service}"
    command = [
        args.helm_command,
        "template",
        service,
        chart_reference,
        "--version",
        version,
        "--namespace",
        args.namespace,
    ]
    result = run_command(command, timeout=args.command_timeout)
    if result.returncode == 0:
        return result.stdout

    # A direct repository URL makes the scanner usable before a repo alias is added.
    fallback_command = [
        args.helm_command,
        "template",
        service,
        service,
        "--repo",
        args.helm_repo_url,
        "--version",
        version,
        "--namespace",
        args.namespace,
    ]
    fallback = run_command(fallback_command, timeout=args.command_timeout)
    if fallback.returncode != 0:
        primary_detail = result.stderr.strip() or result.stdout.strip() or "no output"
        fallback_detail = fallback.stderr.strip() or fallback.stdout.strip() or "no output"
        raise ScannerError(
            f"rendering {chart_reference} {version} failed: {primary_detail}; "
            f"repository URL fallback failed: {fallback_detail}"
        )
    return fallback.stdout


def is_not_found(result: CommandResult) -> bool:
    detail = f"{result.stderr}\n{result.stdout}".lower()
    return result.returncode != 0 and (
        "(notfound)" in detail or " not found" in detail or "notfound" in detail
    )


def fetch_live_secret(
    secret_name: str,
    args: argparse.Namespace,
) -> dict[str, Any] | None:
    command = [
        args.kubectl_command,
        "-n",
        args.namespace,
        "get",
        "secret",
        secret_name,
        "-o",
        "json",
    ]
    result = run_command(command, timeout=args.command_timeout)
    if is_not_found(result):
        return None
    raw = checked(result, f"reading Kubernetes secret {args.namespace}/{secret_name}")
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ScannerError(
            f"cannot parse Kubernetes secret {args.namespace}/{secret_name} as JSON: {exc}"
        ) from exc
    if not isinstance(payload, dict):
        raise ScannerError(
            f"unexpected Kubernetes response for {args.namespace}/{secret_name}"
        )
    data = payload.get("data", {})
    if not isinstance(data, dict):
        raise ScannerError(
            f"Kubernetes secret {args.namespace}/{secret_name} has invalid data"
        )

    return {str(key): value for key, value in data.items()}


def compare_defaults(
    service: str,
    version: str,
    defaults: Iterable[DefaultSecretValue],
    args: argparse.Namespace,
) -> ServiceResult:
    defaults_list = list(defaults)
    result = ServiceResult(
        service=service,
        chart_version=version,
        defaults_checked=len(defaults_list),
    )
    grouped: dict[str, list[DefaultSecretValue]] = {}
    for default in defaults_list:
        grouped.setdefault(default.secret_name, []).append(default)

    for secret_name, expected_values in sorted(grouped.items()):
        live = fetch_live_secret(secret_name, args)
        if live is None:
            result.warnings.append(
                ScanWarning(
                    service,
                    secret_name,
                    "",
                    "rendered secret is not present in the target namespace",
                )
            )
            continue
        result.live_secrets_checked += 1
        for expected in expected_values:
            if expected.key not in live:
                result.warnings.append(
                    ScanWarning(
                        service,
                        secret_name,
                        expected.key,
                        "sensitive key is absent from the live secret",
                    )
                )
                continue
            try:
                live_value = decode_base64_value(live[expected.key])
            except ValueError as exc:
                result.warnings.append(
                    ScanWarning(service, secret_name, expected.key, str(exc))
                )
                continue
            if live_value == expected.value:
                result.findings.append(
                    Finding(
                        service=service,
                        chart_version=version,
                        namespace=args.namespace,
                        secret_name=secret_name,
                        key=expected.key,
                    )
                )
    return result


def scan_service(
    service: str,
    version: str,
    args: argparse.Namespace,
) -> ServiceResult:
    log(f"{service}: rendering chart version {version}", quiet=args.quiet)
    rendered = render_chart(service, version, args)
    defaults, warnings = extract_default_secret_values(rendered, service)
    log(
        f"{service}: checking {len(defaults)} sensitive defaults",
        quiet=args.quiet,
    )
    result = compare_defaults(service, version, defaults, args)
    result.warnings[:0] = warnings
    return result


def build_report(namespace: str, results: list[ServiceResult]) -> ScanReport:
    return ScanReport(
        namespace=namespace,
        services_scanned=len(results),
        defaults_checked=sum(item.defaults_checked for item in results),
        live_secrets_checked=sum(item.live_secrets_checked for item in results),
        findings_count=sum(len(item.findings) for item in results),
        warning_count=sum(len(item.warnings) for item in results),
        error_count=sum(item.error is not None for item in results),
        results=results,
    )


def report_as_dict(report: ScanReport) -> dict[str, Any]:
    return asdict(report)


def print_text_report(report: ScanReport) -> None:
    for result in report.results:
        if result.error:
            print(f"ERROR {result.service} ({result.chart_version}): {result.error}")
        for finding in result.findings:
            print(
                "DEFAULT PASSWORD FOUND: "
                f"service={finding.service} chart={finding.chart_version} "
                f"secret={finding.namespace}/{finding.secret_name} key={finding.key}"
            )
            print(f"  Remediation: {finding.recommendation}")
        for warning in result.warnings:
            target = warning.secret_name
            if warning.key:
                target += f"/{warning.key}"
            print(f"WARNING {warning.service} {target}: {warning.message}")
    print(
        "Summary: "
        f"services={report.services_scanned} "
        f"defaults_checked={report.defaults_checked} "
        f"live_secrets={report.live_secrets_checked} "
        f"findings={report.findings_count} "
        f"warnings={report.warning_count} errors={report.error_count}"
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Detect OpenStack Helm default credentials in Kubernetes secrets."
    )
    parser.add_argument("--components-file", default=DEFAULT_COMPONENTS_FILE)
    parser.add_argument(
        "--chart-versions-file", default=DEFAULT_CHART_VERSIONS_FILE
    )
    parser.add_argument("--namespace", default=DEFAULT_NAMESPACE)
    parser.add_argument("--helm-repo-name", default=DEFAULT_HELM_REPO_NAME)
    parser.add_argument("--helm-repo-url", default=DEFAULT_HELM_REPO_URL)
    parser.add_argument("--kubectl-command", default="kubectl")
    parser.add_argument("--helm-command", default="helm")
    parser.add_argument("--command-timeout", type=int, default=120)
    parser.add_argument(
        "--service",
        action="append",
        help="scan only this enabled service; may be repeated",
    )
    parser.add_argument("--format", choices=("text", "json"), default="text")
    parser.add_argument("--quiet", action="store_true")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if args.command_timeout <= 0:
        print("error: --command-timeout must be greater than zero", file=sys.stderr)
        return EXIT_ERROR

    try:
        enabled = load_enabled_services(args.components_file)
        services = select_services(enabled, args.service)
        versions = load_chart_versions(args.chart_versions_file)
        missing_versions = [service for service in services if service not in versions]
        if missing_versions:
            raise ScannerError(
                "missing chart versions for enabled services: "
                + ", ".join(missing_versions)
            )
    except ScannerError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return EXIT_ERROR

    results: list[ServiceResult] = []
    for service in services:
        version = versions[service]
        try:
            results.append(scan_service(service, version, args))
        except ScannerError as exc:
            results.append(
                ServiceResult(service=service, chart_version=version, error=str(exc))
            )

    report = build_report(args.namespace, results)
    if args.format == "json":
        print(json.dumps(report_as_dict(report), indent=2, sort_keys=True))
    else:
        print_text_report(report)

    if report.error_count:
        return EXIT_ERROR
    if report.findings_count:
        return EXIT_FINDINGS
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
