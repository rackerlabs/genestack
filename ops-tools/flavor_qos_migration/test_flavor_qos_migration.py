#!/usr/bin/env python3
"""Unit tests for the flavor QoS migration tool."""

from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from argparse import Namespace
from pathlib import Path
from types import SimpleNamespace
from unittest import mock
from contextlib import redirect_stderr, redirect_stdout
from io import StringIO


HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location(
    "flavor_qos_migration", HERE / "flavor_qos_migration.py"
)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class RateCalculationTests(unittest.TestCase):
    def test_four_policy_conversions(self):
        cases = (
            (150000, 250000, (1200000, 1000000, 2000000)),
            (250000, 500000, (2000000, 2000000, 4000000)),
            (375000, 750000, (3000000, 3000000, 6000000)),
            (500000, 1000000, (4000000, 4000000, 8000000)),
        )
        for maximum, burst, expected in cases:
            with self.subTest(maximum=maximum):
                self.assertEqual(
                    MODULE.calculate_policy_rates(maximum, burst), expected
                )

    def test_floor_boundaries(self):
        self.assertEqual(MODULE.calculate_policy_rates(249999, 1)[1], 1000000)
        self.assertEqual(MODULE.calculate_policy_rates(250000, 1)[1], 2000000)
        self.assertEqual(MODULE.calculate_policy_rates(250001, 1)[1], 2000000)

    def test_invalid_values_are_rejected(self):
        invalid = (0, -1, 1.5, True, (2**63 - 1) // 8 + 1)
        for value in invalid:
            with self.subTest(value=value):
                with self.assertRaises(MODULE.MigrationError):
                    MODULE.calculate_policy_rates(value, 1)

    def test_zero_after_rounding_is_rejected(self):
        with self.assertRaisesRegex(MODULE.MigrationError, "round to zero"):
            MODULE.calculate_policy_rates(124999, 1)


class MappingTests(unittest.TestCase):
    def test_shipped_mapping_is_complete(self):
        mapping = MODULE.load_mapping(HERE / "flavor_qos_mapping.yaml")
        self.assertEqual(set(mapping.policies), {"lite", "plus", "pro", "elite"})
        self.assertEqual(
            {name: len(region.flavors) for name, region in mapping.regions.items()},
            {"dfw-dev": 16, "dfw-prod": 23, "sjc-prod": 24, "iad-prod": 17},
        )
        self.assertEqual(sum(len(r.flavors) for r in mapping.regions.values()), 80)

    def test_mapping_has_expected_policy_rates(self):
        mapping = MODULE.load_mapping(HERE / "flavor_qos_mapping.yaml")
        self.assertEqual(
            {
                name: (policy.max_kbps, policy.max_burst_kbps)
                for name, policy in mapping.policies.items()
            },
            {
                "lite": (1000000, 2000000),
                "plus": (2000000, 4000000),
                "pro": (3000000, 6000000),
                "elite": (4000000, 8000000),
            },
        )

    def test_rejects_ambiguous_policy_set(self):
        text = (HERE / "flavor_qos_mapping.yaml").read_text()
        text = text.replace("  elite:\n", "  other:\n", 1)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "map.yaml"
            path.write_text(text)
            with self.assertRaisesRegex(
                MODULE.MigrationError, "exactly these policies"
            ):
                MODULE.load_mapping(path)


def serialized_flavor(extra_specs=None, old=None, new=None):
    return json.dumps(
        {
            "cur": {
                "nova_object.name": "Flavor",
                "nova_object.version": "1.2",
                "nova_object.data": {
                    "flavorid": "flavor-id",
                    "extra_specs": extra_specs or {},
                    "unchanged": "keep-me",
                },
            },
            "old": old,
            "new": new,
        },
        separators=(",", ":"),
    )


class CachedFlavorTests(unittest.TestCase):
    POLICY_ID = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"

    def test_only_current_extra_specs_are_changed(self):
        source = serialized_flavor(
            {
                "quota:vif_outbound_average": "125000",
                "quota:vif_inbound_peak": "20480",
                "unrelated": "preserved",
            }
        )
        updated, changed = MODULE.migrate_cached_flavor(source, self.POLICY_ID)
        self.assertTrue(changed)
        result = json.loads(updated)
        data = result["cur"]["nova_object.data"]
        self.assertEqual(data["unchanged"], "keep-me")
        self.assertEqual(
            data["extra_specs"],
            {
                "unrelated": "preserved",
                "flavor_qos:policy_id": self.POLICY_ID,
            },
        )
        self.assertEqual(result["cur"]["nova_object.version"], "1.2")

    def test_idempotent_cached_flavor(self):
        source = serialized_flavor({"flavor_qos:policy_id": self.POLICY_ID})
        updated, changed = MODULE.migrate_cached_flavor(source, self.POLICY_ID)
        self.assertFalse(changed)
        self.assertEqual(updated, source)

    def test_active_resize_flavors_are_rejected(self):
        with self.assertRaisesRegex(MODULE.MigrationError, "non-null old or new"):
            MODULE.migrate_cached_flavor(serialized_flavor(old={}), self.POLICY_ID)


class FakeNetwork:
    def __init__(self, policies=(), rules=()):
        self._policies = list(policies)
        self._rules = list(rules)
        self.created_policy = None
        self.created_rule = None

    def qos_policies(self, **_kwargs):
        return iter(self._policies)

    def qos_bandwidth_limit_rules(self, _policy):
        return iter(self._rules)

    def create_qos_policy(self, **kwargs):
        self.created_policy = kwargs
        return SimpleNamespace(id="bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", **kwargs)

    def create_qos_bandwidth_limit_rule(self, _policy, **kwargs):
        self.created_rule = kwargs
        return SimpleNamespace(**kwargs)

    def qos_dscp_marking_rules(self, _policy):
        return iter(())

    def qos_minimum_bandwidth_rules(self, _policy):
        return iter(())

    def qos_minimum_packet_rate_rules(self, _policy):
        return iter(())

    def qos_packet_rate_limit_rules(self, _policy):
        return iter(())


class PolicyTests(unittest.TestCase):
    def setUp(self):
        self.mapping = MODULE.MappingSpec(
            {"lite": MODULE.PolicySpec("lite", 150000, 250000)}, {}, 1
        )

    def test_exact_policy_is_reused(self):
        policy = SimpleNamespace(
            id="policy-id",
            name="lite",
            project_id="project-id",
            is_shared=False,
            is_default=False,
        )
        rule = SimpleNamespace(
            max_kbps=1000000, max_burst_kbps=2000000, direction="egress"
        )
        conn = SimpleNamespace(
            current_project_id="project-id", network=FakeNetwork([policy], [rule])
        )
        plans = MODULE.find_policies(conn, self.mapping)
        self.assertEqual((plans[0].action, plans[0].policy_id), ("reuse", "policy-id"))

    def test_mismatched_policy_is_a_conflict(self):
        policy = SimpleNamespace(
            id="policy-id",
            project_id="project-id",
            is_shared=False,
            is_default=False,
        )
        rule = SimpleNamespace(
            max_kbps=1200000, max_burst_kbps=2000000, direction="egress"
        )
        conn = SimpleNamespace(
            current_project_id="project-id", network=FakeNetwork([policy], [rule])
        )
        with self.assertRaisesRegex(MODULE.MigrationError, "rule mismatch"):
            MODULE.find_policies(conn, self.mapping)

    def test_creation_uses_non_shared_egress_rule(self):
        network = FakeNetwork()
        plan = MODULE.PolicyPlan("lite", 1200000, 1000000, 2000000)
        MODULE.create_missing_policies(
            SimpleNamespace(network=network, current_project_id="project-id"), [plan]
        )
        self.assertEqual(
            network.created_policy,
            {
                "name": "lite",
                "project_id": "project-id",
                "is_shared": False,
                "is_default": False,
            },
        )
        self.assertEqual(network.created_rule["direction"], "egress")
        self.assertEqual(plan.action, "created")

    def test_additional_rule_type_is_a_conflict(self):
        policy = SimpleNamespace(
            id="policy-id",
            project_id="project-id",
            is_shared=False,
            is_default=False,
        )
        rule = SimpleNamespace(
            max_kbps=1000000, max_burst_kbps=2000000, direction="egress"
        )
        network = FakeNetwork([policy], [rule])
        network.qos_dscp_marking_rules = lambda _policy: iter([object()])
        conn = SimpleNamespace(current_project_id="project-id", network=network)
        with self.assertRaisesRegex(MODULE.MigrationError, "unexpected rule type"):
            MODULE.find_policies(conn, self.mapping)


class FakeCompute:
    def __init__(self, flavor):
        self.flavor = flavor

    def flavors(self, **_kwargs):
        return iter([self.flavor])

    def fetch_flavor_extra_specs(self, _flavor):
        return self.flavor


class FlavorTests(unittest.TestCase):
    POLICY_ID = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"

    def setUp(self):
        self.mapping = MODULE.MappingSpec(
            {"lite": MODULE.PolicySpec("lite", 150000, 250000)}, {}, 1
        )
        self.spec = MODULE.FlavorSpec(
            "gp.test",
            "lite",
            {
                key: (
                    125000
                    if key == "quota:vif_outbound_average"
                    else (
                        250000
                        if key
                        in {"quota:vif_outbound_burst", "quota:vif_outbound_peak"}
                        else None
                    )
                )
                for key in MODULE.LEGACY_KEYS
            },
        )
        self.region = MODULE.RegionSpec("test", (self.spec,))

    def test_fresh_flavor_plan_preserves_unrelated_specs(self):
        flavor = SimpleNamespace(
            id="flavor-id",
            name="gp.test",
            extra_specs={
                "quota:vif_outbound_average": "125000",
                "quota:vif_outbound_burst": "250000",
                "quota:vif_outbound_peak": "250000",
                "unrelated": "keep",
            },
        )
        conn = SimpleNamespace(compute=FakeCompute(flavor))
        plan = MODULE.resolve_flavors(
            conn, self.region, self.mapping, {"lite": self.POLICY_ID}
        )[0]
        self.assertEqual(
            plan.new_extra_specs,
            {"unrelated": "keep", "flavor_qos:policy_id": self.POLICY_ID},
        )
        self.assertEqual(plan.legacy_raw_max_kbps, 1000000)
        self.assertEqual(plan.percent_change, 0)

    def test_missing_expected_legacy_spec_fails_fresh_preflight(self):
        flavor = SimpleNamespace(id="flavor-id", name="gp.test", extra_specs={})
        conn = SimpleNamespace(compute=FakeCompute(flavor))
        with self.assertRaisesRegex(MODULE.MigrationError, "missing expected"):
            MODULE.resolve_flavors(
                conn, self.region, self.mapping, {"lite": self.POLICY_ID}
            )

    def test_already_migrated_flavor_is_idempotent(self):
        flavor = SimpleNamespace(
            id="flavor-id",
            name="gp.test",
            extra_specs={"flavor_qos:policy_id": self.POLICY_ID},
        )
        conn = SimpleNamespace(compute=FakeCompute(flavor))
        plan = MODULE.resolve_flavors(
            conn, self.region, self.mapping, {"lite": self.POLICY_ID}
        )[0]
        self.assertEqual(plan.action, "noop")


class SafetyTests(unittest.TestCase):
    def test_admin_role_is_required(self):
        auth = SimpleNamespace(
            get_access=lambda _session: SimpleNamespace(role_names=["member"])
        )
        conn = SimpleNamespace(
            session=SimpleNamespace(auth=auth), current_project_id="project-id"
        )
        with self.assertRaisesRegex(MODULE.MigrationError, "admin-scoped"):
            MODULE.require_admin_scope(conn)

    def test_admin_role_is_accepted_case_insensitively(self):
        auth = SimpleNamespace(
            get_access=lambda _session: SimpleNamespace(role_names=["Admin"])
        )
        conn = SimpleNamespace(
            session=SimpleNamespace(auth=auth), current_project_id="project-id"
        )
        MODULE.require_admin_scope(conn)

    def test_database_identifier_is_restricted(self):
        self.assertEqual(MODULE.quoted_database("nova_cell1"), "`nova_cell1`")
        with self.assertRaises(MODULE.MigrationError):
            MODULE.quoted_database("nova; DROP DATABASE nova")

    def test_apply_requires_confirmation(self):
        parser = MODULE.build_parser()
        args = parser.parse_args(
            [
                "--map-file",
                "map.yaml",
                "--region",
                "dfw-dev",
                "--os-cloud",
                "cloud",
                "--nova-database",
                "nova",
                "--apply",
            ]
        )
        with redirect_stderr(StringIO()), self.assertRaises(SystemExit):
            MODULE.validate_args(args, parser)


class DatabaseTests(unittest.TestCase):
    def test_compare_and_swap_sql_rolls_all_rows_together(self):
        args = Namespace()
        client = MODULE.MariaDBClient(args)
        captured = {}

        def execute(sql):
            captured["sql"] = sql
            return "__FLAVOR_QOS_CHANGED__1\n"

        client.execute = execute
        plan = MODULE.InstancePlan(
            "nova_cell1",
            "instance-id",
            "flavor",
            "flavor-id",
            "lite",
            "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            "AA",
            "BB",
            "update",
        )
        client.apply_cached_flavors("nova_cell1", [plan])
        self.assertIn(
            "WHERE ie.deleted = 0 AND HEX(ie.flavor) = u.old_hex", captured["sql"]
        )
        self.assertIn("ROLLBACK", captured["sql"])

    def test_compare_and_swap_race_fails_closed(self):
        client = MODULE.MariaDBClient(Namespace())
        client.execute = lambda _sql: "__FLAVOR_QOS_CHANGED__0\n"
        plan = MODULE.InstancePlan(
            "nova",
            "instance-id",
            "flavor",
            "flavor-id",
            "lite",
            "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            "AA",
            "BB",
            "update",
        )
        with self.assertRaisesRegex(MODULE.MigrationError, "compare-and-swap"):
            client.apply_cached_flavors("nova", [plan])

    def test_instances_are_collected_from_multiple_cells(self):
        flavor_plan = MODULE.FlavorPlan(
            "gp.test",
            "flavor-id",
            "lite",
            "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            {},
            {},
            125000,
            1000000,
            1000000,
            0.0,
            "update",
        )

        class Client:
            def active_migrations(self, _database):
                return set()

            def read_instances(self, database):
                instance = "instance-1" if database == "cell1" else "instance-2"
                payload = serialized_flavor().encode().hex()
                return [(instance, "", payload)]

        plans = MODULE.plan_instances(Client(), ["cell1", "cell2"], [flavor_plan])
        self.assertEqual({plan.database for plan in plans}, {"cell1", "cell2"})

    def test_active_task_state_fails_preflight(self):
        flavor_plan = MODULE.FlavorPlan(
            "gp.test",
            "flavor-id",
            "lite",
            "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            {},
            {},
            125000,
            1000000,
            1000000,
            0.0,
            "update",
        )

        class Client:
            def active_migrations(self, _database):
                return set()

            def read_instances(self, _database):
                return [
                    ("instance-1", "rebuilding", serialized_flavor().encode().hex())
                ]

        with self.assertRaisesRegex(MODULE.MigrationError, "active task_state"):
            MODULE.plan_instances(Client(), ["cell1"], [flavor_plan])


class PortTests(unittest.TestCase):
    def test_non_target_explicit_port_policy_is_a_conflict(self):
        port = SimpleNamespace(
            id="port-id",
            device_owner="compute:nova",
            qos_policy_id="other",
            network_id="net-id",
            revision_number=1,
        )
        network = SimpleNamespace(ports=lambda **_kwargs: iter([port]))
        conn = SimpleNamespace(network=network)
        instance = MODULE.InstancePlan(
            "nova",
            "instance-id",
            "flavor",
            "flavor-id",
            "lite",
            "target",
            "AA",
            "BB",
            "update",
        )
        with self.assertRaisesRegex(MODULE.MigrationError, "conflicting"):
            MODULE.plan_ports(conn, [instance])

    def test_apply_re_reads_stored_port_policy(self):
        class Network:
            def __init__(self):
                self.port = SimpleNamespace(
                    id="port-id", qos_policy_id=None, revision_number=7
                )

            def get_port(self, _port_id):
                return self.port

            def update_port(self, _port, if_revision=None, **attrs):
                self.asserted_revision = if_revision
                self.port.qos_policy_id = attrs["qos_policy_id"]
                self.port.revision_number += 1
                return self.port

        network = Network()
        plan = MODULE.PortPlan(
            "port-id",
            "instance-id",
            "flavor",
            "lite",
            "target",
            None,
            None,
            7,
            "update",
        )
        MODULE.apply_ports(SimpleNamespace(network=network), [plan])
        self.assertEqual(network.port.qos_policy_id, "target")
        self.assertEqual(network.asserted_revision, 7)


class RollbackTests(unittest.TestCase):
    POLICY_ID = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"

    def test_rollback_restores_every_layer_and_removes_created_policy(self):
        policy = MODULE.PolicyPlan(
            "lite", 1200000, 1000000, 2000000, self.POLICY_ID, "created"
        )
        flavor = MODULE.FlavorPlan(
            "gp.test",
            "flavor-id",
            "lite",
            self.POLICY_ID,
            {"quota:vif_outbound_average": "125000"},
            {"flavor_qos:policy_id": self.POLICY_ID},
            125000,
            1000000,
            1000000,
            0.0,
            "update",
        )
        instance = MODULE.InstancePlan(
            "nova",
            "instance-id",
            "gp.test",
            "flavor-id",
            "lite",
            self.POLICY_ID,
            "AA",
            "BB",
            "update",
        )
        port = MODULE.PortPlan(
            "port-id",
            "instance-id",
            "gp.test",
            "lite",
            self.POLICY_ID,
            None,
            None,
            1,
            "update",
        )

        class Compute:
            def __init__(self):
                self.flavor = SimpleNamespace(
                    id="flavor-id",
                    name="gp.test",
                    extra_specs={"flavor_qos:policy_id": RollbackTests.POLICY_ID},
                )

            def fetch_flavor_extra_specs(self, _flavor):
                return self.flavor

            def create_flavor_extra_specs(self, _flavor, specs):
                self.flavor.extra_specs.update(specs)

            def delete_flavor_extra_specs_property(self, _flavor, key):
                self.flavor.extra_specs.pop(key, None)

            def flavors(self, **_kwargs):
                return iter([self.flavor])

        class Network:
            def __init__(self):
                self.port = SimpleNamespace(
                    id="port-id",
                    qos_policy_id=RollbackTests.POLICY_ID,
                    revision_number=1,
                )
                self.policy = SimpleNamespace(
                    id=RollbackTests.POLICY_ID,
                    name="lite",
                    project_id="project-id",
                    is_shared=False,
                    is_default=False,
                )
                self.rule = SimpleNamespace(
                    max_kbps=1000000,
                    max_burst_kbps=2000000,
                    direction="egress",
                )
                self.deleted = []

            def get_port(self, _port_id):
                return self.port

            def update_port(self, _port, **attrs):
                self.port.qos_policy_id = attrs["qos_policy_id"]
                return self.port

            def ports(self):
                return iter([self.port])

            def networks(self):
                return iter(())

            def get_qos_policy(self, _policy_id):
                return self.policy

            def qos_bandwidth_limit_rules(self, _policy):
                return iter([self.rule])

            def delete_qos_bandwidth_limit_rule(self, _rule, _policy):
                self.deleted.append("rule")

            def delete_qos_policy(self, _policy):
                self.deleted.append("policy")

        class Database:
            def __init__(self):
                self.calls = []

            def apply_cached_flavors(self, database, plans, reverse=False):
                self.calls.append((database, len(plans), reverse))

        payload = {
            "schema_version": 1,
            "policies": [MODULE.asdict(policy)],
            "flavors": [MODULE.asdict(flavor)],
            "instances": [MODULE.asdict(instance)],
            "ports": [MODULE.asdict(port)],
        }
        compute = Compute()
        network = Network()
        database = Database()
        conn = SimpleNamespace(
            compute=compute, network=network, current_project_id="project-id"
        )
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "state.json"
            state.write_text(json.dumps(payload))
            result = MODULE.rollback(Namespace(), conn, database, state)
            saved = json.loads(state.read_text())
        self.assertEqual(result, MODULE.EXIT_OK)
        self.assertEqual(saved["status"], "rolled_back")
        self.assertEqual(database.calls, [("nova", 1, True)])
        self.assertEqual(
            compute.flavor.extra_specs,
            {"quota:vif_outbound_average": "125000"},
        )
        self.assertEqual(network.port.qos_policy_id, None)
        self.assertEqual(network.deleted, ["rule", "policy"])


class CliTests(unittest.TestCase):
    def test_validate_map_only_json_exit_code(self):
        output = StringIO()
        with redirect_stdout(output):
            result = MODULE.main(
                [
                    "--map-file",
                    str(HERE / "flavor_qos_mapping.yaml"),
                    "--validate-map-only",
                    "--format",
                    "json",
                ]
            )
        self.assertEqual(result, MODULE.EXIT_OK)
        self.assertEqual(json.loads(output.getvalue())["flavors"], 80)

    def test_apply_preflight_failure_uses_runtime_exit_code(self):
        stderr = StringIO()
        with (
            mock.patch.object(
                MODULE,
                "connect_openstack",
                side_effect=MODULE.MigrationError("connection failed"),
            ),
            redirect_stderr(stderr),
        ):
            result = MODULE.main(
                [
                    "--map-file",
                    str(HERE / "flavor_qos_mapping.yaml"),
                    "--region",
                    "dfw-dev",
                    "--os-cloud",
                    "cloud",
                    "--nova-database",
                    "nova",
                    "--apply",
                    "--yes-im-really-sure",
                ]
            )
        self.assertEqual(result, MODULE.EXIT_ERROR)
        self.assertIn("connection failed", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
