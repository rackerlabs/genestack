#!/usr/bin/env python3
"""Scan a node for CRI pod sandboxes not reported by Kubernetes."""

from __future__ import annotations

import argparse
import json
import shlex
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime
from typing import Any

EXIT_OK = 0
EXIT_ERROR = 1
EXIT_FINDINGS = 2


@dataclass(frozen=True)
class CrictlPod:
    uid: str
    namespace: str
    name: str
    attempt: int | None
    state: str
    id: str
    created_at: str


@dataclass(frozen=True)
class KubernetesPod:
    uid: str
    match_uids: tuple[str, ...]
    namespace: str
    name: str
    phase: str
    node_name: str


@dataclass(frozen=True)
class NodeTarget:
    node_name: str
    ssh_target: str
    address_type: str


@dataclass(frozen=True)
class ScanResult:
    node_name: str
    ssh_target: str
    crictl_pods: list[CrictlPod]
    kubernetes_pods: list[KubernetesPod]
    rogue_uids: list[str]
    missing_on_node_uids: list[str]
    error: str = ""


def log(message: str, *, quiet: bool = False) -> None:
    if quiet:
        return
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{timestamp}] {message}", file=sys.stderr, flush=True)


def run_command(
    command: list[str],
    *,
    timeout: int,
    input_text: str | None = None,
) -> str:
    try:
        completed = subprocess.run(
            command,
            input=input_text,
            text=True,
            capture_output=True,
            timeout=timeout,
            check=False,
        )
    except FileNotFoundError as exc:
        raise SystemExit(f"required command not found: {command[0]}") from exc
    except subprocess.TimeoutExpired as exc:
        detail = exc.stderr if isinstance(exc.stderr, str) else ""
        detail = detail.strip() or f"command timed out after {timeout}s"
        raise SystemExit(f"command timed out: {shlex.join(command)}\n{detail}") from exc

    if completed.returncode != 0:
        stderr = completed.stderr.strip()
        stdout = completed.stdout.strip()
        detail = stderr or stdout or "no output"
        raise SystemExit(
            f"command failed ({completed.returncode}): {shlex.join(command)}\n{detail}"
        )

    return completed.stdout


def run_ssh_json(
    ssh_target: str,
    remote_command: list[str],
    ssh_options: list[str],
    command_timeout: int,
    ssh_connect_timeout: int,
) -> dict[str, Any]:
    command = [
        "ssh",
        "-q",
        "-o",
        "BatchMode=yes",
        "-o",
        f"ConnectTimeout={ssh_connect_timeout}",
        *ssh_options,
        ssh_target,
        shlex.join(remote_command),
    ]
    return parse_json(
        run_command(command, timeout=command_timeout),
        f"ssh {ssh_target} {shlex.join(remote_command)}",
    )


def parse_json(raw: str, source: str) -> dict[str, Any]:
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"failed to parse JSON from {source}: {exc}") from exc

    if not isinstance(parsed, dict):
        raise SystemExit(f"expected JSON object from {source}")
    return parsed


def kubectl_base_command(
    kubectl_command: str,
    kubeconfig: str | None,
    context: str | None,
) -> list[str]:
    command = [kubectl_command]
    if kubeconfig:
        command.extend(["--kubeconfig", kubeconfig])
    if context:
        command.extend(["--context", context])
    return command


def pod_uid_from_labels(labels: dict[str, Any]) -> str:
    for key in (
        "io.kubernetes.pod.uid",
        "io.kubernetes.sandbox.id",
    ):
        value = labels.get(key)
        if isinstance(value, str) and value:
            return value
    return ""


def kubernetes_pod_match_uids(metadata: dict[str, Any]) -> tuple[str, ...]:
    candidates: list[str] = []
    uid = metadata.get("uid")
    if isinstance(uid, str) and uid:
        candidates.append(uid)

    annotations = (
        metadata.get("annotations")
        if isinstance(metadata.get("annotations"), dict)
        else {}
    )
    for key in (
        "kubernetes.io/config.mirror",
        "kubernetes.io/config.hash",
    ):
        value = annotations.get(key)
        if isinstance(value, str) and value and value not in candidates:
            candidates.append(value)

    return tuple(candidates)


