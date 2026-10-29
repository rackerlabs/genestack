#!/usr/bin/env python3
import argparse
import pathlib
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import find_orphan_amphora


class FindOrphanAmphoraTests(unittest.TestCase):
    def test_normalize_fixed_ips_handles_openstack_port_shape(self):
        self.assertEqual(
            find_orphan_amphora.normalize_fixed_ips(
                [
                    {"ip_address": "172.16.29.10", "subnet_id": "subnet-a"},
                    {"ip_address": "172.16.29.11", "subnet_id": "subnet-b"},
                ]
            ),
            "172.16.29.10,172.16.29.11",
        )

    def test_fix_requires_operator_confirmation(self):
        args = argparse.Namespace(fix=True, yes_im_really_sure=False)
        with self.assertRaisesRegex(
            find_orphan_amphora.OpsError,
            "--yes-im-really-sure",
        ):
            find_orphan_amphora.validate_fix_args(args)

    def test_aggregate_candidate_without_management_port_is_manual_review(self):
        candidate = find_orphan_amphora.candidate_from_rows(
            "11111111-2222-3333-4444-555555555555",
            "aggregate:octavia",
            {
                "name": "amphora-old",
                "status": "ACTIVE",
                "OS-EXT-SRV-ATTR:host": "compute-1",
                "created": "2026-10-01T00:00:00Z",
            },
            "",
            None,
            "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
        )
        self.assertFalse(candidate["fixable"])

    def test_candidate_with_management_port_is_fixable(self):
        network_id = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        candidate = find_orphan_amphora.candidate_from_rows(
            "11111111-2222-3333-4444-555555555555",
            "management-network:lb-mgmt-net",
            {"name": "amphora-old", "status": "ACTIVE"},
            "99999999-8888-7777-6666-555555555555",
            {
                "network_id": network_id,
                "device_id": "11111111-2222-3333-4444-555555555555",
                "fixed_ips": [{"ip_address": "172.16.29.10"}],
                "mac_address": "fa:16:3e:00:00:01",
            },
            network_id,
        )
        self.assertTrue(candidate["fixable"])
        self.assertEqual(candidate["management_ip"], "172.16.29.10")

    def test_delete_candidate_rechecks_octavia_before_deleting(self):
        args = argparse.Namespace()
        report = {
            "summary": {
                "management_network_id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
                "remediation_attempted": 0,
                "remediation_succeeded": 0,
                "remediation_failed": 0,
            },
            "remediation": [],
        }
        candidate = {
            "compute_id": "11111111-2222-3333-4444-555555555555",
            "port_id": "99999999-8888-7777-6666-555555555555",
        }
        with mock.patch.object(
            find_orphan_amphora,
            "octavia_compute_ids",
            return_value={candidate["compute_id"]},
        ), mock.patch.object(find_orphan_amphora, "openstack") as mocked_openstack:
            find_orphan_amphora.delete_candidate(args, report, candidate)

        mocked_openstack.assert_not_called()
        self.assertEqual(report["summary"]["remediation_failed"], 1)
        self.assertIn("referenced by Octavia", report["remediation"][0]["error"])

    def test_finish_report_exit_codes_match_ops_tool_standard(self):
        args = argparse.Namespace(format="json")
        base = {
            "tool": "find_orphan_amphora",
            "fix": False,
            "candidates": [],
            "remediation": [],
            "artifacts": {},
            "summary": {
                "actionable_findings": 0,
                "remediation_failed": 0,
            },
        }
        with mock.patch("sys.stdout"):
            self.assertEqual(
                find_orphan_amphora.finish_report(args, base),
                find_orphan_amphora.EXIT_OK,
            )
            base["summary"]["actionable_findings"] = 1
            self.assertEqual(
                find_orphan_amphora.finish_report(args, base),
                find_orphan_amphora.EXIT_FINDINGS,
            )
            base["summary"]["remediation_failed"] = 1
            self.assertEqual(
                find_orphan_amphora.finish_report(args, base),
                find_orphan_amphora.EXIT_REMEDIATION_FAILED,
            )

    def test_prepare_audit_paths_creates_expected_layout(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            output_dir = pathlib.Path(tmpdir) / "audit"
            paths = find_orphan_amphora.prepare_audit_paths(str(output_dir))
            self.assertTrue(paths.servers.is_dir())
            self.assertTrue(paths.ports.is_dir())
            self.assertEqual(paths.orphans_tsv.name, "orphans.tsv")
            self.assertEqual(paths.cleanup.name, "cleanup.sh")


if __name__ == "__main__":
    unittest.main()
