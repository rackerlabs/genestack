#!/usr/bin/env python3
"""Validate service secret descriptors against Helm chart sensitive values."""

from __future__ import annotations

import argparse
import fnmatch
import json
import pathlib
import re
import subprocess
import sys
from dataclasses import dataclass, field
from typing import Any

EXIT_OK = 0
EXIT_ERROR = 1
EXIT_FINDINGS = 2

OPENSTACK_HELM_REPO_NAME = "openstack-helm"
OPENSTACK_HELM_REPO_URL = "https://tarballs.opendev.org/openstack/openstack-helm"

NON_CREDENTIAL_SEGMENTS = {
    "annotations",
    "cephclient",
    "existingsecret",
    "existingsecretname",
    "imagepullsecrets",
    "labels",
    "manifests",
    "ociimageregistry",
    "pathkeywords",
    "secretname",
    "secretref",
    "secretuuid",
    "serviceuser",
    "tolerations",
    "usersecretname",
}

SENSITIVE_EXACT_SEGMENTS = {
    "heartbeatkey",
    "kek",
    "memcachesecretkey",
    "metadataproxysharedsecret",
    "oldkek",
    "passphrase",
    "password",
    "passwd",
    "pin",
    "privatekey",
    "publickey",
    "secretkey",
}


class ToolError(Exception):
    """Expected runtime error for CLI reporting."""


@dataclass
class ServiceResult:
    service: str
    descriptor: str
    chart: str | None = None
    chart_version: str | None = None
    observed_paths: list[str] = field(default_factory=list)
    descriptor_paths: list[str] = field(default_factory=list)
    missing_paths: list[str] = field(default_factory=list)
    extra_paths: list[str] = field(default_factory=list)
    unsafe_list_paths: list[str] = field(default_factory=list)
    skipped: bool = False
    updated: bool = False
    error: str | None = None


def load_yaml(path: pathlib.Path) -> Any:
    try:
        from ruamel.yaml import YAML  # type: ignore

        yaml = YAML(typ="safe")
        with path.open() as stream:
            return yaml.load(stream) or {}
    except ImportError:
        try:
            import yaml  # type: ignore
        except ImportError as exc:
            raise ToolError("Install ruamel.yaml or PyYAML to read YAML files") from exc
        with path.open() as stream:
            return yaml.safe_load(stream) or {}


def dump_yaml(path: pathlib.Path, data: Any) -> None:
    try:
        from ruamel.yaml import YAML  # type: ignore

        yaml = YAML()
        yaml.default_flow_style = False
        with path.open("w") as stream:
            yaml.dump(data, stream)
        return
    except ImportError:
        try:
            import yaml  # type: ignore
        except ImportError as exc:
            raise ToolError(
                "Install ruamel.yaml or PyYAML to update YAML files"
            ) from exc
        with path.open("w") as stream:
            yaml.safe_dump(data, stream, sort_keys=False)


def nested_get(data: dict[str, Any], dotted_path: str, default: Any = None) -> Any:
    current: Any = data
    for segment in dotted_path.split("."):
        if not isinstance(current, dict) or segment not in current:
            return default
        current = current[segment]
    return current


def normalize_segment(segment: str) -> str:
    return re.sub(r"[^a-z0-9]", "", segment.lower())


def is_sensitive_path(path: str, value: Any = None) -> bool:
    segments = path.split(".")
    normalized = {normalize_segment(segment) for segment in segments}
    leaf = normalize_segment(segments[-1])

    if isinstance(value, bool):
        return False
    if value is None or value == "":
        return False
    if normalized & NON_CREDENTIAL_SEGMENTS:
        return False
    if leaf in SENSITIVE_EXACT_SEGMENTS:
        return True
    return leaf.endswith("password") or leaf.endswith("passphrase")


def discover_sensitive_paths(values: Any, prefix: tuple[str, ...] = ()) -> list[str]:
    paths: list[str] = []
    if isinstance(values, dict):
        for key, value in values.items():
            child_prefix = prefix + (str(key),)
            if isinstance(value, (dict, list)):
                paths.extend(discover_sensitive_paths(value, child_prefix))
            else:
                dotted = ".".join(child_prefix)
                if is_sensitive_path(dotted, value):
                    paths.append(dotted)
    elif isinstance(values, list):
        for index, value in enumerate(values):
            child_prefix = prefix + (str(index),)
            paths.extend(discover_sensitive_paths(value, child_prefix))
    return sorted(set(paths))


def descriptor_secret_paths(descriptor: dict[str, Any]) -> list[str]:
    secrets = descriptor.get("secrets") or []
    if not isinstance(secrets, list):
        return []
    return sorted(
        helm_key_to_chart_path(str(secret["helm_key"]))
        for secret in secrets
        if isinstance(secret, dict) and secret.get("helm_key")
    )


