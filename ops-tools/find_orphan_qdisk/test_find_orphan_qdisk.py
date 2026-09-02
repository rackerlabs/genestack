#!/usr/bin/env python3
"""Tests for find_orphan_qdisk.py."""

from __future__ import annotations

import importlib.util
import pathlib
import sys
import unittest
from unittest import mock

SCRIPT = pathlib.Path(__file__).with_name("find_orphan_qdisk.py")
SPEC = importlib.util.spec_from_file_location("find_orphan_qdisk", SCRIPT)
assert SPEC and SPEC.loader
find_orphan_qdisk = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = find_orphan_qdisk
SPEC.loader.exec_module(find_orphan_qdisk)


class FakeKubectl:
    def __init__(
        self,
        responses: dict[
            tuple[str, ...],
            find_orphan_qdisk.CommandResult | list[find_orphan_qdisk.CommandResult],
        ],
    ) -> None:
        self.responses = responses
        self.exec_calls: list[tuple[str, ...]] = []

    def exec(self, pod: str, remote_cmd: list[str]) -> find_orphan_qdisk.CommandResult:
        del pod
        key = tuple(remote_cmd)
        self.exec_calls.append(key)
        response = self.responses.get(key, find_orphan_qdisk.CommandResult(0, "", ""))
        if isinstance(response, list):
            return response.pop(0)
        return response