def load_crictl_pods(
    ssh_target: str,
    ssh_options: list[str],
    crictl_command: str,
    use_sudo: bool,
    command_timeout: int,
    ssh_connect_timeout: int,
    quiet: bool,
) -> list[CrictlPod]:
    remote_command = []
    if use_sudo:
        remote_command.extend(["sudo", "-n"])
    remote_command.extend([crictl_command, "pods", "-o", "json"])

    log(
        f"SSH {ssh_target}: running {shlex.join(remote_command)}",
        quiet=quiet,
    )
    payload = run_ssh_json(
        ssh_target,
        remote_command,
        ssh_options,
        command_timeout,
        ssh_connect_timeout,
    )
    pods = payload.get("items", [])
    if not isinstance(pods, list):
        raise SystemExit("unexpected crictl JSON: .items is not a list")
    log(f"SSH {ssh_target}: received {len(pods)} CRI pod sandboxes", quiet=quiet)

    crictl_pods: list[CrictlPod] = []
    for pod in pods:
        if not isinstance(pod, dict):
            continue

        metadata = pod.get("metadata") if isinstance(pod.get("metadata"), dict) else {}
        labels = pod.get("labels") if isinstance(pod.get("labels"), dict) else {}
        uid = pod_uid_from_labels(labels)
        if not uid:
            continue

        crictl_pods.append(
            CrictlPod(
                uid=uid,
                namespace=str(metadata.get("namespace", "")),
                name=str(metadata.get("name", "")),
                attempt=(
                    metadata.get("attempt")
                    if isinstance(metadata.get("attempt"), int)
                    else None
                ),
                state=str(pod.get("state", "")),
                id=str(pod.get("id", "")),
                created_at=str(pod.get("createdAt", "")),
            )
        )

    return crictl_pods


def load_kubernetes_pods(
    kubectl_command: str,
    node_name: str,
    kubeconfig: str | None,
    context: str | None,
    command_timeout: int,
    quiet: bool,
) -> list[KubernetesPod]:
    command = [
        *kubectl_base_command(kubectl_command, kubeconfig, context),
        "get",
        "pods",
        "--all-namespaces",
        "--field-selector",
        f"spec.nodeName={node_name}",
        "-o",
        "json",
    ]

    log(f"Kubernetes {node_name}: querying scheduled pods", quiet=quiet)
    payload = parse_json(
        run_command(command, timeout=command_timeout),
        shlex.join(command),
    )
    pods = payload.get("items", [])
    if not isinstance(pods, list):
        raise SystemExit("unexpected kubectl JSON: .items is not a list")
    log(f"Kubernetes {node_name}: found {len(pods)} scheduled pods", quiet=quiet)

    k8s_pods: list[KubernetesPod] = []
    for pod in pods:
        if not isinstance(pod, dict):
            continue
        metadata = pod.get("metadata") if isinstance(pod.get("metadata"), dict) else {}
        spec = pod.get("spec") if isinstance(pod.get("spec"), dict) else {}
        status = pod.get("status") if isinstance(pod.get("status"), dict) else {}
        match_uids = kubernetes_pod_match_uids(metadata)
        if not match_uids:
            continue
        k8s_pods.append(
            KubernetesPod(
                uid=match_uids[0],
                match_uids=match_uids,
                namespace=str(metadata.get("namespace", "")),
                name=str(metadata.get("name", "")),
                phase=str(status.get("phase", "")),
                node_name=str(spec.get("nodeName", "")),
            )
        )

    return k8s_pods


def node_addresses(node: dict[str, Any]) -> list[dict[str, str]]:
    status = node.get("status") if isinstance(node.get("status"), dict) else {}
    addresses = status.get("addresses", [])
    if not isinstance(addresses, list):
        return []

    normalized: list[dict[str, str]] = []
    for address in addresses:
        if not isinstance(address, dict):
            continue
        address_type = address.get("type")
        value = address.get("address")
        if isinstance(address_type, str) and isinstance(value, str) and value:
            normalized.append({"type": address_type, "address": value})
    return normalized


def preferred_node_address(
    node: dict[str, Any],
    address_preference: list[str],
) -> tuple[str, str]:
    addresses = node_addresses(node)
    by_type = {address["type"]: address["address"] for address in addresses}
    for address_type in address_preference:
        if address_type in by_type:
            return by_type[address_type], address_type
    return "", ""


