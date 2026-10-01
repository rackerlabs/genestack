#!/usr/bin/env python3
import argparse
import pathlib
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import secret_schema_validator as validator


class SecretSchemaValidatorTests(unittest.TestCase):
    def test_discover_sensitive_paths_filters_names_not_values(self):
        values = {
            "tls": {"secretName": "existing-cert"},
            "manifests": {"secret_db": True},
            "conf": {
                "barbican": {
                    "p11_crypto_plugin": {
                        "hmac_label": "ignored",
                        "mkek_label": "ignored",
                        "pin": "123456",
                    },
                    "simple_crypto_kek_rewrap": {"old_kek": "old"},
                    "simple_crypto_plugin": {"kek": "current"},
                },
                "service_user": {"send_service_user_token": True},
                "zaqar": {"signed_url": {"secret_key": "SOMELONGSECRETKEY"}},
            },
            "image": {"pullSecrets": [{"name": "registry"}]},
            "network": {"ssh": {"private_key": "", "public_key": ""}},
            "endpoints": {
                "identity": {"auth": {"admin": {"password": "secret"}}},
                "oci_image_registry": {
                    "auth": {"service": {"password": "operator-managed"}}
                },
                "oslo_cache": {"auth": {"memcache_secret_key": "key"}},
            },
            "optional": {"auth": {"password": None}},
        }

        self.assertEqual(
            validator.discover_sensitive_paths(values),
            [
                "conf.barbican.p11_crypto_plugin.pin",
                "conf.barbican.simple_crypto_kek_rewrap.old_kek",
                "conf.barbican.simple_crypto_plugin.kek",
                "conf.zaqar.signed_url.secret_key",
                "endpoints.identity.auth.admin.password",
                "endpoints.oslo_cache.auth.memcache_secret_key",
            ],
        )

    def test_descriptor_secret_paths_ignores_entries_without_helm_key(self):
        descriptor = {
            "secrets": [
                {"helm_key": "endpoints.identity.auth.admin.password"},
                {"source_secret": "only-a-k8s-secret"},
            ]
        }

        self.assertEqual(
            validator.descriptor_secret_paths(descriptor),
            ["endpoints.identity.auth.admin.password"],
        )

    def test_helm_key_to_chart_path_preserves_escaped_dot_and_indexes(self):
        self.assertEqual(
            validator.helm_key_to_chart_path(
                r"conf.rally_tests.tests.TroveInstances\.create_and_delete_instance[0].args.users[0].password"
            ),
            "conf.rally_tests.tests.TroveInstances.create_and_delete_instance.0.args.users.0.password",
        )

    def test_descriptor_secret_paths_normalizes_helm_set_syntax(self):
        descriptor = {
            "secrets": [
                {
                    "helm_key": r"conf.rally_tests.tests.TroveInstances\.create_and_delete_instance[0].args.users[0].password"
                },
            ]
        }

        self.assertEqual(
            validator.descriptor_secret_paths(descriptor),
            [
                "conf.rally_tests.tests.TroveInstances.create_and_delete_instance.0.args.users.0.password"
            ],
        )

    def test_descriptor_unsafe_list_paths_flags_indexed_set_paths(self):
        descriptor = {
            "secrets": [
                {
                    "helm_key": r"conf.tests.example[0].args.password",
                    "helm_flag": "--set",
                },
                {
                    "helm_key": r"conf.tests.example[0].args.key",
                    "helm_flag": "--set-file",
                },
                {
                    "helm_key": r"conf.tests.example[0].args.json",
                    "helm_flag": "--set-json",
                },
                {
                    "helm_key": r"conf.tests.example[0].args.literal",
                    "helm_flag": "--set-literal",
                },
                {
                    "helm_key": "conf.tests.example",
                    "helm_flag": "--set-json",
                },
            ]
        }

        self.assertEqual(
            validator.descriptor_unsafe_list_paths(descriptor),
            [
                r"conf.tests.example[0].args.json",
                r"conf.tests.example[0].args.key",
                r"conf.tests.example[0].args.literal",
                r"conf.tests.example[0].args.password",
            ],
        )

    def test_report_includes_unsafe_list_paths_as_findings(self):
        result = validator.ServiceResult(
            service="trove",
            descriptor="bin/services/trove.yaml",
            unsafe_list_paths=[r"conf.tests.example[0].args.password"],
        )

        report = validator.report_to_dict([result])

        self.assertEqual(report["summary"]["unsafe_list_paths"], 1)
        self.assertEqual(
            report["services"][0]["unsafe_list_paths"],
            [r"conf.tests.example[0].args.password"],
        )

    def test_descriptor_ignore_paths_reads_chart_scoped_patterns(self):
        descriptor = {"chart": {"ignore_paths": ["conf.example.secret"]}}

        self.assertEqual(
            validator.descriptor_ignore_paths(descriptor), ["conf.example.secret"]
        )

    def test_service_descriptor_paths_supports_explicit_services(self):
        with tempfile.TemporaryDirectory() as tmp:
            services_dir = pathlib.Path(tmp)
            (services_dir / "nova.yaml").write_text("service:\n  name: nova\n")

            self.assertEqual(
                validator.service_descriptor_paths(services_dir, ["nova"]),
                [services_dir / "nova.yaml"],
            )

    def test_validate_service_reports_missing_and_extra_paths(self):
        descriptor = {
            "service": {"name": "nova"},
            "chart": {},
            "secrets": [
                {"helm_key": "endpoints.identity.auth.admin.password"},
                {"helm_key": "conf.nova.database.connection"},
            ],
        }
        versions = {"charts": {"nova": "1.2.3"}}
        values = {
            "endpoints": {
                "identity": {
                    "auth": {
                        "admin": {"password": "default"},
                        "nova": {"password": "default"},
                    }
                }
            }
        }

        with tempfile.TemporaryDirectory() as tmp:
            descriptor_path = pathlib.Path(tmp) / "nova.yaml"
            descriptor_path.write_text("unused")
            args = argparse.Namespace(
                helm_command="helm",
                command_timeout=30,
                fallback_repo_url=validator.OPENSTACK_HELM_REPO_URL,
                ignore_path=[],
                update_cache=False,
            )

            with mock.patch.object(
                validator, "load_yaml", return_value=descriptor
            ), mock.patch.object(
                validator, "helm_show_values", return_value="unused"
            ), mock.patch.object(
                validator, "parse_yaml_text", return_value=values
            ):
                result = validator.validate_service(args, descriptor_path, versions)

        self.assertEqual(
            result.missing_paths, ["endpoints.identity.auth.nova.password"]
        )
        self.assertEqual(result.extra_paths, ["conf.nova.database.connection"])

    def test_update_cache_writes_non_operational_schema_metadata(self):
        descriptor = {"service": {"name": "keystone"}, "chart": {}, "secrets": []}
        with tempfile.TemporaryDirectory() as tmp:
            descriptor_path = pathlib.Path(tmp) / "keystone.yaml"
            validator.update_chart_schema_cache(
                descriptor_path,
                descriptor,
                "keystone",
                "keystone",
                "1.2.3",
                ["endpoints.identity.auth.admin.password"],
                {"endpoints.identity.auth.admin.password": "password"},
            )

            written = validator.load_yaml(descriptor_path)

        self.assertEqual(
            written["chart_secret_schema"]["sensitive_value_paths"],
            ["endpoints.identity.auth.admin.password"],
        )
        self.assertEqual(
            written["chart_secret_schema"]["sensitive_values"],
            {"endpoints.identity.auth.admin.password": "password"},
        )
        self.assertEqual(written["secrets"], [])


if __name__ == "__main__":
    unittest.main()
