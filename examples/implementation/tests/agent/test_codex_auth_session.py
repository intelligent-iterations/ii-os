import json
import os
import subprocess
import sys
import tempfile
import unittest
import urllib.parse
from pathlib import Path
from unittest import mock

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts" / "agent"))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from codex_test_support import (  # noqa: E402
    CONNECTOR, SCRIPTS, SESSION, FakeServer, json_response, owned_directory,
)
import codex_auth_session_client as MODULE  # noqa: E402


EVENTS_ROUTE = f"v1/codex-auth-sessions/{SESSION}/events"


class CodexAuthSessionTest(unittest.TestCase):
    @staticmethod
    def runtime_smoke_result(transcript: str) -> dict:
        # Runtime-result shape of a canary refusal. Identifiers, usage and
        # paths are synthetic; no login or credential is stored.
        return {
            "verified": False,
            "outcome": {
                "schemaVersion": 1,
                "executionId": "synthetic-canary",
                "attemptId": "1",
                "started": True,
                "phase": "collection",
                "status": "failed",
                "cleanupConfirmed": True,
                "cleanup": [{"component": "network", "confirmed": True}],
            },
            "transcript": transcript,
        }

    def smoke_failure_code(self, envelope: dict) -> str:
        with owned_directory() as root:
            result = subprocess.CompletedProcess(
                [], 1, json.dumps(envelope), ""
            )
            with mock.patch.object(MODULE.subprocess, "run", return_value=result):
                with self.assertRaises(MODULE.SessionFailure) as context:
                    MODULE.smoke_codex(root / "codex", root)
            return context.exception.code

    def test_canary_refusal_is_not_a_network_failure_from_cleanup_metadata(self) -> None:
        transcript = json.dumps({
            "type": "item.completed",
            "item": {
                "type": "agent_message",
                "text": "I can't create ok.txt because repository writes "
                        "aren't authorized for this prompt.",
            },
        })
        result = self.runtime_smoke_result(transcript)
        self.assertEqual(
            self.smoke_failure_code(result), "codex_auth_smoke_output_missing"
        )

    def test_real_failure_categories_come_from_the_structured_transcript(self) -> None:
        for message, code in (
            ("refresh_token_reused", "codex_auth_refresh_failed"),
            ("rate limit exceeded", "codex_auth_usage_limited"),
            ("401 unauthorized", "codex_auth_request_unauthorized"),
            ("network connection failed", "codex_auth_network_failed"),
        ):
            with self.subTest(code=code):
                envelope = self.runtime_smoke_result(
                    json.dumps({"type": "error", "message": message})
                )
                self.assertEqual(self.smoke_failure_code(envelope), code)

    def test_metadata_without_a_transcript_does_not_invent_a_network_failure(self) -> None:
        result = self.runtime_smoke_result("")
        result["outcome"]["phase"] = "execution"
        self.assertEqual(
            self.smoke_failure_code(result), "codex_auth_smoke_failed"
        )

    def test_collection_failure_requires_started_and_confirmed_cleanup(self) -> None:
        for field, value in (("started", False), ("cleanupConfirmed", False),
                             ("status", "cleanup-unconfirmed")):
            with self.subTest(field=field):
                result = self.runtime_smoke_result("No canary was produced.")
                result["outcome"][field] = value
                self.assertEqual(
                    self.smoke_failure_code(result), "codex_auth_smoke_failed"
                )

    def test_smoke_uses_the_runtime_without_delivering_control_credentials_to_the_worker(self) -> None:
        with owned_directory() as root:
            smoke_dir = root / "smoke"
            smoke_dir.mkdir()
            state = root / "state"
            settings = {
                "II_OS_CONNECTOR_URL": CONNECTOR,
                "II_OS_AGENT_EXECUTION_DIR": str(root / "agent_execution"),
                "II_OS_CONTROLLER_STATE_DIR": str(state),
                "II_OS_CONTROLLER_ADMISSION_DIR": str(root / "admission"),
                "II_OS_CONTROLLER_SCRATCH_DIR": str(root / "scratch"),
                "II_OS_CREDENTIAL_BUDGET_CONTEXT": str(state / "credential-rotation/context.json"),
                "II_OS_CREDENTIAL_ROTATION_OIDC": json.dumps({"tokenUrl": "https://token.actions.githubusercontent.com/oidc",
                                                              "requestToken": "synthetic-request-token"}),
                "II_OS_RUNTIME_KIND": "codex-auth", "II_OS_RUNTIME_OBSERVER": "1",
                "II_OS_RUNTIME_CONTROLLER": "{}", "II_OS_CODEX_AUTH_SESSION_ID": SESSION,
                "GITHUB_REPOSITORY": "acme-co/example-app", "GITHUB_REPOSITORY_ID": "42",
                "GITHUB_RUN_ID": "100", "GITHUB_RUN_ATTEMPT": "1",
                "COORDINATOR_SOURCE_SHA": "a" * 40, "II_OS_RUNTIME_SOURCE_SHA": "b" * 40,
            }

            def run(command, **kwargs):
                (smoke_dir / "ok.txt").write_text("ok\n")
                self.assertEqual(command[:2], ["node", str(SCRIPTS / "runtime_codex_smoke.mjs")])
                self.assertEqual(command[2:], ["execute", str(root / "codex/auth.json"), str(smoke_dir)])
                self.assertEqual(kwargs["timeout"], 600)
                self.assertEqual(kwargs["env"]["II_OS_CODEX_AUTH_CREDENTIAL_PROVIDER"], "github-actions")
                for name, value in settings.items():
                    self.assertEqual(kwargs["env"][name], value)
                for name in ["ACTIONS_ID_TOKEN_REQUEST_TOKEN", "ACTIONS_ID_TOKEN_REQUEST_URL", "GH_TOKEN",
                             "GITHUB_TOKEN", "CODEX_AUTH_JSON", "OPENAI_API_KEY"]:
                    self.assertNotIn(name, kwargs["env"])
                return subprocess.CompletedProcess(command, 0, "", "")

            with mock.patch.dict(MODULE.os.environ, {
                "II_OS_CODEX_AUTH_CREDENTIAL_PROVIDER": "github-actions",
                "CODEX_AUTH_JSON": "synthetic-private-value",
                "OPENAI_API_KEY": "synthetic-forbidden-key",
                "ACTIONS_ID_TOKEN_REQUEST_TOKEN": "synthetic-request-token",
                **settings,
            }), mock.patch.object(MODULE.subprocess, "run", run):
                MODULE.smoke_codex(root / "codex", smoke_dir)

    def test_smoke_reports_safe_actionable_failure_categories(self) -> None:
        cases = (
            ("refresh_token_reused", "codex_auth_refresh_failed"),
            ("rate limit exceeded", "codex_auth_usage_limited"),
            ("401 unauthorized", "codex_auth_request_unauthorized"),
            ("network connection failed", "codex_auth_network_failed"),
        )
        for message, code in cases:
            with self.subTest(code=code), tempfile.TemporaryDirectory() as root:
                result = subprocess.CompletedProcess([], 1, "", message)
                with mock.patch.object(
                    MODULE.subprocess, "run", return_value=result
                ):
                    with self.assertRaises(MODULE.SessionFailure) as context:
                        MODULE.smoke_codex(Path(root) / "codex", Path(root))
                self.assertEqual(context.exception.code, code)

    def test_smoke_timeout_is_actionable(self) -> None:
        with tempfile.TemporaryDirectory() as root:
            timeout = subprocess.TimeoutExpired(["codex"], 180)
            with mock.patch.object(MODULE.subprocess, "run", side_effect=timeout):
                with self.assertRaises(MODULE.SessionFailure) as context:
                    MODULE.smoke_codex(Path(root) / "codex", Path(root))
            self.assertEqual(context.exception.code, "codex_auth_smoke_timeout")

    def test_connector_comes_from_the_named_setting_and_rejects_unsafe_values(self) -> None:
        with self.assertRaises(MODULE.SessionFailure) as missing:
            MODULE.configured_connector({})
        self.assertEqual(missing.exception.code, "ii_os_connector_missing")
        self.assertIn("II_OS_CONNECTOR_URL", missing.exception.detail)
        for value in ("http://ii-os.example.com/api", "ftp://ii-os.example.com/api",
                      "https://alice@ii-os.example.com/api", "https://:x@ii-os.example.com/api",
                      "https://ii-os.example.com/api?route=x", "https://ii-os.example.com/api?",
                      "https://ii-os.example.com/api#fragment", "https:///api",
                      "https://ii-os.example.com:notaport/api", "https://ii-os.example.com/a pi",
                      "ii-os.example.com/api", CONNECTOR + "/", " " + CONNECTOR, CONNECTOR + "\n"):
            with self.subTest(value=value):
                with self.assertRaises(MODULE.SessionFailure) as invalid:
                    MODULE.configured_connector({"II_OS_CONNECTOR_URL": value})
                self.assertEqual(invalid.exception.code, "ii_os_connector_invalid")
                self.assertIn("II_OS_CONNECTOR_URL", invalid.exception.detail)
        self.assertEqual(MODULE.configured_connector({"II_OS_CONNECTOR_URL": CONNECTOR}), CONNECTOR)
        for loopback in ("http://127.0.0.1:8080/api", "http://localhost:8080/api"):
            self.assertEqual(MODULE.configured_connector({"II_OS_CONNECTOR_URL": loopback}), loopback)

    def test_oidc_audience_is_the_configured_connector_session_route(self) -> None:
        with mock.patch.dict(MODULE.os.environ, {"II_OS_CONNECTOR_URL": CONNECTOR}, clear=True):
            self.assertEqual(MODULE.oidc_audience(), CONNECTOR + "/v1/codex-auth-sessions")
        with mock.patch.dict(MODULE.os.environ, {}, clear=True):
            with self.assertRaises(MODULE.SessionFailure) as missing:
                MODULE.oidc_audience()
        self.assertEqual(missing.exception.code, "ii_os_connector_missing")

    def test_connector_url_keeps_credentials_out_of_query(self) -> None:
        with mock.patch.dict(MODULE.os.environ, {"II_OS_CONNECTOR_URL": CONNECTOR}, clear=True):
            result = MODULE.connector_url(CONNECTOR, EVENTS_ROUTE)

        self.assertEqual(
            result,
            CONNECTOR + "?route=v1%2Fcodex-auth-sessions%2F" + SESSION + "%2Fevents",
        )
        self.assertNotIn("token", result)

    def test_connector_rejects_insecure_remote_origin(self) -> None:
        with mock.patch.dict(MODULE.os.environ, {"II_OS_CONNECTOR_URL": "http://ii-os.example.com/api"}, clear=True):
            with self.assertRaises(MODULE.SessionFailure) as context:
                MODULE.connector_url("http://ii-os.example.com/api", EVENTS_ROUTE)

        self.assertEqual(context.exception.code, "ii_os_connector_invalid")

    def test_connector_rejects_path_traversal_and_unpinned_origins(self) -> None:
        with mock.patch.dict(MODULE.os.environ, {"II_OS_CONNECTOR_URL": CONNECTOR}, clear=True):
            for base, route in (
                ("https://other.example.com/api", "v1/session/events"),
                (CONNECTOR, "v1/session/../events"),
                (CONNECTOR, "v1/session//events"),
                (CONNECTOR, "v2/session/events"),
            ):
                with self.subTest(base=base, route=route):
                    with self.assertRaises(MODULE.SessionFailure):
                        MODULE.connector_url(base, route)

    def test_openai_challenge_and_session_are_strictly_bounded(self) -> None:
        self.assertEqual(MODULE.DEVICE_URL, "https://auth.openai.com/codex/device")
        self.assertIsNotNone(MODULE.USER_CODE.fullmatch("ABCD-12345"))
        self.assertIsNone(MODULE.USER_CODE.fullmatch("abcd-12345"))
        self.assertIsNotNone(MODULE.SESSION_ID.fullmatch(SESSION))
        self.assertIsNone(MODULE.SESSION_ID.fullmatch("../session"))

    def test_codex_subprocess_environment_drops_control_credentials(self) -> None:
        env = MODULE.sanitized_environment(
            codex_home=Path("/tmp/codex"),
            source={
                "II_OS_TOKEN": "workflow-token",
                "GITHUB_TOKEN": "github-token",
                "GH_TOKEN": "gh-token",
                "ACTIONS_ID_TOKEN_REQUEST_TOKEN": "oidc-request-token",
                "ACTIONS_ID_TOKEN_REQUEST_URL": "https://example.test/oidc",
                "UNTRUSTED_RUNNER_VALUE": "must-not-reach-codex",
            },
        )

        self.assertEqual(env["CODEX_HOME"], "/tmp/codex")
        self.assertEqual(env["HOME"], "/tmp")
        self.assertNotIn("UNTRUSTED_RUNNER_VALUE", env)
        for name in (
            "II_OS_TOKEN",
            "GITHUB_TOKEN",
            "GH_TOKEN",
            "ACTIONS_ID_TOKEN_REQUEST_TOKEN",
            "ACTIONS_ID_TOKEN_REQUEST_URL",
        ):
            self.assertNotIn(name, env)

    def test_oidc_request_token_can_only_go_to_github_actions(self) -> None:
        self.assertTrue(
            MODULE.valid_github_oidc_request_url(
                "https://vstoken.actions.githubusercontent.com/oidc?request=x"
            )
        )
        self.assertTrue(
            MODULE.valid_github_oidc_request_url(
                "https://actions.githubusercontent.com/oidc?request=x"
            )
        )
        for value in (
            "https://actions.githubusercontent.com.evil.example/oidc",
            "https://user@vstoken.actions.githubusercontent.com/oidc",
            "http://vstoken.actions.githubusercontent.com/oidc",
        ):
            self.assertFalse(MODULE.valid_github_oidc_request_url(value))

    def test_oidc_request_accepts_bounded_github_jwt(self) -> None:
        url = "https://vstoken.actions.githubusercontent.com/oidc?request=x"
        token = "x" * 8192

        self.assertEqual(
            MODULE.github_oidc_request(
                {
                    "ACTIONS_ID_TOKEN_REQUEST_URL": url,
                    "ACTIONS_ID_TOKEN_REQUEST_TOKEN": token,
                }
            ),
            (url, token),
        )

    def test_oidc_request_distinguishes_missing_and_invalid(self) -> None:
        with self.assertRaises(MODULE.SessionFailure) as missing:
            MODULE.github_oidc_request({})
        self.assertEqual(missing.exception.code, "github_actions_oidc_missing")

        with self.assertRaises(MODULE.SessionFailure) as invalid:
            MODULE.github_oidc_request(
                {
                    "ACTIONS_ID_TOKEN_REQUEST_URL": (
                        "https://vstoken.actions.githubusercontent.com/oidc"
                    ),
                    "ACTIONS_ID_TOKEN_REQUEST_TOKEN": (
                        "x"
                        * (MODULE.MAX_GITHUB_OIDC_REQUEST_TOKEN_CHARS + 1)
                    ),
                }
            )
        self.assertEqual(invalid.exception.code, "github_actions_oidc_invalid")

    def test_failed_callback_debit_stops_before_oidc_or_connector_transport(self) -> None:
        with owned_directory() as root:
            context = root / "state/credential-rotation/context.json"
            settings = {
                "II_OS_CONNECTOR_URL": CONNECTOR,
                "II_OS_AGENT_EXECUTION_DIR": str(root / "agent_execution"),
                "II_OS_CONTROLLER_STATE_DIR": str(root / "state"),
                "II_OS_CONTROLLER_ADMISSION_DIR": str(root / "admission"),
                "II_OS_CONTROLLER_SCRATCH_DIR": str(root / "scratch"),
                "II_OS_CREDENTIAL_BUDGET_CONTEXT": str(context),
            }
            with mock.patch.dict(MODULE.os.environ, {
                **settings,
                "GITHUB_TOKEN": "synthetic-forbidden-token",
                "ACTIONS_ID_TOKEN_REQUEST_TOKEN": "synthetic-request-token",
                "II_OS_CREDENTIAL_ROTATION_OIDC": "synthetic-oidc",
            }, clear=True), mock.patch.object(MODULE.subprocess, "run", return_value=
                    subprocess.CompletedProcess([], 1, "", "")) as charge, \
                    mock.patch.object(MODULE, "github_oidc_token") as oidc:
                with self.assertRaises(MODULE.SessionFailure) as error:
                    MODULE.post_json(CONNECTOR, EVENTS_ROUTE, {})
        self.assertEqual(error.exception.code, "credential_budget_exhausted")
        self.assertEqual(charge.call_count, 1)
        command, environment = charge.call_args.args[0], charge.call_args.kwargs["env"]
        self.assertEqual(command, ["node", str(SCRIPTS / "codex_credential_rotation.mjs"), "charge"])
        self.assertEqual({name: environment[name] for name in settings}, settings)
        for name in ("GITHUB_TOKEN", "ACTIONS_ID_TOKEN_REQUEST_TOKEN", "II_OS_CREDENTIAL_ROTATION_OIDC"):
            self.assertNotIn(name, environment)
        oidc.assert_not_called()

    def test_callback_budget_must_live_in_the_controller_state_directory(self) -> None:
        for state, context in (
            (None, "/elsewhere/credential-rotation/context.json"),
            ("relative/state", "relative/state/credential-rotation/context.json"),
            ("/private-state", "/other-state/credential-rotation/context.json"),
            ("/private-state/../x", "/x/credential-rotation/context.json"),
        ):
            environment = {"II_OS_CONNECTOR_URL": CONNECTOR, "II_OS_CREDENTIAL_BUDGET_CONTEXT": context}
            if state is not None:
                environment["II_OS_CONTROLLER_STATE_DIR"] = state
            with self.subTest(state=state), mock.patch.dict(MODULE.os.environ, environment, clear=True), \
                    mock.patch.object(MODULE.subprocess, "run") as charge, \
                    mock.patch.object(MODULE, "github_oidc_token") as oidc:
                with self.assertRaises(MODULE.SessionFailure) as error:
                    MODULE.post_json(CONNECTOR, EVENTS_ROUTE, {})
            self.assertEqual(error.exception.code, "credential_budget_invalid")
            charge.assert_not_called()
            oidc.assert_not_called()


