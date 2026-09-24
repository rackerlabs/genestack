#!/usr/bin/env python3
"""Unit tests for default_password_detector.py."""

from __future__ import annotations

import base64
import importlib.util
import io
import json
import pathlib
import sys
import tempfile
import unittest
from argparse import Namespace
from contextlib import redirect_stderr, redirect_stdout
from unittest import mock

SCRIPT = pathlib.Path(__file__).with_name("default_password_detector.py")
SPEC = importlib.util.spec_from_file_location("default_password_detector", SCRIPT)
assert SPEC and SPEC.loader
module = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = module
SPEC.loader.exec_module(module)


def encoded(value: str) -> str:
    return base64.b64encode(value.encode()).decode()


def args() -> Namespace:
    return Namespace(
        helm_command="helm",
        kubectl_command="kubectl",
        helm_repo_name="openstack-helm",
        helm_repo_url="https://example.invalid/charts",
        namespace="openstack",
        command_timeout=30,
        quiet=True,
    )


class DefaultPasswordDetectorTests(unittest.TestCase):
    def write_yaml(self, content: str) -> str:
        handle = tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", delete=False)
        self.addCleanup(pathlib.Path(handle.name).unlink, missing_ok=True)
        with handle:
            handle.write(content)
        return handle.name

    def test_loads_only_exact_boolean_true_components_and_versions(self) -> None:
        components = self.write_yaml(
            "components:\n  cinder: true\n  glance: false\n  nova: 'true'\n"
        )
        versions = self.write_yaml("charts:\n  cinder: 2026.1.9+abc\n")
        self.assertEqual(module.load_enabled_services(components), ["cinder"])
        self.assertEqual(
            module.load_chart_versions(versions), {"cinder": "2026.1.9+abc"}
        )

    def test_extracts_sensitive_data_and_string_data_only(self) -> None:
        rendered = f"""
apiVersion: v1
kind: Secret
metadata:
  name: cinder-keystone-nova
data:
  OS_PASSWORD: {encoded('password')}
  OS_AUTH_URL: {encoded('http://keystone/v3')}
stringData:
  db_secret: default-secret
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: ignored
data:
  password: password
"""
        defaults, warnings = module.extract_default_secret_values(rendered, "cinder")
        values = {(item.secret_name, item.key): item.value for item in defaults}
        self.assertEqual(
            values,
            {
                ("cinder-keystone-nova", "OS_PASSWORD"): b"password",
                ("cinder-keystone-nova", "db_secret"): b"default-secret",
            },
        )
        self.assertEqual(warnings, [])

    def test_invalid_default_base64_becomes_warning(self) -> None:
        rendered = """
kind: Secret
metadata:
  name: bad-secret
data:
  password: not-base64!
"""
        defaults, warnings = module.extract_default_secret_values(rendered, "nova")
        self.assertEqual(defaults, [])
        self.assertEqual(len(warnings), 1)
        self.assertNotIn("not-base64", warnings[0].message)

    def test_compare_finds_match_and_ignores_rotated_value(self) -> None:
        defaults = [
            module.DefaultSecretValue("identity", "OS_PASSWORD", b"password"),
            module.DefaultSecretValue("database", "password", b"password"),
        ]
        live = {
            "identity": {"OS_PASSWORD": encoded("password")},
            "database": {"password": encoded("rotated")},
        }
        with mock.patch.object(
            module, "fetch_live_secret", side_effect=lambda name, _args: live[name]
        ):
            result = module.compare_defaults("cinder", "1.2.3", defaults, args())
        self.assertEqual(len(result.findings), 1)
        self.assertEqual(result.findings[0].secret_name, "identity")
        self.assertEqual(result.findings[0].key, "OS_PASSWORD")

    def test_missing_live_secret_and_key_are_warnings(self) -> None:
        defaults = [
            module.DefaultSecretValue("missing", "password", b"password"),
            module.DefaultSecretValue("partial", "token", b"token"),
        ]
        live = {"missing": None, "partial": {}}
        with mock.patch.object(
            module, "fetch_live_secret", side_effect=lambda name, _args: live[name]
        ):
            result = module.compare_defaults("nova", "1.2.3", defaults, args())
        self.assertEqual(len(result.warnings), 2)
        self.assertEqual(result.findings, [])

    def test_live_decode_error_is_warning_and_does_not_disclose_value(self) -> None:
        defaults = [
            module.DefaultSecretValue("identity", "OS_PASSWORD", b"password")
        ]
        with mock.patch.object(
            module,
            "fetch_live_secret",
            return_value={"OS_PASSWORD": "plain-default!"},
        ):
            result = module.compare_defaults("cinder", "1.2.3", defaults, args())
        self.assertEqual(len(result.warnings), 1)
        self.assertEqual(result.findings, [])
        self.assertNotIn("plain-default", result.warnings[0].message)

    def test_main_uses_mocked_helm_and_kubectl_responses(self) -> None:
        components = self.write_yaml("components:\n  cinder: true\n")
        versions = self.write_yaml("charts:\n  cinder: 1.2.3\n")
        rendered = f"""
kind: Secret
metadata:
  name: cinder-keystone-nova
data:
  OS_PASSWORD: {encoded('password')}
"""
        live = json.dumps({"data": {"OS_PASSWORD": encoded("password")}})
        responses = [
            module.CommandResult(0, rendered, ""),
            module.CommandResult(0, live, ""),
        ]
        stdout = io.StringIO()
        with mock.patch.object(
            module, "run_command", side_effect=responses
        ) as run, redirect_stdout(stdout):
            exit_code = module.main(
                [
                    "--components-file",
                    components,
                    "--chart-versions-file",
                    versions,
                    "--service",
                    "cinder",
                    "--format",
                    "json",
                    "--quiet",
                ]
            )
        self.assertEqual(exit_code, module.EXIT_FINDINGS)
        self.assertEqual(run.call_count, 2)
        self.assertEqual(json.loads(stdout.getvalue())["findings_count"], 1)

    def test_main_json_returns_findings_exit_code(self) -> None:
        components = self.write_yaml("components:\n  cinder: true\n")
        versions = self.write_yaml("charts:\n  cinder: 1.2.3\n")
        result = module.ServiceResult(
            service="cinder",
            chart_version="1.2.3",
            findings=[
                module.Finding(
                    "cinder", "1.2.3", "openstack", "identity", "OS_PASSWORD"
                )
            ],
        )
        stdout = io.StringIO()
        with mock.patch.object(module, "scan_service", return_value=result), redirect_stdout(
            stdout
        ):
            exit_code = module.main(
                [
                    "--components-file",
                    components,
                    "--chart-versions-file",
                    versions,
                    "--format",
                    "json",
                    "--quiet",
                ]
            )
        payload = json.loads(stdout.getvalue())
        self.assertEqual(exit_code, module.EXIT_FINDINGS)
        self.assertEqual(payload["findings_count"], 1)
        self.assertNotIn('"value":', stdout.getvalue())

    def test_main_text_returns_ok_without_findings(self) -> None:
        components = self.write_yaml("components:\n  cinder: true\n")
        versions = self.write_yaml("charts:\n  cinder: 1.2.3\n")
        result = module.ServiceResult("cinder", "1.2.3")
        stdout = io.StringIO()
        with mock.patch.object(module, "scan_service", return_value=result), redirect_stdout(
            stdout
        ):
            exit_code = module.main(
                [
                    "--components-file",
                    components,
                    "--chart-versions-file",
                    versions,
                    "--quiet",
                ]
            )
        self.assertEqual(exit_code, module.EXIT_OK)
        self.assertIn("findings=0", stdout.getvalue())

    def test_main_returns_error_for_service_scan_failure(self) -> None:
        components = self.write_yaml("components:\n  cinder: true\n")
        versions = self.write_yaml("charts:\n  cinder: 1.2.3\n")
        stdout = io.StringIO()
        stderr = io.StringIO()
        with mock.patch.object(
            module, "scan_service", side_effect=module.ScannerError("render failed")
        ), redirect_stdout(stdout), redirect_stderr(stderr):
            exit_code = module.main(
                [
                    "--components-file",
                    components,
                    "--chart-versions-file",
                    versions,
                    "--quiet",
                ]
            )
        self.assertEqual(exit_code, module.EXIT_ERROR)
        self.assertIn("render failed", stdout.getvalue())


if __name__ == "__main__":
    unittest.main()