class QdiscParserTest(unittest.TestCase):
    def test_parse_ingress_qdiscs_ignores_root_qdiscs(self) -> None:
        output = """\
qdisc fq_codel 0: dev tapf52ad2bd-cc root refcnt 2 limit 10240p
 Sent 11387262282 bytes 64335642 pkt
qdisc noqueue 80d4: dev tap9b25c261-b5 root refcnt 257
 Sent 0 bytes 0 pkt
qdisc ingress ffff: dev tap142d9788-2c parent ffff:fff1 ----------------
 Sent 0 bytes 0 pkt
qdisc fq_codel 0: dev eth0 root refcnt 2 limit 10240p
"""

        self.assertEqual(
            find_orphan_qdisk.parse_ingress_qdiscs(output),
            {
                "tap142d9788-2c": [
                    "qdisc ingress ffff: dev tap142d9788-2c parent ffff:fff1 ----------------",
                    " Sent 0 bytes 0 pkt",
                ]
            },
        )

    def test_audit_pod_flags_only_ingress_taps_not_claimed_by_libvirt(self) -> None:
        tc_output = """\
qdisc ingress ffff: dev tap-owned parent ffff:fff1 ----------------
 Sent 0 bytes 0 pkt
qdisc ingress ffff: dev tap-stale parent ffff:fff1 ----------------
 Sent 0 bytes 0 pkt
qdisc fq_codel 0: dev tap-root-only root refcnt 2 limit 10240p
 Sent 1 bytes 1 pkt
"""
        virsh_output = """\
Interface  Type       Source     Model       MAC
-------------------------------------------------------
tap-owned  bridge     br-int     virtio      fa:16:3e:00:00:01
"""
        ovs_output = "tap-owned\ntap-stale\n"
        kubectl = FakeKubectl(
            {
                ("tc", "-s", "qdisc", "show"): find_orphan_qdisk.CommandResult(
                    0, tc_output, ""
                ),
                (
                    "bash",
                    "-c",
                    find_orphan_qdisk.VIRSH_DOMAIN_INTERFACE_SCRIPT,
                ): find_orphan_qdisk.CommandResult(
                    0,
                    virsh_output,
                    "",
                ),
                (
                    "bash",
                    "-c",
                    find_orphan_qdisk.OVS_PORT_SCRIPT,
                ): find_orphan_qdisk.CommandResult(
                    0,
                    ovs_output,
                    "",
                ),
            }
        )

        result = find_orphan_qdisk.audit_pod(
            kubectl, "pod/libvirt", fix=False, tap_filter=None
        )
        findings = {finding.tap: finding for finding in result.findings}

        self.assertEqual(result.status, "stale_found")
        self.assertEqual(result.stale_count, 1)
        self.assertEqual(result.in_use_ingress_count, 1)
        self.assertNotIn("tap-root-only", findings)
        self.assertEqual(findings["tap-owned"].status, "in_use")
        self.assertEqual(findings["tap-stale"].status, "stale")
        self.assertTrue(findings["tap-stale"].present_in_ovs)

    def test_audit_pod_fails_closed_when_virsh_inventory_fails(self) -> None:
        kubectl = FakeKubectl(
            {
                ("tc", "-s", "qdisc", "show"): find_orphan_qdisk.CommandResult(
                    0,
                    "qdisc ingress ffff: dev tap-stale parent ffff:fff1 ----------------\n",
                    "",
                ),
                (
                    "bash",
                    "-c",
                    find_orphan_qdisk.VIRSH_DOMAIN_INTERFACE_SCRIPT,
                ): find_orphan_qdisk.CommandResult(1, "", "virsh failed"),
            }
        )

        with self.assertRaisesRegex(find_orphan_qdisk.AuditError, "virsh"):
            find_orphan_qdisk.audit_pod(
                kubectl, "pod/libvirt", fix=True, tap_filter=None
            )
        self.assertNotIn(
            ("tc", "qdisc", "del", "dev", "tap-stale", "ingress"),
            kubectl.exec_calls,
        )

    def test_fix_revalidates_candidate_before_delete(self) -> None:
        tc_output = (
            "qdisc ingress ffff: dev tap-race parent ffff:fff1 ----------------\n"
        )
        kubectl = FakeKubectl(
            {
                ("tc", "-s", "qdisc", "show"): [
                    find_orphan_qdisk.CommandResult(0, tc_output, ""),
                    find_orphan_qdisk.CommandResult(0, tc_output, ""),
                ],
                (
                    "bash",
                    "-c",
                    find_orphan_qdisk.VIRSH_DOMAIN_INTERFACE_SCRIPT,
                ): [
                    find_orphan_qdisk.CommandResult(0, "", ""),
                    find_orphan_qdisk.CommandResult(0, "tap-race\n", ""),
                ],
                (
                    "bash",
                    "-c",
                    find_orphan_qdisk.OVS_PORT_SCRIPT,
                ): find_orphan_qdisk.CommandResult(0, "", ""),
            }
        )

        result = find_orphan_qdisk.audit_pod(
            kubectl, "pod/libvirt", fix=True, tap_filter=None
        )

        self.assertEqual(result.findings[0].status, "in_use")
        self.assertFalse(result.findings[0].cleanup_attempted)
        self.assertNotIn(
            ("tc", "qdisc", "del", "dev", "tap-race", "ingress"),
            kubectl.exec_calls,
        )

    def test_result_exit_code_reports_stale_findings_in_dry_run(self) -> None:
        result = find_orphan_qdisk.AuditResult(
            namespace="openstack",
            label_selector="application=libvirt",
            container="libvirt",
            fix=False,
            started_at="2026-09-02T00:00:00Z",
            duration_seconds=0.1,
            pods_scanned=1,
            stale_count=1,
            in_use_ingress_count=0,
            error_count=0,
            cleanup_failed_count=0,
            results=[],
        )

        self.assertEqual(
            find_orphan_qdisk.result_exit_code(result),
            find_orphan_qdisk.EXIT_STALE_FOUND,
        )

    def test_result_exit_code_allows_fixed_stale_findings(self) -> None:
        result = find_orphan_qdisk.AuditResult(
            namespace="openstack",
            label_selector="application=libvirt",
            container="libvirt",
            fix=True,
            started_at="2026-09-02T00:00:00Z",
            duration_seconds=0.1,
            pods_scanned=1,
            stale_count=1,
            in_use_ingress_count=0,
            error_count=0,
            cleanup_failed_count=0,
            results=[],
        )

        self.assertEqual(
            find_orphan_qdisk.result_exit_code(result), find_orphan_qdisk.EXIT_OK
        )

    def test_fix_requires_yes_im_really_sure(self) -> None:
        with mock.patch.object(sys, "argv", ["find_orphan_qdisk.py", "--fix"]):
            self.assertEqual(find_orphan_qdisk.main(), find_orphan_qdisk.EXIT_ERROR)

    def test_yes_im_really_sure_confirms_fix(self) -> None:
        result = find_orphan_qdisk.AuditResult(
            namespace="openstack",
            label_selector="application=libvirt",
            container="libvirt",
            fix=True,
            started_at="2026-09-02T00:00:00Z",
            duration_seconds=0.1,
            pods_scanned=0,
            stale_count=0,
            in_use_ingress_count=0,
            error_count=0,
            cleanup_failed_count=0,
            results=[],
        )

        with (
            mock.patch.object(
                sys,
                "argv",
                ["find_orphan_qdisk.py", "--fix", "--yes-im-really-sure"],
            ),
            mock.patch.object(
                find_orphan_qdisk, "build_audit_result", return_value=result
            ),
            mock.patch.object(find_orphan_qdisk, "print_text"),
        ):
            self.assertEqual(find_orphan_qdisk.main(), find_orphan_qdisk.EXIT_OK)


if __name__ == "__main__":
    unittest.main()
