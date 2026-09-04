#!/usr/bin/env python3
"""Audit stale libvirt tap ingress qdiscs that can block Nova spawns.

Nova/libvirt may fail instance start with:

    tc qdisc add dev tap<id> ingress
    Error: Exclusivity flag on, cannot modify.

That failure means an ingress qdisc already exists on the tap device at the
time Nova tries to add it. This tool finds tap devices with ingress qdiscs that
are not claimed by any running libvirt domain. By default it is read-only.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import time
from dataclasses import asdict, dataclass, field

EXIT_OK = 0
EXIT_ERROR = 1
EXIT_STALE_FOUND = 2
EXIT_CLEANUP_FAILED = 3

TAP_RE = re.compile(r"\btap[A-Za-z0-9_.-]+")
QDISC_DEV_RE = re.compile(r"\bdev\s+(\S+)")
VIRSH_DOMAIN_INTERFACE_SCRIPT = r"""
if ! command -v virsh >/dev/null 2>&1; then
    echo "virsh not found" >&2
    exit 1
fi

domain_list=$(virsh list --name 2>&1) || {
    printf '%s\n' "$domain_list" >&2
    exit 1
}

while IFS= read -r domain; do
    [ -n "$domain" ] || continue
    virsh domiflist "$domain" || exit 1