def descriptor_unsafe_list_paths(descriptor: dict[str, Any]) -> list[str]:
    secrets = descriptor.get("secrets") or []
    if not isinstance(secrets, list):
        return []

    unsafe_paths = []
    for secret in secrets:
        if not isinstance(secret, dict) or not secret.get("helm_key"):
            continue
        helm_key = str(secret["helm_key"])
        helm_flag = str(secret.get("helm_flag") or "--set")
        if re.search(r"\[\d+\]", helm_key) and helm_flag in {
            "--set",
            "--set-file",
            "--set-json",
            "--set-literal",
            "--set-string",
        }:
            unsafe_paths.append(helm_key)
    return sorted(unsafe_paths)


def helm_key_to_chart_path(helm_key: str) -> str:
    """Convert Helm --set path syntax to the dotted paths discovered from YAML."""
    segments: list[str] = []
    current: list[str] = []
    i = 0
    while i < len(helm_key):
        char = helm_key[i]
        if char == "\\" and i + 1 < len(helm_key):
            current.append(helm_key[i + 1])
            i += 2
            continue
        if char == ".":
            segments.append("".join(current))
            current = []
            i += 1
            continue
        if char == "[":
            end = helm_key.find("]", i)
            if end != -1:
                if current:
                    segments.append("".join(current))
                    current = []
                segments.append(helm_key[i + 1 : end])
                i = end + 1
                continue
        current.append(char)
        i += 1

    if current or not segments:
        segments.append("".join(current))
    return ".".join(segment for segment in segments if segment != "")


def descriptor_ignore_paths(descriptor: dict[str, Any]) -> list[str]:
    chart = descriptor.get("chart") or {}
    if not isinstance(chart, dict):
        return []
    ignore_paths = chart.get("ignore_paths") or []
    if not isinstance(ignore_paths, list):
        return []
    return [str(path) for path in ignore_paths]


def service_name_from_descriptor(path: pathlib.Path, descriptor: dict[str, Any]) -> str:
    name = nested_get(descriptor, "service.name")
    return str(name or path.stem)


def chart_service_name(service: str, descriptor: dict[str, Any]) -> str:
    return str(nested_get(descriptor, "chart.service_name") or service)


def chart_repo_name(descriptor: dict[str, Any]) -> str:
    return str(nested_get(descriptor, "chart.repo_name") or OPENSTACK_HELM_REPO_NAME)


def chart_repo_url(descriptor: dict[str, Any]) -> str:
    return str(nested_get(descriptor, "chart.repo_url") or OPENSTACK_HELM_REPO_URL)


def chart_version(
    service: str, chart_name: str, versions: dict[str, Any]
) -> str | None:
    charts = versions.get("charts") or {}
    if not isinstance(charts, dict):
        return None
    value = charts.get(service, charts.get(chart_name))
    return str(value) if value else None


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
        raise ToolError(f"{' '.join(command)} failed: {stderr}")
    return proc.stdout


def helm_show_values(
    args: argparse.Namespace, chart: str, repo: str, version: str
) -> str:
    direct_ref = f"{repo}/{chart}"
    command = [args.helm_command, "show", "values", direct_ref, "--version", version]
    try:
        return run_command(command, args.command_timeout)
    except ToolError as first_error:
        if not args.fallback_repo_url:
            raise
        fallback = [
            args.helm_command,
            "show",
            "values",
            chart,
            "--repo",
            args.fallback_repo_url,
            "--version",
            version,
        ]
        try:
            return run_command(fallback, args.command_timeout)
        except ToolError as second_error:
            raise ToolError(
                f"{first_error}; fallback failed: {second_error}"
            ) from second_error


def should_ignore(path: str, patterns: list[str]) -> bool:
    return any(fnmatch.fnmatch(path, pattern) for pattern in patterns)


def service_descriptor_paths(
    services_dir: pathlib.Path, requested: list[str]
) -> list[pathlib.Path]:
    if requested:
        paths = []
        for service in requested:
            path = services_dir / f"{service}.yaml"
            if not path.exists():
                raise ToolError(f"Service descriptor not found: {path}")
            paths.append(path)
        return paths
    return sorted(
        path
        for path in services_dir.glob("*.yaml")
        if path.name != "example-service.yaml"
    )


def update_chart_schema_cache(
    path: pathlib.Path,
    descriptor: dict[str, Any],
    service: str,
    chart: str,
    version: str,
    observed_paths: list[str],
    observed_values: dict[str, Any],
) -> None:
    descriptor["chart_secret_schema"] = {
        "generated_by": "ops-tools/secret_schema_validator",
        "service": service,
        "chart": chart,
        "chart_version": version,
        "sensitive_value_paths": observed_paths,
        "sensitive_values": observed_values,
    }
    dump_yaml(path, descriptor)