class CodexAuthTransportTest(unittest.TestCase):
    """Loopback servers stand in for ii-os and the GitHub OIDC issuer."""

    def setUp(self) -> None:
        proxies = mock.patch.object(MODULE.urllib.request, "getproxies", return_value={})
        proxies.start()
        self.addCleanup(proxies.stop)

    def connector_env(self, server: FakeServer, **extra: str):
        return mock.patch.dict(MODULE.os.environ, {"II_OS_CONNECTOR_URL": server.base + "/api", **extra}, clear=True)

    def test_callback_posts_metadata_with_the_identity_to_the_configured_route(self) -> None:
        with FakeServer(lambda *_: json_response({"data": {"status": "validating"}})) as server, \
                self.connector_env(server):
            result = MODULE.post_json(server.base + "/api", EVENTS_ROUTE, {"status": "validating"},
                                      identity_token="synthetic-identity")
        self.assertEqual(result, {"data": {"status": "validating"}})
        (request,) = server.requests
        self.assertEqual(request["method"], "POST")
        self.assertEqual(urllib.parse.urlsplit(request["path"]).path, "/api")
        self.assertEqual(urllib.parse.parse_qs(urllib.parse.urlsplit(request["path"]).query),
                         {"route": [EVENTS_ROUTE]})
        self.assertEqual(request["headers"]["Authorization"], "Bearer synthetic-identity")
        self.assertEqual(json.loads(request["body"]), {"status": "validating"})

    def test_callback_never_follows_a_redirect(self) -> None:
        def respond(method, path, headers, body):
            if path.startswith("/api"):
                return 302, {"Location": "/elsewhere"}, b""
            return json_response({"data": {}})

        with FakeServer(respond) as server, self.connector_env(server):
            with self.assertRaises(MODULE.SessionFailure) as error:
                MODULE.post_json(server.base + "/api", EVENTS_ROUTE, {"status": "validating"},
                                 identity_token="synthetic-identity")
        self.assertEqual(error.exception.code, "ii_os_callback_failed")
        self.assertEqual([request["path"].split("?")[0] for request in server.requests], ["/api"])

    def test_callback_response_is_bounded(self) -> None:
        oversized = {"data": {}, "padding": "x" * (MODULE.MAX_RESPONSE_BYTES + 1)}
        with FakeServer(lambda *_: json_response(oversized)) as server, self.connector_env(server):
            with self.assertRaises(MODULE.SessionFailure) as error:
                MODULE.post_json(server.base + "/api", EVENTS_ROUTE, {"status": "validating"},
                                 identity_token="synthetic-identity")
        self.assertEqual(error.exception.code, "ii_os_callback_failed")
        self.assertEqual(len(server.requests), 1)

    def oidc_token(self, respond):
        with FakeServer(respond) as server, self.connector_env(
            server,
            ACTIONS_ID_TOKEN_REQUEST_URL=server.base + "/oidc?request=synthetic",
            ACTIONS_ID_TOKEN_REQUEST_TOKEN="synthetic-request-token",
        ), mock.patch.object(MODULE, "valid_github_oidc_request_url", return_value=True):
            try:
                return MODULE.github_oidc_token(), server
            except MODULE.SessionFailure as error:
                return error, server

    def test_oidc_token_is_requested_for_the_connector_audience(self) -> None:
        token, server = self.oidc_token(lambda *_: json_response({"value": "t" * 200}))
        self.assertEqual(token, "t" * 200)
        (request,) = server.requests
        query = urllib.parse.parse_qs(urllib.parse.urlsplit(request["path"]).query)
        self.assertEqual(query["audience"], [server.base + "/api/v1/codex-auth-sessions"])
        self.assertEqual(request["headers"]["Authorization"], "Bearer synthetic-request-token")

    def test_oidc_request_token_never_follows_a_redirect(self) -> None:
        def respond(method, path, headers, body):
            if path.startswith("/oidc"):
                return 302, {"Location": "/captured"}, b""
            return json_response({"value": "t" * 200})

        error, server = self.oidc_token(respond)
        self.assertIsInstance(error, MODULE.SessionFailure)
        self.assertEqual(error.code, "github_actions_oidc_failed")
        self.assertEqual([request["path"].split("?")[0] for request in server.requests], ["/oidc"])

    def test_oidc_response_is_bounded(self) -> None:
        oversized = {"value": "t" * 200, "padding": "x" * (MODULE.MAX_RESPONSE_BYTES + 1)}
        error, _ = self.oidc_token(lambda *_: json_response(oversized))
        self.assertIsInstance(error, MODULE.SessionFailure)
        self.assertEqual(error.code, "github_actions_oidc_failed")


if __name__ == "__main__":
    unittest.main()