def load_kubernetes_nodes(
    kubectl_command: str,
    kubeconfig: str | None,
    context: str | None,
    address_preference: list[str],
    ssh_user: str | None,
    command_timeout: int,
    quiet: bool,
) -> list[NodeTarget]:
    command = [
        *kubectl_base_command(kubectl_command, kubeconfig, context),
        "get",
        "nodes",
        "-o",
        "json",
    ]
    log("Kubernetes inventory: querying node list", quiet=quiet)
    payload = parse_json(
        run_command(command, timeout=command_timeout),
        shlex.join(command),
    )
    nodes = payload.get("items", [])
    if not isinstance(nodes, list):
        raise SystemExit("unexpected kubectl JSON: .items is not a list")
    log(f"Kubernetes inventory: found {len(nodes)} nodes", quiet=quiet)

    targets: list[NodeTarget] = []
    skipped: list[str] = []
    for node in nodes:
        if not isinstance(node, dict):
            continue
        metadata = (
            node.get("metadata") if isinstance(node.get("metadata"), dict) else {}
        )
        node_name = metadata.get("name")
        if not isinstance(node_name, str) or not node_name:
            continue

        address, address_type = preferred_node_address(node, address_preference)
        if not address:
            skipped.append(node_name)
            continue

        ssh_target = f"{ssh_user}@{address}" if ssh_user else address
        targets.append(NodeTarget(node_name, ssh_target, address_type))
        log(
            f"Kubernetes inventory: {node_name} -> {ssh_target} ({address_type})",
            quiet=quiet,
        )

    if skipped:
        print(
            "WARN: skipped nodes with no matching address: " + ", ".join(skipped),
            file=sys.stderr,
        )
    if not targets:
        raise SystemExit("no Kubernetes nodes had a usable SSH address")
    return targets


def format_pod_name(namespace: str, name: str) -> str:
    if namespace and name:
        return f"{namespace}/{name}"
    return name or namespace or "<unknown>"


def print_table(
    title: str,
    headers: list[str],
    rows: list[list[str]],
    *,
    stream: Any = sys.stdout,
) -> None:
    print(title, file=stream)
    if not rows:
        print("  none", file=stream)
        return

    widths = [
        max(len(headers[column]), *(len(row[column]) for row in rows))
        for column in range(len(headers))
    ]
    print(
        "  " + "  ".join(header.ljust(widths[i]) for i, header in enumerate(headers)),
        file=stream,
    )
    print("  " + "  ".join("-" * width for width in widths), file=stream)
    for row in rows:
        print(
            "  " + "  ".join(value.ljust(widths[i]) for i, value in enumerate(row)),
            file=stream,
        )


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "SSH to a node, read CRI pod sandboxes with crictl, and compare them "
            "with pods reported by the Kubernetes API for that node."
        )
    )
    parser.add_argument(
        "ssh_target",
        nargs="?",
        help="SSH target for the node, for example node-01 or ubuntu@node-01.",
    )
    parser.add_argument(
        "--all-nodes",
        action="store_true",
        help="Build SSH inventory from kubectl get nodes and scan every node.",
    )
    parser.add_argument(
        "--ssh-user",
        help="SSH user to prepend to Kubernetes node addresses in --all-nodes mode.",
    )
    parser.add_argument(
        "--node-address-type",
        action="append",
        choices=["InternalIP", "ExternalIP", "Hostname"],
        help=(
            "Node address type preference for --all-nodes. Repeat to set order. "
            "Default: InternalIP, ExternalIP, Hostname."
        ),
    )
    parser.add_argument(
        "--node-name",
        help="Kubernetes node name. Defaults to the SSH host portion of ssh_target.",
    )
    parser.add_argument(
        "--ssh-option",
        action="append",
        default=[],
        help=(
            "Extra SSH option. Repeat as needed, "
            "for example --ssh-option '-i /path/key'."
        ),
    )
    parser.add_argument(
        "--ssh-connect-timeout",
        type=int,
        default=10,
        help="SSH connect timeout in seconds. Default: 10.",
    )
    parser.add_argument(
        "--command-timeout",
        type=int,
        default=120,
        help="Timeout per local or SSH command in seconds. Default: 120.",
    )
    parser.add_argument(
        "--sudo",
        action="store_true",
        help="Run crictl through sudo -n on the remote node.",
    )
    parser.add_argument(
        "--crictl-command",
        default="crictl",
        help="Remote crictl command or absolute path. Default: crictl.",
    )
    parser.add_argument(
        "--kubectl-command",
        default="kubectl",
        help="Local kubectl command or absolute path. Default: kubectl.",
    )
    parser.add_argument(
        "--kubeconfig",
        help="Optional kubeconfig path for kubectl.",
    )
    parser.add_argument(
        "--context",
        help="Optional kubeconfig context for kubectl.",
    )
    parser.add_argument(
        "--include-notready",
        action="store_true",
        help="Include CRI pod sandboxes whose state is not SANDBOX_READY.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Compatibility alias for --format json.",
    )
    parser.add_argument(
        "--format",
        choices=["text", "json"],
        default="text",
        help="Output format. Default: text.",
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="Suppress progress logs on stderr.",
    )
    parser.add_argument(
        "--no-fail",
        action="store_true",
        help="Always exit 0, even when rogue pods are found.",
    )
    return parser.parse_args(argv)


