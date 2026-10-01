#!/usr/bin/env python3
"""Report Kubernetes secrets that still match Helm chart default credentials."""

from __future__ import annotations

import argparse
import base64
import json
import pathlib
import subprocess
import sys
from dataclasses import dataclass
from typing import Any

SECRET_SCHEMA_TOOL = (
    pathlib.Path(__file__).resolve().parents[1]
    / "secret_schema_validator"
    / "secret_schema_validator.py"
)

sys.path.insert(0, str(SECRET_SCHEMA_TOOL.parent))
import secret_schema_validator as schema  # noqa: E402

EXIT_OK = 0
EXIT_ERROR = 1
EXIT_FINDINGS = 2


@dataclass
class Finding:
    service: str
    helm_key: str
    namespace: str
    secret: str
    data_key: str
    reason: str


def run_command(command: list[str], timeout: int) -> str:
    proc = subprocess.run(
        command,
        check=False,
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    if proc.returncode != 0:
        stderr = proc.stderr.strip()
        raise schema.ToolError(f"{' '.join(command)} failed: {stderr}")
    return proc.stdout


def decode_secret_data(data: dict[str, str], key: str) -> str | None:
    raw = data.get(key)
    if raw is None:
        return None
    try:
        return base64.b64decode(raw).decode()
    except Exception as exc:
        raise schema.ToolError(f"unable to decode secret data key {key}") from exc


def kubectl_secret_data(
    kubectl: str, namespace: str, secret_name: str, timeout: int
) -> dict[str, str] | None:
    command = [
        kubectl,
        "get",
        "secret",
        secret_name,
        "--namespace",
        namespace,
        "-o",
        "json",
    ]
    proc = subprocess.run(
        command,
        check=False,
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    if proc.returncode != 0:
        if "NotFound" in proc.stderr or "not found" in proc.stderr.lower():
            return None
        raise schema.ToolError(f"{' '.join(command)} failed: {proc.stderr.strip()}")
    secret = json.loads(proc.stdout)
    data = secret.get("data") or {}
    if not isinstance(data, dict):
        return {}
    return {str(key): str(value) for key, value in data.items()}


def chart_sensitive_defaults(
    args: argparse.Namespace,
    service: str,
    descriptor: dict[str, Any],
    versions: dict[str, Any],
) -> dict[str, Any]:
    chart = schema.chart_service_name(service, descriptor)
    repo = schema.chart_repo_name(descriptor)
    version = schema.chart_version(service, chart, versions)
    cached = descriptor.get("chart_secret_schema") or {}
    cached_values = cached.get("sensitive_values") or {}

    if (
        isinstance(cached, dict)
        and cached.get("chart_version") == version
        and isinstance(cached_values, dict)
        and cached_values
        and not args.refresh_chart
    ):
        return {str(key): value for key, value in cached_values.items()}

    if not version:
        return {}

    values_text = schema.helm_show_values(args, chart, repo, version)
    values = schema.parse_yaml_text(values_text)
    defaults: dict[str, Any] = {}
    for path in schema.discover_sensitive_paths(values):
        if schema.should_ignore(path, args.ignore_path):
            continue
        defaults[path] = schema.nested_get(values, path)
    return defaults


def iter_secret_refs(
    descriptor: dict[str, Any], service_namespace: str
) -> list[tuple[str, str, str, str]]:
    refs: list[tuple[str, str, str, str]] = []
    secrets = descriptor.get("secrets") or []
    if not isinstance(secrets, list):
        return refs

    for entry in secrets:
        if not isinstance(entry, dict):
            continue
        helm_key = entry.get("helm_key")

        source_secret = entry.get("source_secret")
        data_key = entry.get("data_key")
        if helm_key and source_secret and data_key:
            namespace = entry.get("source_namespace") or service_namespace
            refs.append(
                (str(helm_key), str(namespace), str(source_secret), str(data_key))
            )

        name = entry.get("name")
        keys = entry.get("keys")
        if name and isinstance(keys, dict):
            namespace = entry.get("namespace") or service_namespace
            for key_name in keys:
                default_key = f"{helm_key}.{key_name}" if helm_key else str(key_name)
                refs.append(
                    (
                        default_key,
                        str(namespace),
                        str(name),
                        str(key_name),
                    )
                )
    return refs


def scan_service(
    args: argparse.Namespace,
    descriptor_path: pathlib.Path,
    versions: dict[str, Any],
) -> list[Finding]:
    descriptor = schema.load_yaml(descriptor_path)
    if not isinstance(descriptor, dict):
        raise schema.ToolError(f"Descriptor is not a YAML mapping: {descriptor_path}")

    service = schema.service_name_from_descriptor(descriptor_path, descriptor)
    service_namespace = str(
        schema.nested_get(descriptor, "service.namespace", "openstack")
    )
    defaults = chart_sensitive_defaults(args, service, descriptor, versions)
    findings: list[Finding] = []
    secret_cache: dict[tuple[str, str], dict[str, str] | None] = {}

    for helm_key, namespace, secret_name, data_key in iter_secret_refs(
        descriptor, service_namespace
    ):
        default = defaults.get(helm_key)
        if default is None:
            continue
        if isinstance(default, bool):
            continue
        default_text = str(default)
        if default_text == "":
            continue

        cache_key = (namespace, secret_name)
        if cache_key not in secret_cache:
            secret_cache[cache_key] = kubectl_secret_data(
                args.kubectl_command, namespace, secret_name, args.command_timeout
            )
        data = secret_cache[cache_key]
        if data is None:
            findings.append(
                Finding(
                    service,
                    helm_key,
                    namespace,
                    secret_name,
                    data_key,
                    "secret is missing; chart default may be used",
                )
            )
            continue

        value = decode_secret_data(data, data_key)
        if value is None or value == "":
            findings.append(
                Finding(
                    service,
                    helm_key,
                    namespace,
                    secret_name,
                    data_key,
                    "secret data key is missing or empty; chart default may be used",
                )
            )
        elif value == default_text:
            findings.append(
                Finding(
                    service,
                    helm_key,
                    namespace,
                    secret_name,
                    data_key,
                    "secret value matches chart default",
                )
            )

    return findings


def report_to_dict(findings: list[Finding]) -> dict[str, Any]:
    return {
        "summary": {"findings": len(findings)},
        "findings": [finding.__dict__ for finding in findings],
    }


def print_text_report(findings: list[Finding]) -> None:
    if not findings:
        print("Default password scan: no chart-default credentials detected.")
        return

    print(
        "Default password scan: "
        f"{len(findings)} chart-default credential finding(s)."
    )
    for finding in findings:
        print(
            f"- {finding.service}: {finding.namespace}/{finding.secret}:"
            f"{finding.data_key} -> {finding.helm_key} ({finding.reason})"
        )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Detect Kubernetes secrets that still match Helm chart defaults."
    )
    parser.add_argument("--services-dir", default="bin/services")
    parser.add_argument("--chart-versions-file", default="helm-chart-versions.yaml")
    parser.add_argument(
        "--service", action="append", default=[], help="Service to scan"
    )
    parser.add_argument("--kubectl-command", default="kubectl")
    parser.add_argument("--helm-command", default="helm")
    parser.add_argument("--command-timeout", type=int, default=120)
    parser.add_argument("--fallback-repo-url", default=schema.OPENSTACK_HELM_REPO_URL)
    parser.add_argument("--ignore-path", action="append", default=[])
    parser.add_argument(
        "--refresh-chart",
        action="store_true",
        help="ignore chart_secret_schema cache and fetch Helm values",
    )
    parser.add_argument("--format", choices=("text", "json"), default="text")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    try:
        services_dir = pathlib.Path(args.services_dir)
        versions = schema.load_yaml(pathlib.Path(args.chart_versions_file))
        paths = schema.service_descriptor_paths(services_dir, args.service)
        findings: list[Finding] = []
        for path in paths:
            findings.extend(scan_service(args, path, versions))

        if args.format == "json":
            print(json.dumps(report_to_dict(findings), indent=2, sort_keys=True))
        else:
            print_text_report(findings)
        return EXIT_FINDINGS if findings else EXIT_OK
    except (
        OSError,
        json.JSONDecodeError,
        subprocess.TimeoutExpired,
        schema.ToolError,
    ) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return EXIT_ERROR


if __name__ == "__main__":
    sys.exit(main())