done <<< "$domain_list"
"""
OVS_PORT_SCRIPT = (
    "command -v ovs-vsctl >/dev/null 2>&1 && ovs-vsctl list-ports br-int || true"
)


@dataclass
class CommandResult:
    returncode: int
    stdout: str
    stderr: str
    timed_out: bool = False


@dataclass
class TapFinding:
    tap: str
    status: str
    reason: str
    qdisc: list[str] = field(default_factory=list)
    present_in_ovs: bool = False
    cleanup_attempted: bool = False
    cleanup_succeeded: bool | None = None


@dataclass
class PodResult:
    pod: str
    status: str
    findings: list[TapFinding] = field(default_factory=list)
    error: str | None = None
    stale_count: int = 0
    in_use_ingress_count: int = 0
    checked_tap_count: int = 0


@dataclass
class AuditResult:
    namespace: str
    label_selector: str
    container: str | None
    fix: bool
    started_at: str
    duration_seconds: float
    pods_scanned: int
    stale_count: int
    in_use_ingress_count: int
    error_count: int
    cleanup_failed_count: int
    results: list[PodResult]


class AuditError(RuntimeError):
    pass


def run(cmd: list[str], timeout: int) -> CommandResult:
    try:
        proc = subprocess.run(cmd, text=True, capture_output=True, timeout=timeout)
        return CommandResult(proc.returncode, proc.stdout, proc.stderr)
    except subprocess.TimeoutExpired as exc:
        stdout = exc.stdout if isinstance(exc.stdout, str) else ""
        stderr = exc.stderr if isinstance(exc.stderr, str) else ""
        return CommandResult(
            124, stdout, stderr or f"command timed out after {timeout}s", True
        )


def clean_kubectl_noise(text: str) -> str:
    lines = []
    for line in text.splitlines():
        if line.startswith("Defaulted container "):
            continue
        if "Error: Peer netns" in line:
            continue
        lines.append(line)
    return "\n".join(lines).strip()


class Kubectl:
    def __init__(
        self,
        namespace: str,
        container: str | None,
        request_timeout: str,
        command_timeout: int,
    ) -> None:
        self.namespace = namespace
        self.container = container
        self.request_timeout = request_timeout
        self.command_timeout = command_timeout

    def base(self) -> list[str]:
        return [
            "kubectl",
            f"--request-timeout={self.request_timeout}",
            "-n",
            self.namespace,
        ]

    def get(self, args: list[str]) -> CommandResult:
        return run([*self.base(), *args], timeout=self.command_timeout)

    def exec(self, pod: str, remote_cmd: list[str]) -> CommandResult:
        cmd = [*self.base(), "exec", pod]
        if self.container:
            cmd.extend(["-c", self.container])
        cmd.extend(["--", *remote_cmd])
        return run(cmd, timeout=self.command_timeout)


def require_kubectl() -> None:
    if not shutil.which("kubectl"):
        raise AuditError("required command 'kubectl' is not installed or not in PATH")


def checked(result: CommandResult, action: str) -> CommandResult:
    if result.returncode != 0:
        detail = clean_kubectl_noise(result.stderr) or clean_kubectl_noise(
            result.stdout
        )
        if result.timed_out:
            detail = detail or "command timed out"
        raise AuditError(f"{action} failed: {detail}")
    return result


def normalize_pod_name(pod: str) -> str:
    return pod if pod.startswith("pod/") else f"pod/{pod}"


def get_libvirt_pods(
    kubectl: Kubectl, label_selector: str, target_node: str | None
) -> list[str]:
    args = ["get", "pods", "-l", label_selector, "-o", "name"]
    if target_node:
        args.extend(["--field-selector", f"spec.nodeName={target_node}"])

    result = kubectl.get(args)
    pods = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    if pods or result.returncode == 0:
        return pods

    fallback = checked(
        kubectl.get(["get", "pods", "-o", "wide", "--no-headers"]),
        "pod discovery fallback",
    )
    pods = []
    for line in fallback.stdout.splitlines():
        fields = line.split()
        if len(fields) < 7 or "libvirt" not in fields[0]:
            continue
        if target_node and fields[6] != target_node:
            continue
        pods.append(f"pod/{fields[0]}")
    return pods


def parse_ingress_qdiscs(tc_output: str) -> dict[str, list[str]]:
    qdiscs: dict[str, list[str]] = {}
    current_dev: str | None = None
    current_block: list[str] = []

    def flush() -> None:
        if current_dev and current_dev.startswith("tap") and current_block:
            qdiscs.setdefault(current_dev, []).extend(current_block)

    for line in tc_output.splitlines():
        if line.startswith("qdisc "):
            flush()
            match = QDISC_DEV_RE.search(line)
            current_dev = match.group(1) if match else None
            current_block = [line]
        elif current_block:
            current_block.append(line)
    flush()

    return {
        dev: lines
        for dev, lines in qdiscs.items()
        if any(line.startswith("qdisc ingress ") for line in lines)
    }


def get_ingress_qdiscs_by_tap(kubectl: Kubectl, pod: str) -> dict[str, list[str]]:
    result = checked(kubectl.exec(pod, ["tc", "-s", "qdisc", "show"]), "tc qdisc scan")
    return parse_ingress_qdiscs(result.stdout)


def get_ingress_qdisc_taps(kubectl: Kubectl, pod: str) -> set[str]:
    return set(get_ingress_qdiscs_by_tap(kubectl, pod))


def get_running_domain_interface_taps(kubectl: Kubectl, pod: str) -> set[str]:
    result = checked(
        kubectl.exec(pod, ["bash", "-c", VIRSH_DOMAIN_INTERFACE_SCRIPT]),
        "virsh domiflist scan",
    )
    return set(TAP_RE.findall(result.stdout))


def get_ovs_ports(kubectl: Kubectl, pod: str) -> set[str]:
    result = kubectl.exec(pod, ["bash", "-c", OVS_PORT_SCRIPT])
    return {
        line.strip()
        for line in result.stdout.splitlines()
        if line.strip().startswith("tap")
    }


def delete_ingress_qdisc(kubectl: Kubectl, pod: str, dev: str) -> bool:
    result = kubectl.exec(pod, ["tc", "qdisc", "del", "dev", dev, "ingress"])
    return result.returncode == 0


def revalidate_stale_tap(
    kubectl: Kubectl, pod: str, dev: str
) -> tuple[bool, str, str, list[str]]:
    qdiscs = get_ingress_qdiscs_by_tap(kubectl, pod)
    qdisc = qdiscs.get(dev, [])
    if not qdisc:
        return False, "ok", "ingress qdisc no longer exists", []

    domain_taps = get_running_domain_interface_taps(kubectl, pod)
    if dev in domain_taps:
        return False, "in_use", "tap is now claimed by virsh", qdisc

    return (
        True,
        "stale",
        "ingress qdisc exists and tap is not claimed by a running libvirt domain",
        qdisc,
    )


def audit_pod(
    kubectl: Kubectl, pod: str, fix: bool, tap_filter: set[str] | None
) -> PodResult:
    qdiscs = get_ingress_qdiscs_by_tap(kubectl, pod)
    ingress_taps = set(qdiscs)
    domain_taps = get_running_domain_interface_taps(kubectl, pod)
    ovs_ports = get_ovs_ports(kubectl, pod)

    candidate_taps = ingress_taps
    findings: list[TapFinding] = []

    if tap_filter:
        missing_qdisc_taps = sorted(tap_filter - candidate_taps)
        candidate_taps &= tap_filter
        for dev in missing_qdisc_taps:
            if dev in domain_taps:
                status = "in_use"
                reason = "claimed by virsh; no ingress qdisc conflict shown by tc"
            else:
                status = "ok"
                reason = "no ingress qdisc conflict shown by tc"
            findings.append(
                TapFinding(
                    tap=dev,
                    status=status,
                    reason=reason,
                    present_in_ovs=dev in ovs_ports,
                )
            )

    for dev in sorted(candidate_taps):
        if dev in domain_taps:
            findings.append(
                TapFinding(
                    tap=dev,
                    status="in_use",
                    reason="claimed by virsh; ingress qdisc exists",
                    qdisc=qdiscs[dev],
                    present_in_ovs=dev in ovs_ports,
                )
            )
            continue

        finding = TapFinding(
            tap=dev,
            status="stale",
            reason="ingress qdisc exists and tap is not claimed by a running libvirt domain",
            qdisc=qdiscs[dev],
            present_in_ovs=dev in ovs_ports,
        )
        if fix:
            safe_to_delete, status, reason, qdisc = revalidate_stale_tap(
                kubectl, pod, dev
            )
            finding.reason = reason
            finding.qdisc = qdisc
            if not safe_to_delete:
                finding.status = status
                findings.append(finding)
                continue

            finding.cleanup_attempted = True
            finding.cleanup_succeeded = delete_ingress_qdisc(kubectl, pod, dev)
            if not finding.cleanup_succeeded:
                finding.status = "cleanup_failed"
        findings.append(finding)

    stale_count = sum(
        1 for finding in findings if finding.status in {"stale", "cleanup_failed"}
    )
    cleanup_failed = any(finding.status == "cleanup_failed" for finding in findings)
    status = (
        "cleanup_failed" if cleanup_failed else "stale_found" if stale_count else "ok"
    )

    return PodResult(
        pod=pod,
        status=status,
        findings=findings,
        stale_count=stale_count,
        in_use_ingress_count=sum(
            1 for finding in findings if finding.status == "in_use" and finding.qdisc
        ),
        checked_tap_count=len(candidate_taps),
    )


def build_audit_result(args: argparse.Namespace) -> AuditResult:
    require_kubectl()
    start = time.time()
    started_at = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(start))

    kubectl = Kubectl(
        args.namespace,
        args.container,
        args.kubectl_request_timeout,
        args.command_timeout,
    )
    if args.pod:
        pods = [normalize_pod_name(pod) for pod in args.pod]
    else:
        pods = get_libvirt_pods(kubectl, args.label_selector, args.node)

    if not pods:
        target = (
            f" on node {args.node}" if args.node else f" in namespace {args.namespace}"
        )
        raise AuditError(f"no libvirt pods found{target}")

    tap_filter = set(args.tap) if args.tap else None
    results: list[PodResult] = []
    for pod in pods:
        try:
            results.append(audit_pod(kubectl, pod, args.fix, tap_filter))
        except AuditError as exc:
            results.append(PodResult(pod=pod, status="error", error=str(exc)))

    return AuditResult(
        namespace=args.namespace,
        label_selector=args.label_selector,
        container=args.container,
        fix=args.fix,
        started_at=started_at,
        duration_seconds=round(time.time() - start, 3),
        pods_scanned=len(results),
        stale_count=sum(result.stale_count for result in results),
        in_use_ingress_count=sum(result.in_use_ingress_count for result in results),
        error_count=sum(1 for result in results if result.status == "error"),
        cleanup_failed_count=sum(
            1
            for result in results
            for finding in result.findings
            if finding.status == "cleanup_failed"
        ),
        results=results,
    )


def result_exit_code(result: AuditResult) -> int:
    if result.error_count:
        return EXIT_ERROR
    if result.cleanup_failed_count:
        return EXIT_CLEANUP_FAILED
    if result.stale_count and not result.fix:
        return EXIT_STALE_FOUND
    return EXIT_OK


def print_text(result: AuditResult, args: argparse.Namespace) -> None:
    print("=== Stale tap qdisc audit ===")
    if args.pod:
        print(f"Mode: Explicit pod list ({len(args.pod)} pod(s))")
    elif args.node:
        print(f"Mode: Single node ({args.node})")
    else:
        print("Mode: Entire cluster")
    print(f"Namespace: {result.namespace}")
    print(f"Label selector: {result.label_selector}")
    print(f"Container: {result.container or '<kubectl default>'}")
    print(f"Fix mode: {'ON' if result.fix else 'OFF (dry-run)'}")
    if args.tap:
        print(f"Tap filter: {', '.join(args.tap)}")
    print()

    print(f"Found {result.pods_scanned} libvirt pod(s):")
    for pod_result in result.results:
        print(pod_result.pod)
    print()

    for pod_result in result.results:
        print(f"--- {pod_result.pod} ---")
        if pod_result.status == "error":
            print(f"ERROR: {pod_result.error}")
            continue
        if not pod_result.findings:
            print("OK: No stale tap ingress qdiscs found")
            continue

        emitted_stale = False
        for finding in pod_result.findings:
            if finding.status == "ok":
                print(f"OK: {finding.tap} ({finding.reason})")
            elif finding.status == "in_use":
                print(f"IN_USE: {finding.tap} ({finding.reason})")
            else:
                emitted_stale = True
                ovs_note = "present-in-ovs" if finding.present_in_ovs else "not-in-ovs"
                print(f"TC_EXCL_CONFLICT: {finding.tap} has an existing ingress qdisc")
                print(f"STALE: {finding.tap} ({ovs_note}, not claimed by virsh)")
                for line in finding.qdisc[:3]:
                    print(line)
                if finding.cleanup_attempted:
                    outcome = "succeeded" if finding.cleanup_succeeded else "failed"
                    print(f"  -> cleanup {outcome}")

        if not emitted_stale and not args.tap:
            print("OK: No stale tap ingress qdiscs found")

    print("=== Audit complete ===")
    print(
        "Summary: "
        f"pods={result.pods_scanned} "
        f"stale={result.stale_count} "
        f"in_use_ingress={result.in_use_ingress_count} "
        f"errors={result.error_count} "
        f"cleanup_failed={result.cleanup_failed_count} "
        f"duration_seconds={result.duration_seconds}"
    )
    if result.fix:
        print("Stale ingress qdiscs have been cleaned where possible.")
    else:
        print("=== Run with --fix --yes-im-really-sure to apply remediation ===")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Audit stale libvirt tap ingress qdiscs."
    )
    parser.add_argument(
        "--namespace",
        default="openstack",
        help="Kubernetes namespace containing libvirt pods",
    )
    parser.add_argument(
        "--label-selector",
        default="application=libvirt",
        help="libvirt pod label selector",
    )
    parser.add_argument(
        "--container",
        default="libvirt",
        help="container to exec inside the libvirt pod",
    )
    parser.add_argument(
        "--kubectl-request-timeout", default="30s", help="kubectl API request timeout"
    )
    parser.add_argument(
        "--command-timeout",
        type=int,
        default=60,
        help="local timeout per kubectl command in seconds",
    )
    parser.add_argument(
        "--format", choices=("text", "json"), default="text", help="output format"
    )
    parser.add_argument(
        "--fix", action="store_true", help="delete stale ingress qdiscs"
    )
    parser.add_argument(
        "--yes-im-really-sure",
        action="store_true",
        help="required with --fix to delete stale ingress qdiscs",
    )
    parser.add_argument("--node", help="limit audit to one Kubernetes node")
    parser.add_argument(
        "--pod",
        action="append",
        help="audit one libvirt pod; may be passed more than once",
    )
    parser.add_argument(
        "--tap",
        action="append",
        help="audit one tap device from a Nova error; may be passed more than once",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    if args.fix and not args.yes_im_really_sure:
        print("ERROR: --fix requires --yes-im-really-sure", file=sys.stderr)
        return EXIT_ERROR

    try:
        result = build_audit_result(args)
    except AuditError as exc:
        if args.format == "json":
            print(json.dumps({"status": "error", "error": str(exc)}, sort_keys=True))
        else:
            print(f"ERROR: {exc}", file=sys.stderr)
        return EXIT_ERROR

    if args.format == "json":
        print(json.dumps(asdict(result), sort_keys=True))
    else:
        print_text(result, args)

    return result_exit_code(result)


if __name__ == "__main__":
    sys.exit(main())
