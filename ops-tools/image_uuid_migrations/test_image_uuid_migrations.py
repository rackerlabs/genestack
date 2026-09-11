import sys
import tempfile
import unittest
from unittest import mock
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import image_uuid_migrations as tool


def subprocess_result(stdout="", stderr="", returncode=0):
    return tool.subprocess.CompletedProcess(
        args=["mariadb"], returncode=returncode, stdout=stdout, stderr=stderr
    )


class ImageUuidMigrationsTest(unittest.TestCase):
    def test_apply_requires_confirmation(self):
        self.assertEqual(tool.main(["--map-file", "missing.csv", "--apply"]), 1)

    def test_requires_map_file(self):
        self.assertEqual(tool.main([]), 1)

    def test_defaults_to_nova_database(self):
        path = Path(__file__).resolve().parent / "image_migration.csv"
        args = tool.parse_args(["--map-file", str(path)])
        plan = tool.build_plan(args)

        self.assertEqual(plan.nova_databases, ["nova"])
        self.assertIn("USE `nova`", plan.sql)

    def test_dry_run_plan_contains_nova_and_cinder_updates(self):
        path = Path(__file__).resolve().parent / "image_migration.csv"
        args = tool.parse_args(["--map-file", str(path), "--cinder-database", "cinder"])
        plan = tool.build_plan(args)

        self.assertFalse(plan.apply)
        self.assertIn("START TRANSACTION", plan.sql)
        self.assertIn("UPDATE instances", plan.sql)
        self.assertIn("nova:instances_to_update", plan.sql)
        self.assertIn("nova:block_device_mapping_to_update", plan.sql)
        self.assertIn("cinder:volume_glance_metadata_to_update", plan.sql)

    def test_apply_plan_contains_transaction_and_updates(self):
        path = Path(__file__).resolve().parent / "image_migration.csv"
        args = tool.parse_args(
            [
                "--map-file",
                str(path),
                "--cinder-database",
                "cinder",
                "--apply",
                "--yes-im-really-sure",
            ]
        )
        plan = tool.build_plan(args)

        self.assertTrue(plan.apply)
        self.assertIn("START TRANSACTION", plan.sql)
        self.assertIn("UPDATE instances", plan.sql)
        self.assertIn("UPDATE `cinder`.volume_glance_metadata", plan.sql)
        self.assertIn("COMMIT", plan.sql)

    def test_preview_plan_contains_counts_without_updates(self):
        path = Path(__file__).resolve().parent / "image_migration.csv"
        args = tool.parse_args(["--map-file", str(path), "--cinder-database", "cinder"])
        plan = tool.build_plan(args)

        self.assertIn("nova:instances_to_update", plan.preview_sql)
        self.assertIn("nova:block_device_mapping_to_update", plan.preview_sql)
        self.assertIn("cinder:volume_glance_metadata_to_update", plan.preview_sql)
        self.assertNotIn("UPDATE instances", plan.preview_sql)
        self.assertNotIn("UPDATE block_device_mapping", plan.preview_sql)
        self.assertNotIn("UPDATE `cinder`.volume_glance_metadata", plan.preview_sql)

    def test_connection_options_are_added_to_commands_and_password_is_redacted(self):
        path = Path(__file__).resolve().parent / "image_migration.csv"
        args = tool.parse_args(
            [
                "--map-file",
                str(path),
                "--mysql-host",
                "db.example.test",
                "--mysql-port",
                "3307",
                "--mysql-user",
                "nova",
                "--mysql-password",
                "secret",
            ]
        )
        plan = tool.build_plan(args)

        self.assertIn("--host", plan.command)
        self.assertIn("db.example.test", plan.command)
        self.assertIn("--port", plan.command)
        self.assertIn("3307", plan.command)
        self.assertIn("--user", plan.command)
        self.assertIn("nova", plan.command)
        self.assertNotIn("secret", plan.command)
        self.assertEqual(plan.command_env, {"MYSQL_PWD": "***"})
        self.assertIn("--batch", plan.preview_command)

    def test_parse_preview_rows(self):
        rows = tool.parse_preview_rows(
            "mapping_rows\t3\nnova:instances_to_update\t2\ncinder:volume_glance_metadata_to_update\t1\n"
        )

        self.assertEqual(
            rows,
            [
                ("mapping_rows", 3),
                ("nova:instances_to_update", 2),
                ("cinder:volume_glance_metadata_to_update", 1),
            ],
        )

    def test_run_preview_uses_preview_sql(self):
        path = Path(__file__).resolve().parent / "image_migration.csv"
        args = tool.parse_args(["--map-file", str(path), "--quiet"])
        plan = tool.build_plan(args)
        completed = subprocess_result(
            stdout="mapping_rows\t3\nnova:instances_to_update\t0\nnova:block_device_mapping_to_update\t0\nnova:instance_system_metadata_to_update\t0\n"
        )

        with mock.patch.object(tool.shutil, "which", return_value="/usr/bin/mariadb"):
            with mock.patch.object(
                tool.subprocess, "run", return_value=completed
            ) as run:
                with mock.patch("builtins.print"):
                    self.assertEqual(tool.run_preview(plan, args), 0)

        self.assertEqual(run.call_args.kwargs["input"], plan.preview_sql)
        self.assertNotIn("UPDATE instances", run.call_args.kwargs["input"])

    def test_rejects_invalid_database_name(self):
        path = Path(__file__).resolve().parent / "image_migration.csv"
        args = tool.parse_args(
            ["--map-file", str(path), "--nova-database", "nova-cell1"]
        )
        with self.assertRaises(tool.MigrationError):
            tool.build_plan(args)

    def test_loads_csv_mapping(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "map.csv"
            path.write_text(
                "image_name,old_image_uuid,new_image_uuid\n"
                "Ubuntu,93736472-ed21-4697-a5e1-15a094b0c938,"
                "28f59de2-804f-45e9-8597-9eb43baaadae\n",
                encoding="utf-8",
            )
            args = tool.parse_args(["--map-file", str(path)])
            plan = tool.build_plan(args)

        self.assertEqual(plan.mapping_count, 1)
        self.assertIn("Ubuntu", plan.sql)

    def test_example_csv_mapping_loads(self):
        path = Path(__file__).resolve().parent / "image_migration.csv"
        args = tool.parse_args(["--map-file", str(path)])
        plan = tool.build_plan(args)

        self.assertEqual(plan.mapping_count, 3)
        self.assertEqual(plan.changed_mapping_count, 3)

    def test_csv_preflight_rejects_missing_header(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "map.csv"
            path.write_text(
                "Example Linux,11111111-1111-4111-8111-111111111111,"
                "22222222-2222-4222-8222-222222222222\n",
                encoding="utf-8",
            )

            with self.assertRaisesRegex(tool.MigrationError, "missing required column"):
                tool.load_csv_mappings(path)

    def test_csv_preflight_rejects_duplicate_old_uuid(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "map.csv"
            path.write_text(
                "image_name,old_image_uuid,new_image_uuid\n"
                "Example Linux 1,11111111-1111-4111-8111-111111111111,"
                "22222222-2222-4222-8222-222222222222\n"
                "Example Linux 2,11111111-1111-4111-8111-111111111111,"
                "44444444-4444-4444-8444-444444444444\n",
                encoding="utf-8",
            )

            with self.assertRaisesRegex(
                tool.MigrationError, "duplicate old_image_uuid"
            ):
                tool.load_csv_mappings(path)


if __name__ == "__main__":
    unittest.main()
