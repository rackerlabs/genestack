#!/usr/bin/env python3
import argparse
import pathlib
import sys
import unittest
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import ovn_ops


class OvnOpsTests(unittest.TestCase):
    def test_extract_uuid_from_neutron_prefixed_name(self):
        self.assertEqual(
            ovn_ops.extract_uuid("neutron-11111111-2222-3333-4444-555555555555"),
            "11111111-2222-3333-4444-555555555555",
        )

    def test_extract_neutron_resource_uuid_requires_exact_prefix(self):
        uuid = "11111111-2222-3333-4444-555555555555"
        self.assertEqual(
            ovn_ops.extract_neutron_resource_uuid(f"neutron-{uuid}"),
            uuid,
        )
        self.assertIsNone(ovn_ops.extract_neutron_resource_uuid(f"custom-{uuid}"))
        self.assertIsNone(ovn_ops.extract_neutron_resource_uuid(f"neutron-{uuid}-x"))

    def test_extract_neutron_lrp_uuid_requires_exact_lrp_prefix(self):
        uuid = "11111111-2222-3333-4444-555555555555"
        self.assertEqual(ovn_ops.extract_neutron_lrp_uuid(f"lrp-{uuid}"), uuid)
        self.assertIsNone(ovn_ops.extract_neutron_lrp_uuid(f"cr-lrp-{uuid}"))
        self.assertIsNone(ovn_ops.extract_neutron_lrp_uuid(f"custom-{uuid}"))

    def test_router_maps_ignore_non_neutron_uuid_names(self):
        args = argparse.Namespace()
        router_uuid = "11111111-2222-3333-4444-555555555555"
        ovn_uuid = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        with mock.patch.object(
            ovn_ops,
            "ovn_uuid_map",
            return_value=[
                [ovn_uuid, f"neutron-{router_uuid}"],
                ["bbbbbbbb-cccc-dddd-eeee-ffffffffffff", f"custom-{router_uuid}"],
            ],
        ):
            self.assertEqual(ovn_ops.ovn_lr_map(args), {router_uuid: ovn_uuid})

    def test_router_port_maps_ignore_non_lrp_uuid_names(self):
        args = argparse.Namespace()
        port_uuid = "11111111-2222-3333-4444-555555555555"
        ovn_uuid = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        with mock.patch.object(
            ovn_ops,
            "ovn_uuid_map",
            return_value=[
                [ovn_uuid, f"lrp-{port_uuid}"],
                ["bbbbbbbb-cccc-dddd-eeee-ffffffffffff", f"cr-lrp-{port_uuid}"],
            ],
        ):
            self.assertEqual(ovn_ops.ovn_lrp_map(args), {port_uuid: ovn_uuid})

    def test_parse_csv_rows_handles_quoted_external_ids(self):
        rows = ovn_ops.parse_csv_rows(
            'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee,"{neutron:security_group_id=11111111-2222-3333-4444-555555555555}"\n'
        )
        self.assertEqual(rows[0][0], "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        self.assertIn("neutron:security_group_id=", rows[0][1])

    def test_compare_sets_returns_missing_and_stale(self):
        missing, stale = ovn_ops.compare_sets(
            {"a": "expected-a", "b": "expected-b"},
            {"b": "ovn-b", "c": "ovn-c"},
        )
        self.assertEqual(missing, [("a", "expected-a")])
        self.assertEqual(stale, [("c", "ovn-c")])

    def test_fix_requires_operator_confirmation(self):
        args = argparse.Namespace(fix=True, yes_im_really_sure=False)
        with self.assertRaisesRegex(ovn_ops.OpsError, "--yes-im-really-sure"):
            ovn_ops.validate_fix_args(args)

    def test_destroy_rejects_invalid_uuid_without_running_nbctl(self):
        args = argparse.Namespace(nbctl_command="kubectl ko nbctl", command_timeout=60)
        report = {
            "summary": {
                "remediation_attempted": 0,
                "remediation_failed": 0,
                "remediation_succeeded": 0,
            },
            "remediation": [],
        }
        with mock.patch.object(ovn_ops, "nbctl") as mocked_nbctl:
            ovn_ops.destroy_ovn_resource(args, report, "NAT", "not-a-uuid")
        mocked_nbctl.assert_not_called()
        self.assertEqual(report["summary"]["remediation_failed"], 1)

    def test_fip_main_returns_findings_for_stale_nat(self):
        uuid = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        with mock.patch.object(ovn_ops, "ensure_nbctl"), mock.patch.object(
            ovn_ops, "neutron_fips", return_value={"203.0.113.10": "fip-id"}
        ), mock.patch.object(
            ovn_ops, "ovn_nat_map", return_value={"203.0.113.20": uuid}
        ), mock.patch(
            "sys.stdout"
        ):
            rc = ovn_ops.main_fips(["--scan"])
        self.assertEqual(rc, ovn_ops.EXIT_FINDINGS)

    def test_fip_fix_deletes_stale_nat_but_keeps_missing_findings(self):
        uuid = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        with mock.patch.object(ovn_ops, "ensure_nbctl"), mock.patch.object(
            ovn_ops, "neutron_fips", return_value={"203.0.113.10": "fip-id"}
        ), mock.patch.object(
            ovn_ops, "ovn_nat_map", return_value={"203.0.113.20": uuid}
        ), mock.patch.object(
            ovn_ops, "nbctl", return_value=""
        ) as mocked_nbctl, mock.patch(
            "sys.stdout"
        ):
            rc = ovn_ops.main_fips(["--fix", "--yes-im-really-sure"])
        mocked_nbctl.assert_called_once_with(mock.ANY, ["destroy", "NAT", uuid])
        self.assertEqual(rc, ovn_ops.EXIT_FINDINGS)


if __name__ == "__main__":
    unittest.main()