def ssh_host_from_target(ssh_target: str) -> str:
    host = ssh_target.rsplit("@", 1)[-1]
    return host.split(":", 1)[0]


def expand_ssh_options(options: list[str]) -> list[str]:
    expanded: list[str] = []
    for option in options:
        expanded.extend(shlex.split(option))
    return expanded


def scan_node(
    node_name: str,
    ssh_target: str,
    args: argparse.Namespace,
    ssh_options: list[str],
) -> ScanResult:
    log(f"{node_name}: starting scan via {ssh_target}", quiet=args.quiet)
    crictl_pods = load_crictl_pods(
        ssh_target,
        ssh_options,
        args.crictl_command,
        args.sudo,
        args.command_timeout,
        args.ssh_connect_timeout,
        args.quiet,
    )
    if not args.include_notready:
        before_filter = len(crictl_pods)
        crictl_pods = [pod for pod in crictl_pods if pod.state == "SANDBOX_READY"]
        log(
            f"{node_name}: using {len(crictl_pods)} ready CRI pod sandboxes "
            f"({before_filter - len(crictl_pods)} non-ready filtered)",
            quiet=args.quiet,
        )
    else:
        log(
            f"{node_name}: using {len(crictl_pods)} CRI pod sandboxes "
            "including non-ready states",
            quiet=args.quiet,
        )

    k8s_pods = load_kubernetes_pods(
        args.kubectl_command,
        node_name,
        args.kubeconfig,
        args.context,
        args.command_timeout,
        args.quiet,
    )

    crictl_by_uid = {pod.uid: pod for pod in crictl_pods}
    k8s_match_uids = {match_uid for pod in k8s_pods for match_uid in pod.match_uids}
    crictl_uids = set(crictl_by_uid)

    rogue_uids = sorted(crictl_uids - k8s_match_uids)
    missing_on_node_uids = sorted(
        pod.uid
        for pod in k8s_pods
        if not any(match_uid in crictl_uids for match_uid in pod.match_uids)
    )
    log(
        f"{node_name}: comparison complete, rogue={len(rogue_uids)}, "
        f"k8s_missing_on_node={len(missing_on_node_uids)}",
        quiet=args.quiet,
    )
    return ScanResult(
        node_name=node_name,
        ssh_target=ssh_target,
        crictl_pods=crictl_pods,
        kubernetes_pods=k8s_pods,
        rogue_uids=rogue_uids,
        missing_on_node_uids=missing_on_node_uids,
    )


def result_to_json(result: ScanResult) -> dict[str, Any]:
    crictl_by_uid = {pod.uid: pod for pod in result.crictl_pods}
    k8s_by_uid = {pod.uid: pod for pod in result.kubernetes_pods}
    payload: dict[str, Any] = {
        "node": result.node_name,
        "ssh_target": result.ssh_target,
        "summary": {
            "crictl_pods": len(result.crictl_pods),
            "kubernetes_pods": len(result.kubernetes_pods),
            "rogue_pods": len(result.rogue_uids),
            "kubernetes_pods_missing_on_node": len(result.missing_on_node_uids),
        },
    }
    if result.error:
        payload["error"] = result.error
        return payload

    payload["rogue_pods"] = [
        crictl_by_uid[uid].__dict__
        | {
            "display_name": format_pod_name(
                crictl_by_uid[uid].namespace,
                crictl_by_uid[uid].name,
            )
        }
        for uid in result.rogue_uids
    ]
    payload["kubernetes_pods_missing_on_node"] = [
        k8s_by_uid[uid].__dict__
        | {
            "display_name": format_pod_name(
                k8s_by_uid[uid].namespace,
                k8s_by_uid[uid].name,
            )
        }
        for uid in result.missing_on_node_uids
    ]
    return payload