def validate_service(
    args: argparse.Namespace,
    path: pathlib.Path,
    versions: dict[str, Any],
) -> ServiceResult:
    descriptor = load_yaml(path)
    if not isinstance(descriptor, dict):
        raise ToolError(f"Descriptor is not a YAML mapping: {path}")

    service = service_name_from_descriptor(path, descriptor)
    chart = chart_service_name(service, descriptor)
    repo = chart_repo_name(descriptor)
    version = chart_version(service, chart, versions)
    result = ServiceResult(
        service=service,
        descriptor=str(path),
        chart=f"{repo}/{chart}",
        chart_version=version,
    )

    if not version:
        result.skipped = True
        result.error = "chart version not found"
        return result

    values_text = helm_show_values(args, chart, repo, version)
    values = parse_yaml_text(values_text)
    ignore_paths = [*args.ignore_path, *descriptor_ignore_paths(descriptor)]
    observed = [
        item
        for item in discover_sensitive_paths(values)
        if not should_ignore(item, ignore_paths)
    ]
    observed_values = {path: nested_get(values, path) for path in observed}
    descriptor_paths = descriptor_secret_paths(descriptor)

    result.observed_paths = observed
    result.descriptor_paths = descriptor_paths
    result.missing_paths = sorted(set(observed) - set(descriptor_paths))
    result.extra_paths = sorted(set(descriptor_paths) - set(observed))
    result.unsafe_list_paths = descriptor_unsafe_list_paths(descriptor)

    if args.update_cache:
        update_chart_schema_cache(
            path, descriptor, service, chart, version, observed, observed_values
        )
        result.updated = True

    return result


def parse_yaml_text(text: str) -> Any:
    try:
        from ruamel.yaml import YAML  # type: ignore

        yaml = YAML(typ="safe")
        return yaml.load(text) or {}
    except ImportError:
        try:
            import yaml  # type: ignore
        except ImportError as exc:
            raise ToolError(
                "Install ruamel.yaml or PyYAML to parse Helm values"
            ) from exc
        return yaml.safe_load(text) or {}


def report_to_dict(results: list[ServiceResult]) -> dict[str, Any]:
    missing_count = sum(len(result.missing_paths) for result in results)
    extra_count = sum(len(result.extra_paths) for result in results)
    unsafe_list_count = sum(len(result.unsafe_list_paths) for result in results)
    skipped_count = sum(1 for result in results if result.skipped)
    error_count = sum(1 for result in results if result.error and not result.skipped)
    return {
        "summary": {
            "services": len(results),
            "missing_paths": missing_count,
            "extra_paths": extra_count,
            "unsafe_list_paths": unsafe_list_count,
            "skipped": skipped_count,
            "errors": error_count,
            "updated": sum(1 for result in results if result.updated),
        },
        "services": [result.__dict__ for result in results],
    }


def print_text_report(report: dict[str, Any]) -> None:
    summary = report["summary"]
    print(
        "Secret schema validation: "
        f"{summary['services']} service(s), "
        f"{summary['missing_paths']} missing chart path(s), "
        f"{summary['extra_paths']} descriptor-only path(s), "
        f"{summary['unsafe_list_paths']} unsafe list path(s), "
        f"{summary['skipped']} skipped."
    )
    for result in report["services"]:
        if result["skipped"]:
            print(f"\n{result['service']}: skipped ({result['error']})")
            continue
        print(f"\n{result['service']}: {result['chart']} {result['chart_version']}")
        if result["missing_paths"]:
            print("  Missing from descriptor secrets:")
            for path in result["missing_paths"]:
                print(f"    - {path}")
        if result["extra_paths"]:
            print("  Present in descriptor but not observed in chart values:")
            for path in result["extra_paths"]:
                print(f"    - {path}")
        if result["unsafe_list_paths"]:
            print("  Unsafe Helm list paths in descriptor secrets:")
            for path in result["unsafe_list_paths"]:
                print(f"    - {path}")
            print(
                "  Helm --set style flags replace list items instead of merging them."
            )
        if result["updated"]:
            print("  Updated chart_secret_schema cache.")
        if (
            not result["missing_paths"]
            and not result["extra_paths"]
            and not result["unsafe_list_paths"]
        ):
            print("  OK")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Validate bin/services secret descriptors against Helm chart values."
    )
    parser.add_argument("--services-dir", default="bin/services")
    parser.add_argument("--chart-versions-file", default="helm-chart-versions.yaml")
    parser.add_argument(
        "--service", action="append", default=[], help="Service to validate"
    )
    parser.add_argument("--helm-command", default="helm")
    parser.add_argument("--command-timeout", type=int, default=120)
    parser.add_argument("--fallback-repo-url", default=OPENSTACK_HELM_REPO_URL)
    parser.add_argument("--ignore-path", action="append", default=[])
    parser.add_argument("--update-cache", action="store_true")
    parser.add_argument("--format", choices=("text", "json"), default="text")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    try:
        services_dir = pathlib.Path(args.services_dir)
        versions_file = pathlib.Path(args.chart_versions_file)
        versions = load_yaml(versions_file)
        paths = service_descriptor_paths(services_dir, args.service)

        results = [validate_service(args, path, versions) for path in paths]
        report = report_to_dict(results)
        if args.format == "json":
            print(json.dumps(report, indent=2, sort_keys=True))
        else:
            print_text_report(report)

        if report["summary"]["errors"]:
            return EXIT_ERROR
        if report["summary"]["missing_paths"] or report["summary"]["unsafe_list_paths"]:
            return EXIT_FINDINGS
        return EXIT_OK
    except (OSError, subprocess.TimeoutExpired, ToolError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return EXIT_ERROR


if __name__ == "__main__":
    sys.exit(main())
