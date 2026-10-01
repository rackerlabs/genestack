#!/usr/bin/env python3
import argparse
import base64
import pathlib
import sys
import unittest
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import default_password_detector as detector


def encoded(value: str) -> str:
    return base64.b64encode(value.encode()).decode()


class DefaultPasswordDetectorTests(unittest.TestCase):
    def test_iter_secret_refs_maps_source_and_named_key_entries(self):
        descriptor = {
            "secrets": [
                {
                    "helm_key": "endpoints.identity.auth.nova.password",
                    "source_secret": "nova-admin",
                    "source_namespace": "openstack",
                    "data_key": "password",
                },
                {
                    "helm_key": "conf.example",
                    "name": "example-secret",
                    "namespace": "other",
                    "keys": {"password": "generate"},
                },
            ]
        }

        self.assertEqual(
            detector.iter_secret_refs(descriptor, "openstack"),
            [
                (
                    "endpoints.identity.auth.nova.password",
                    "openstack",
                    "nova-admin",
                    "password",
                ),
                ("conf.example.password", "other", "example-secret", "password"),
            ],
        )

    def test_iter_secret_refs_maps_named_keys_without_helm_key(self):
        descriptor = {
            "secrets": [
                {
                    "name": "mariadb",
                    "namespace": "openstack",
                    "keys": {
                        "root-password": "generate",
                        "password": "generate",
                    },
                }
            ]
        }

        self.assertEqual(
            detector.iter_secret_refs(descriptor, "mariadb-system"),
            [
                ("root-password", "openstack", "mariadb", "root-password"),
                ("password", "openstack", "mariadb", "password"),
            ],
        )

    def test_scan_service_reports_secret_matching_chart_default(self):
        descriptor = {
            "service": {"name": "nova"},
            "chart_secret_schema": {
                "chart_version": "1.2.3",
                "sensitive_values": {
                    "endpoints.identity.auth.nova.password": "password"
                },
            },
            "secrets": [
                {
                    "helm_key": "endpoints.identity.auth.nova.password",
                    "source_secret": "nova-admin",
                    "source_namespace": "openstack",
                    "data_key": "password",
                }
            ],
        }
        versions = {"charts": {"nova": "1.2.3"}}
        args = argparse.Namespace(
            kubectl_command="kubectl",
            helm_command="helm",
            command_timeout=30,
            fallback_repo_url=detector.schema.OPENSTACK_HELM_REPO_URL,
            ignore_path=[],
            refresh_chart=False,
        )

        with mock.patch.object(
            detector.schema, "load_yaml", return_value=descriptor
        ), mock.patch.object(
            detector,
            "kubectl_secret_data",
            return_value={"password": encoded("password")},
        ):
            findings = detector.scan_service(
                args, pathlib.Path("bin/services/nova.yaml"), versions
            )

        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].reason, "secret value matches chart default")

    def test_scan_service_ignores_randomized_secret(self):
        descriptor = {
            "service": {"name": "nova"},
            "chart_secret_schema": {
                "chart_version": "1.2.3",
                "sensitive_values": {
                    "endpoints.identity.auth.nova.password": "password"
                },
            },
            "secrets": [
                {
                    "helm_key": "endpoints.identity.auth.nova.password",
                    "source_secret": "nova-admin",
                    "source_namespace": "openstack",
                    "data_key": "password",
                }
            ],
        }
        versions = {"charts": {"nova": "1.2.3"}}
        args = argparse.Namespace(
            kubectl_command="kubectl",
            helm_command="helm",
            command_timeout=30,
            fallback_repo_url=detector.schema.OPENSTACK_HELM_REPO_URL,
            ignore_path=[],
            refresh_chart=False,
        )

        with mock.patch.object(
            detector.schema, "load_yaml", return_value=descriptor
        ), mock.patch.object(
            detector,
            "kubectl_secret_data",
            return_value={"password": encoded("not-the-default")},
        ):
            findings = detector.scan_service(
                args, pathlib.Path("bin/services/nova.yaml"), versions
            )

        self.assertEqual(findings, [])

    def test_scan_service_reports_missing_data_key(self):
        descriptor = {
            "service": {"name": "nova"},
            "chart_secret_schema": {
                "chart_version": "1.2.3",
                "sensitive_values": {
                    "endpoints.identity.auth.nova.password": "password"
                },
            },
            "secrets": [
                {
                    "helm_key": "endpoints.identity.auth.nova.password",
                    "source_secret": "nova-admin",
                    "source_namespace": "openstack",
                    "data_key": "password",
                }
            ],
        }
        versions = {"charts": {"nova": "1.2.3"}}
        args = argparse.Namespace(
            kubectl_command="kubectl",
            helm_command="helm",
            command_timeout=30,
            fallback_repo_url=detector.schema.OPENSTACK_HELM_REPO_URL,
            ignore_path=[],
            refresh_chart=False,
        )

        with mock.patch.object(
            detector.schema, "load_yaml", return_value=descriptor
        ), mock.patch.object(detector, "kubectl_secret_data", return_value={}):
            findings = detector.scan_service(
                args, pathlib.Path("bin/services/nova.yaml"), versions
            )

        self.assertEqual(len(findings), 1)
        self.assertIn("missing or empty", findings[0].reason)


if __name__ == "__main__":
    unittest.main()