def print_result(result: ScanResult) -> None:
    if result.error:
        print(f"Node: {result.node_name}")
        print(f"SSH target: {result.ssh_target}")
        print(f"ERROR: {result.error}", file=sys.stderr)
        print()
        return

    crictl_by_uid = {pod.uid: pod for pod in result.crictl_pods}
    k8s_by_uid = {pod.uid: pod for pod in result.kubernetes_pods}

    print(f"Node: {result.node_name}")
    print(f"SSH target: {result.ssh_target}")
    print(
        "Summary: "
        f"crictl={len(result.crictl_pods)} "
        f"kubernetes={len(result.kubernetes_pods)} "
        f"rogue={len(result.rogue_uids)} "
        f"k8s_missing_on_node={len(result.missing_on_node_uids)}"
    )
    print()
    print_table(
        "Rogue CRI pod sandboxes present on node but absent from Kubernetes:",
        ["pod", "uid", "state", "sandbox_id", "attempt"],
        [
            [
                format_pod_name(pod.namespace, pod.name),
                pod.uid,
                pod.state,
                pod.id[:16],
                "" if pod.attempt is None else str(pod.attempt),
            ]
            for pod in (crictl_by_uid[uid] for uid in result.rogue_uids)
        ],
        stream=sys.stderr if result.rogue_uids else sys.stdout,
    )
    print()
    print_table(
        "Kubernetes pods scheduled to node but absent from ready CRI sandboxes:",
        ["pod", "uid", "phase"],
        [
            [
                format_pod_name(pod.namespace, pod.name),
                pod.uid,
                pod.phase,
            ]
            for pod in (k8s_by_uid[uid] for uid in result.missing_on_node_uids)
        ],
    )
    print()


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    if args.all_nodes and args.ssh_target:
        raise SystemExit("pass either --all-nodes or ssh_target, not both")
    if args.ssh_user and not args.all_nodes:
        raise SystemExit("--ssh-user only applies with --all-nodes")
    if args.node_address_type and not args.all_nodes:
        raise SystemExit("--node-address-type only applies with --all-nodes")
    if args.node_name and args.all_nodes:
        raise SystemExit("--node-name only applies when scanning one ssh_target")
    if not args.all_nodes and not args.ssh_target:
        raise SystemExit("ssh_target is required unless --all-nodes is used")

    ssh_options = expand_ssh_options(args.ssh_option)
    address_preference = args.node_address_type or [
        "InternalIP",
        "ExternalIP",
        "Hostname",
    ]

    if args.all_nodes:
        targets = load_kubernetes_nodes(
            args.kubectl_command,
            args.kubeconfig,
            args.context,
            address_preference,
            args.ssh_user,
            args.command_timeout,
            args.quiet,
        )
    else:
        assert args.ssh_target is not None
        targets = [
            NodeTarget(
                args.node_name or ssh_host_from_target(args.ssh_target),
                args.ssh_target,
                "ssh_target",
            )
        ]
        log(
            f"Single-node inventory: {targets[0].node_name} -> {targets[0].ssh_target}",
            quiet=args.quiet,
        )

    log(f"Inventory ready: scanning {len(targets)} node(s)", quiet=args.quiet)

    results: list[ScanResult] = []
    for target in targets:
        try:
            results.append(
                scan_node(target.node_name, target.ssh_target, args, ssh_options)
            )
        except SystemExit as exc:
            log(f"{target.node_name}: scan failed: {exc}", quiet=args.quiet)
            results.append(
                ScanResult(
                    node_name=target.node_name,
                    ssh_target=target.ssh_target,
                    crictl_pods=[],
                    kubernetes_pods=[],
                    rogue_uids=[],
                    missing_on_node_uids=[],
                    error=str(exc),
                )
            )

    log(
        "Scan finished: "
        f"nodes={len(results)} "
        f"failed={sum(1 for result in results if result.error)} "
        f"rogue={sum(len(result.rogue_uids) for result in results)} "
        "k8s_missing_on_node="
        f"{sum(len(result.missing_on_node_uids) for result in results)}",
        quiet=args.quiet,
    )

    if args.json or args.format == "json":
        summary = {
            "nodes_scanned": len(results),
            "nodes_failed": sum(1 for result in results if result.error),
            "rogue_pods": sum(len(result.rogue_uids) for result in results),
            "kubernetes_pods_missing_on_node": sum(
                len(result.missing_on_node_uids) for result in results
            ),
        }
        print(
            json.dumps(
                {
                    "summary": summary,
                    "nodes": [result_to_json(result) for result in results],
                },
                indent=2,
                sort_keys=True,
            )
        )
    else:
        for result in results:
            print_result(result)
        print(
            "Cluster summary: "
            f"nodes={len(results)} "
            f"failed={sum(1 for result in results if result.error)} "
            f"rogue={sum(len(result.rogue_uids) for result in results)} "
            "k8s_missing_on_node="
            f"{sum(len(result.missing_on_node_uids) for result in results)}"
        )

    has_errors = any(result.error for result in results)
    has_rogue_pods = any(result.rogue_uids for result in results)
    if has_errors:
        return EXIT_ERROR
    if has_rogue_pods and not args.no_fail:
        return EXIT_FINDINGS
    return EXIT_OK


if __name__ == "__main__":
    raise SystemExit(main())
