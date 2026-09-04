#!/usr/bin/env python3
"""Unit tests for find_orphan_instances.py."""

from __future__ import annotations

import importlib.util
import pathlib
import sys
import unittest
from argparse import Namespace
from unittest import mock

SCRIPT = pathlib.Path(__file__).with_name("find_orphan_instances.py")
SPEC = importlib.util.spec_from_file_location("find_orphan_instances", SCRIPT)
assert SPEC and SPEC.loader
module = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = module
SPEC.loader.exec_module(module)


class FindOrphanInstancesTests(unittest.TestCase):
    def database_args(self) -> Namespace:
        return Namespace(
            kubectl_command="kubectl",
            kubectl_request_timeout="30s",
            namespace="openstack",
            mariadb_secret="mariadb",
            mariadb_password_env="MYSQL_PWD",
            mariadb_pod="mariadb-cluster-0",
            mariadb_user="root",
            nova_database="nova",
            command_timeout=120,
        )

    def test_parse_instance_dirs_filters_uuid_directories(self) -> None:
        parsed = module.parse_instance_dirs(
            "\n".join(
                [
                    "2048 /var/lib/nova/instances/11111111-2222-3333-4444-555555555555",
                    "100 /var/lib/nova/instances/_base",
                    "bad /var/lib/nova/instances/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
                ]
            )
        )
        self.assertEqual(len(parsed), 1)
        self.assertEqual(parsed[0].uuid, "11111111-2222-3333-4444-555555555555")
        self.assertEqual(parsed[0].size_kb, 2048)

    def test_get_database_password_prefers_environment(self) -> None:
        args = self.database_args()
        with mock.patch.dict(module.os.environ, {"MYSQL_PWD": "secret"}, clear=False):
            with mock.patch.object(module, "run") as mocked_run:
                self.assertEqual(module.get_database_password(args), "secret")
        mocked_run.assert_not_called()

    def test_database_lookup_keeps_password_out_of_command_arguments(self) -> None:
        args = self.database_args()
        uuid = "11111111-2222-3333-4444-555555555555"

        def fake_run(
            cmd: list[str], timeout: int, input_text: str | None = None
        ) -> module.CommandResult:
            del timeout
            self.assertNotIn("-psecret", cmd)
            self.assertNotIn("secret", cmd)
            self.assertEqual(input_text, "secret\n")
            return module.CommandResult(0, f"{uuid}\n", "")

        with mock.patch.object(module, "run", side_effect=fake_run):
            self.assertEqual(
                module.active_uuids_in_database(args, "secret", {uuid}), {uuid}
            )

    def test_delete_requires_explicit_confirmation(self) -> None:
        self.assertEqual(
            module.main(["--delete-orphans", "--skip-credential-check"]),
            module.EXIT_ERROR,
        )

    def test_backup_requires_delete_mode(self) -> None:
        self.assertEqual(
            module.main(["--backup", "--skip-credential-check"]), module.EXIT_ERROR
        )

    def test_dry_run_orphan_exit_code(self) -> None:
        result = module.AuditResult(
            delete_orphans=False,
            backup=False,
            started_at="2026-09-02T00:00:00+00:00",
            duration_seconds=0.1,
            hosts_scanned=1,
            orphan_count=1,
            deleted_count=0,
            error_count=0,
            delete_failed_count=0,
            potential_savings_kb=1024,
            results=[],
        )
        with mock.patch.object(module, "require_command"), mock.patch.object(
            module, "verify_openstack_credentials"
        ), mock.patch.object(
            module, "build_audit_result", return_value=result
        ), mock.patch(
            "sys.stdout"
        ):
            self.assertEqual(
                module.main(["--skip-credential-check"]), module.EXIT_ORPHANS_FOUND
            )

    def test_delete_success_exit_code(self) -> None:
        result = module.AuditResult(
            delete_orphans=True,
            backup=False,
            started_at="2026-09-02T00:00:00+00:00",
            duration_seconds=0.1,
            hosts_scanned=1,
            orphan_count=1,
            deleted_count=1,
            error_count=0,
            delete_failed_count=0,
            potential_savings_kb=1024,
            results=[],
        )
        with mock.patch.object(module, "require_command"), mock.patch.object(
            module, "verify_openstack_credentials"
        ), mock.patch.object(
            module, "build_audit_result", return_value=result
        ), mock.patch(
            "sys.stdout"
        ):
            self.assertEqual(
                module.main(
                    [
                        "--delete-orphans",
                        "--yes-im-really-sure",
                        "--skip-credential-check",
                    ]
                ),
                module.EXIT_OK,
            )


if __name__ == "__main__":
    unittest.main()
