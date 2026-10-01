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
            "endpoints": {
                "identity": {"auth": {"admin": {"password": "secret"}}},
                "oslo_cache": {"auth": {"memcache_secret_key": "key"}},
            },
            "tls": {"secretName": "existing-cert"},
            "manifests": {"secret_db": True},
            "conf": {"service_user": {"send_service_user_token": True}},
            "image": {"pullSecrets": [{"name": "registry"}]},
            "network": {"ssh": {"private_key": "", "public_key": ""}},
        }

        self.assertEqual(
            validator.discover_sensitive_paths(values),
            [
                "endpoints.identity.auth.admin.password",
                "endpoints.oslo_cache.auth.memcache_secret_key",
                "network.ssh.private_key",
                "network.ssh.public_key",
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
