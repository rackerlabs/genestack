#!/usr/bin/env python3
"""Unit tests for rogue_pod_scanner.py."""

from __future__ import annotations

import importlib.util
import pathlib
import sys
import unittest
from unittest import mock

SCRIPT = pathlib.Path(__file__).with_name("rogue_pod_scanner.py")
SPEC = importlib.util.spec_from_file_location("rogue_pod_scanner", SCRIPT)
assert SPEC and SPEC.loader
module = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = module
SPEC.loader.exec_module(module)


class RoguePodScannerTests(unittest.TestCase):
    def test_parse_json_requires_object(self) -> None:
        with self.assertRaises(SystemExit):
            module.parse_json("[]", "test")

    def test_format_json_returns_success_without_findings(self) -> None:
        result = module.ScanResult(
            node_name="node-01",
            ssh_target="node-01",
            crictl_pods=[],
            kubernetes_pods=[],
            rogue_uids=[],
            missing_on_node_uids=[],
        )
        with mock.patch.object(module, "scan_node", return_value=result), mock.patch(
            "sys.stdout"
        ):
            self.assertEqual(
                module.main(["node-01", "--format", "json", "--quiet"]),
                module.EXIT_OK,
            )

    def test_rogue_pods_return_findings_exit_code(self) -> None:
        pod = module.CrictlPod(
            uid="uid-1",
            namespace="default",
            name="stale",
            attempt=0,
            state="SANDBOX_READY",
            id="sandbox-id",
            created_at="",
        )
        result = module.ScanResult(
            node_name="node-01",
            ssh_target="node-01",
            crictl_pods=[pod],
            kubernetes_pods=[],
            rogue_uids=["uid-1"],
            missing_on_node_uids=[],
        )
        with mock.patch.object(module, "scan_node", return_value=result), mock.patch(
            "sys.stdout"
        ), mock.patch("sys.stderr"):
            self.assertEqual(
                module.main(["node-01", "--format", "json", "--quiet"]),
                module.EXIT_FINDINGS,
            )


if __name__ == "__main__":
    unittest.main()
