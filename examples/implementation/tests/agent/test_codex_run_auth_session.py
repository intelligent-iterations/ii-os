import contextlib
import hashlib
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts" / "agent"))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from codex_test_support import (  # noqa: E402
    CONNECTOR, REPOSITORY, SCRIPTS, SESSION, owned_directory,
)
import run_codex_auth_session as MODULE  # noqa: E402


SCRIPT = SCRIPTS / "run_codex_auth_session.py"


class RunCodexAuthSessionTest(unittest.TestCase):
    AUTH = {"auth_mode": "chatgpt", "tokens": {
        "access_token": "synthetic-access-" * 5,
        "refresh_token": "synthetic-refresh-" * 5,
    }}

    def run_session(self, *, saved=None, reauthenticate="false", failure=None,
                    refreshed=None, observed=None, connector=CONNECTOR):
        observed = {} if observed is None else observed
        observed.update(events=[], payloads=[], logins=0, smokes=0, commits=0, transports=0)
        with owned_directory() as root:
            environment = {
                "II_OS_CODEX_AUTH_SESSION_ID": SESSION,
                "II_OS_CODEX_AUTH_REPOSITORY": REPOSITORY,
                "II_OS_CODEX_AUTH_REAUTHENTICATE": reauthenticate,
                "GITHUB_REPOSITORY": REPOSITORY, "RUNNER_TEMP": str(root),
            }
            if connector is not None:
                environment["II_OS_CONNECTOR_URL"] = connector
            if saved is not None:
                environment["CODEX_AUTH_JSON"] = saved

            def app_server(home):
                self.assertNotIn("CODEX_AUTH_JSON", os.environ)
                observed["logins"] += 1
                server = mock.Mock()
                server.start_device_login.return_value = (
                    "synthetic-login", "https://auth.openai.com/codex/device", "ABCD-1234"
                )

                def finish(_):
                    target = home / "auth.json"
                    self.assertFalse(target.exists())
                    target.write_text(json.dumps(self.AUTH))
                    target.chmod(0o600)
                server.wait_for_login.side_effect = finish
                return server

            def smoke(home, directory):
                observed["smokes"] += 1
                self.assertNotIn("CODEX_AUTH_JSON", os.environ)
                observed["provider"] = os.environ.get("II_OS_CODEX_AUTH_CREDENTIAL_PROVIDER")
                auth = home / "auth.json"
                self.assertEqual(auth.stat().st_mode & 0o777, 0o600)
                observed["smoke_auth"] = json.loads(auth.read_text())
                if failure:
                    raise failure
                if refreshed:
                    auth.write_text(json.dumps(refreshed))

            def committed(kind):
                observed["commits"] += 1
                self.assertEqual(kind, "codex-auth")
                return {"secretUpdatedAt": "2026-01-01T00:00:00Z",
                        "secretDigest": hashlib.sha256(json.dumps(refreshed or self.AUTH).encode()).hexdigest(),
                        "changed": True, "generation": 1}

            def post(connector, route, event):
                observed["events"].append(event["status"])
                observed["payloads"].append(event)

            def transport(*args, **kwargs):
                observed["transports"] += 1
                raise AssertionError("no subprocess may start")

            try:
                with mock.patch.dict(os.environ, environment, clear=True), \
                        mock.patch.object(MODULE, "CodexAppServer", app_server), \
                        mock.patch.object(MODULE, "run_metadata", return_value={}), \
                        mock.patch.object(MODULE, "post_json", side_effect=post), \
                        mock.patch.object(MODULE, "smoke_codex", smoke), \
                        mock.patch.object(MODULE, "committed_credential", committed), \
                        mock.patch.object(subprocess, "run", transport), \
                        contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(MODULE.main(), 0)
                    self.assertNotIn("CODEX_AUTH_JSON", os.environ)
            finally:
                observed["leftovers"] = list(root.glob("ii-os-codex-auth-*"))
            self.assertEqual(observed["leftovers"], [])
        return observed

    def test_saved_oauth_skips_device_login_and_verifies_exactly_once(self):
        result = self.run_session(saved=json.dumps(self.AUTH))
        self.assertEqual((result["logins"], result["smokes"], result["commits"]), (0, 1, 1))
        self.assertEqual(result["events"], ["validating", "writing_secret", "awaiting_cleanup"])
        self.assertEqual(result["provider"], "github-actions")
        self.assertEqual(result["smoke_auth"], self.AUTH)

    def test_missing_saved_oauth_keeps_the_existing_device_flow(self):
        result = self.run_session()
        self.assertEqual((result["logins"], result["smokes"], result["commits"]), (1, 1, 1))
        self.assertEqual(result["events"], ["waiting_for_user", "validating", "writing_secret", "awaiting_cleanup"])
        self.assertEqual(result["provider"], "codex-device-login")

    def test_explicit_reauthentication_ignores_the_saved_snapshot(self):
        result = self.run_session(saved="malformed ignored snapshot", reauthenticate="true")
        self.assertEqual((result["logins"], result["smokes"], result["commits"]), (1, 1, 1))
        self.assertEqual(result["provider"], "codex-device-login")

    def test_native_refresh_uses_the_committed_provider_digest(self):
        refreshed = {"auth_mode": "chatgpt", "tokens": {
            "access_token": "synthetic-new-access-" * 5,
            "refresh_token": "synthetic-new-refresh-" * 5,
        }}
        result = self.run_session(saved=json.dumps(self.AUTH), refreshed=refreshed)
        self.assertEqual(result["payloads"][-1]["secretDigest"], hashlib.sha256(json.dumps(refreshed).encode()).hexdigest())
        self.assertEqual(set(result["payloads"][-1]), {"status", "secretUpdatedAt", "secretDigest"})
        self.assertEqual(result["smokes"], 1)

    def test_callbacks_carry_metadata_only(self):
        result = self.run_session()
        for payload in result["payloads"]:
            encoded = json.dumps(payload)
            self.assertNotIn("synthetic-access-", encoded)
            self.assertNotIn("synthetic-refresh-", encoded)

    def test_saved_credential_failures_never_fall_back_to_another_login_or_worker(self):
        for code in ("codex_auth_refresh_failed", "codex_auth_usage_limited",
                     "codex_auth_network_failed", "codex_auth_smoke_output_missing",
                     "codex_auth_smoke_timeout"):
            with self.subTest(code=code):
                observed = {}
                with self.assertRaises(MODULE.SessionFailure) as failure:
                    self.run_session(saved=json.dumps(self.AUTH),
                                     failure=MODULE.SessionFailure(code, "synthetic failure"), observed=observed)
                self.assertEqual(failure.exception.code, code)
                self.assertEqual((observed["logins"], observed["smokes"], observed["commits"]), (0, 1, 0))

    def test_malformed_or_api_key_cache_is_rejected_before_login_or_canary(self):
        for saved in ("not json", "x" * 49153, json.dumps(["x" * 120]),
                      json.dumps({"OPENAI_API_KEY": "synthetic-key-" * 20}),
                      json.dumps({**self.AUTH, "OPENAI_API_KEY": "synthetic-key-" * 20}),
                      json.dumps({**self.AUTH, "auth_mode": "apikey"}),
                      json.dumps({"tokens": {"access_token": "x" * 120}})):
            with self.subTest(shape=saved[:24]):
                observed = {}
                with self.assertRaises(MODULE.SessionFailure) as failure:
                    self.run_session(saved=saved, observed=observed)
                self.assertEqual(failure.exception.code, "codex_auth_repository_secret_invalid")
                self.assertEqual((observed["logins"], observed["smokes"], observed["commits"]), (0, 0, 0))
                self.assertEqual(observed["events"], [])

    def test_reauthentication_flag_is_strictly_boolean(self):
        observed = {}
        with self.assertRaises(MODULE.SessionFailure):
            self.run_session(reauthenticate="yes", observed=observed)
        self.assertEqual((observed["logins"], observed["smokes"]), (0, 0))

    def test_refuses_to_start_without_a_valid_connector_setting(self):
        for connector, code in ((None, "ii_os_connector_missing"), ("", "ii_os_connector_missing"),
                                ("http://ii-os.example.com/api", "ii_os_connector_invalid"),
                                ("https://alice@ii-os.example.com/api", "ii_os_connector_invalid"),
                                ("https://ii-os.example.com/api?x=1", "ii_os_connector_invalid")):
            for saved in (None, json.dumps(self.AUTH)):
                with self.subTest(connector=connector, saved=saved is not None):
                    observed = {}
                    with self.assertRaises(MODULE.SessionFailure) as failure:
                        self.run_session(saved=saved, connector=connector, observed=observed)
                    self.assertEqual(failure.exception.code, code)
                    self.assertIn("II_OS_CONNECTOR_URL", failure.exception.detail)
                    self.assertEqual((observed["logins"], observed["smokes"], observed["commits"],
                                      observed["transports"]), (0, 0, 0, 0))
                    self.assertEqual(observed["events"], [])

    def test_cli_names_the_missing_or_insecure_connector_setting(self):
        for connector in (None, "http://ii-os.example.com/api"):
            with self.subTest(connector=connector), owned_directory() as root:
                environment = {"PATH": os.environ.get("PATH", ""), "RUNNER_TEMP": str(root),
                               "PYTHONDONTWRITEBYTECODE": "1",
                               "II_OS_CODEX_AUTH_SESSION_ID": SESSION,
                               "II_OS_CODEX_AUTH_REPOSITORY": REPOSITORY,
                               "GITHUB_REPOSITORY": REPOSITORY, "GITHUB_RUN_ID": "100",
                               "CODEX_AUTH_JSON": json.dumps(self.AUTH)}
                if connector is not None:
                    environment["II_OS_CONNECTOR_URL"] = connector
                result = subprocess.run([sys.executable, str(SCRIPT)], env=environment, cwd=root,
                                        text=True, capture_output=True, timeout=20, check=False)
                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout, "")
                self.assertIn("II_OS_CONNECTOR_URL", result.stderr)
                self.assertNotIn("synthetic-access-", result.stderr)
                self.assertEqual(list(root.glob("ii-os-codex-auth-*")), [])

    def test_saved_auth_staging_does_not_follow_or_overwrite_existing_files(self):
        for symlink in (False, True):
            with self.subTest(symlink=symlink), owned_directory() as root:
                target = root / "preserve.json"
                target.write_text("preserve existing owned fixture")
                auth = root / "auth.json"
                if symlink:
                    auth.symlink_to(target)
                else:
                    auth.write_text("preserve existing owned fixture")
                with self.assertRaises(MODULE.SessionFailure):
                    MODULE.stage_saved_auth(auth, json.dumps(self.AUTH))
                self.assertEqual(target.read_text(), "preserve existing owned fixture")
                self.assertEqual(auth.read_text(), "preserve existing owned fixture")

    def test_managed_oauth_metadata_does_not_turn_a_null_api_key_into_api_auth(self):
        auth = {**self.AUTH, "OPENAI_API_KEY": None, "last_refresh": "synthetic-metadata"}
        result = self.run_session(saved=json.dumps(auth))
        self.assertEqual(result["smoke_auth"], auth)
        self.assertEqual(result["logins"], 0)

    def test_reusable_auth_must_be_valid_bounded_json(self) -> None:
        with tempfile.TemporaryDirectory() as root:
            auth_file = Path(root) / "auth.json"
            auth_file.write_text(json.dumps({"tokens": "x" * 120}))

            MODULE.wait_for_reusable_auth(auth_file, timeout=0.1)

    def test_missing_reusable_auth_reports_exact_failure(self) -> None:
        with tempfile.TemporaryDirectory() as root:
            with self.assertRaises(MODULE.SessionFailure) as context:
                MODULE.wait_for_reusable_auth(
                    Path(root) / "auth.json", timeout=0
                )

            self.assertEqual(context.exception.code, "codex_auth_file_missing")


if __name__ == "__main__":
    unittest.main()
