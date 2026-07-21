#!/usr/bin/env python3
"""Contract tests for the LensCloud Infra failure message envelope."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT / "bench-command-runner" / "runner.py"
CATALOG = ROOT / "bench-command-runner" / "message_catalog.v1.json"


class MessageEnvelopeTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.root = Path(self.tempdir.name)
        self.bench_path = self.root / "frappe-bench"
        self.request_dir = self.root / "request"
        self.secret_dir = self.root / "oauth-secret"
        self.site = "runner-test.localhost"
        self.request_dir.mkdir()
        self.secret_dir.mkdir()
        (self.secret_dir / "client_secret").write_text("must-not-leak-oauth-secret\n", encoding="utf-8")
        site_root = self.bench_path / "sites" / self.site
        site_root.mkdir(parents=True)
        (site_root / "site_config.json").write_text(
            json.dumps(
                {
                    "db_name": "runner_test",
                    "db_password": "must-not-leak-db-password",
                    "maintenance_mode": 0,
                }
            )
            + "\n",
            encoding="utf-8",
        )

    def tearDown(self) -> None:
        self.tempdir.cleanup()

    def run_command(
        self,
        name: str,
        command: str,
        args: dict,
        *,
        target: dict | None = None,
        expected_exit: int = 1,
        extra_env: dict[str, str] | None = None,
        timeout_seconds: int = 60,
    ) -> dict:
        request_path = self.request_dir / f"{name}.json"
        termination_path = self.request_dir / f"{name}.termination.json"
        request = {
            "apiVersion": "lenscloud.io/v1",
            "kind": "BenchCommand",
            "commandId": f"local-{name}",
            "command": command,
            "target": target
            or {
                "namespace": "lenscloud-runtime-eu",
                "bench": "runner-test-bench",
                "site": self.site,
            },
            "args": args,
            "timeoutSeconds": timeout_seconds,
        }
        request_path.write_text(json.dumps(request, sort_keys=True), encoding="utf-8")
        env = dict(os.environ)
        env.update(
            {
                "BENCH_PATH": str(self.bench_path),
                "BENCH_COMMAND_REQUEST": str(request_path),
                "BENCH_COMMAND_TERMINATION_LOG": str(termination_path),
                "LENS_COMMAND_OAUTH_CLIENT_SECRET_PATH": str(self.secret_dir / "client_secret"),
                "LENS_COMMAND_FAKE_FRAPPE_SETUP": "1",
            }
        )
        if extra_env:
            env.update(extra_env)
        completed = subprocess.run(
            [sys.executable, str(RUNNER)],
            cwd=str(ROOT),
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        self.assertEqual(
            expected_exit,
            completed.returncode,
            f"unexpected exit for {name}: stdout={completed.stdout} stderr={completed.stderr}",
        )
        payload = json.loads(termination_path.read_text(encoding="utf-8"))
        encoded = json.dumps(payload, sort_keys=True)
        for canary in (
            "must-not-leak",
            "db_password",
            "admin_password",
            "client_secret",
            "token=",
            "private_key",
            "BEGIN ",
        ):
            self.assertNotIn(canary, encoded)
        return payload

    def assert_message(self, payload: dict, message_id: str) -> dict:
        self.assertIn("message", payload)
        message = payload["message"]
        self.assertEqual(message_id, message["message_id"])
        self.assertEqual("Error", message["message_type"])
        self.assertEqual("Runner", message["source"])
        self.assertEqual("Platform", message["destination"])
        self.assertIsInstance(message["params"], dict)
        self.assertEqual(payload["command"], message["params"]["operation"])
        self.assertTrue(message["safe_summary"])
        self.assertIsNone(message["details_ref"])
        return message

    def test_catalog_contains_runner_ids(self) -> None:
        catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
        ids = {item["message_id"] for item in catalog["messages"]}
        self.assertEqual(
            {
                "LC-INFRA-RUNNER-0001",
                "LC-INFRA-RUNNER-0002",
                "LC-INFRA-STORAGE-0001",
                "LC-INFRA-UNKNOWN-0001",
                "LC-INFRA-QUEUE-0001",
                "LC-INFRA-BOOTSTRAP-0001",
                "LC-INFRA-TIMEOUT-0001",
                "LC-INFRA-COMMAND-0001",
            },
            ids,
        )

    def test_every_failed_poc_operation_returns_nested_message(self) -> None:
        failures = [
            ("bootstrap_unsupported", "site_bootstrap.install_apps", {"install_apps": [{"app": "erpnext"}]}, 0),
            ("setup_status_missing_storage", "site_setup.status", {}, 1),
            ("setup_complete_sensitive", "site_setup.complete", {"admin_password": "must-not-leak"}, 1),
            ("oauth_status_bad_args", "oauth.status", {"provider": "Bad Provider!"}, 1),
            (
                "oauth_configure_secret_arg",
                "oauth.configure",
                {"provider": "platform_oauth", "provider_name": "Platform OAuth", "client_secret": "must-not-leak"},
                1,
            ),
        ]
        missing_target = {
            "namespace": "lenscloud-runtime-eu",
            "bench": "runner-test-bench",
            "site": "missing.localhost",
        }
        for name, command, args, expected_exit in failures:
            target = missing_target if name == "setup_status_missing_storage" else None
            payload = self.run_command(name, command, args, target=target, expected_exit=expected_exit)
            self.assertIn("message", payload, name)
            self.assertIsInstance(payload["message"]["params"], dict, name)

    def test_known_failure_classifications(self) -> None:
        unsupported = self.run_command(
            "unsupported",
            "site_bootstrap.install_apps",
            {"install_apps": [{"app": "erpnext"}]},
            expected_exit=0,
        )
        self.assert_message(unsupported, "LC-INFRA-COMMAND-0001")

        storage = self.run_command(
            "storage",
            "site_setup.status",
            {},
            target={
                "namespace": "lenscloud-runtime-eu",
                "bench": "runner-test-bench",
                "site": "missing.localhost",
            },
        )
        storage_message = self.assert_message(storage, "LC-INFRA-STORAGE-0001")
        self.assertEqual("bench-sites", storage_message["params"]["mount_kind"])

        queue = self.run_command(
            "queue",
            "site_setup.complete",
            {"language": "English"},
            expected_exit=2,
            extra_env={"LENS_COMMAND_FAKE_SETUP_QUEUE_OVERLOAD": "1"},
        )
        self.assert_message(queue, "LC-INFRA-QUEUE-0001")

        timeout = self.run_command(
            "timeout",
            "oauth.status",
            {"provider": "platform_oauth"},
            expected_exit=1,
            extra_env={"LENS_COMMAND_FAKE_TIMEOUT_COMMAND": "oauth.status"},
            timeout_seconds=45,
        )
        timeout_message = self.assert_message(timeout, "LC-INFRA-TIMEOUT-0001")
        self.assertEqual(45, timeout_message["params"]["timeout_seconds"])

    def test_bootstrap_unknown_generic_and_success_contracts(self) -> None:
        bootstrap_a = self.run_command(
            "bootstrap_a",
            "site_bootstrap.install_apps",
            {"install_apps": [{"app": "erpnext"}]},
            expected_exit=2,
            extra_env={
                "LENS_COMMAND_ENABLE_APP_AWARE_COMMANDS": "1",
                "LENS_COMMAND_FAKE_APP_INSTALL_FAIL": "erpnext",
            },
        )
        bootstrap_message = self.assert_message(bootstrap_a, "LC-INFRA-BOOTSTRAP-0001")
        self.assertEqual("erpnext", bootstrap_message["params"]["app"])

        bootstrap_b = self.run_command(
            "bootstrap_b",
            "site_bootstrap.install_apps",
            {"install_apps": [{"app": "erpnext"}]},
            expected_exit=2,
            extra_env={
                "LENS_COMMAND_ENABLE_APP_AWARE_COMMANDS": "1",
                "LENS_COMMAND_FAKE_APP_INSTALL_FAIL": "erpnext",
            },
        )
        self.assertEqual(
            bootstrap_a["message"]["message_id"],
            bootstrap_b["message"]["message_id"],
            "volatile command IDs must not change stable message identity",
        )

        generic = self.run_command(
            "generic",
            "site_setup.complete",
            {"admin_password": "must-not-leak"},
            expected_exit=1,
        )
        self.assert_message(generic, "LC-INFRA-RUNNER-0002")

        unknown = self.run_command(
            "unknown",
            "oauth.status",
            {"provider": "platform_oauth"},
            expected_exit=1,
            extra_env={"LENS_COMMAND_FORCE_UNKNOWN_FAILURE": "1"},
        )
        self.assert_message(unknown, "LC-INFRA-UNKNOWN-0001")

        success = self.run_command(
            "success",
            "site_setup.status",
            {},
            expected_exit=0,
        )
        self.assertEqual("Succeeded", success["phase"])
        self.assertNotIn("message", success)
        self.assertIn("display", success)


if __name__ == "__main__":
    unittest.main()
