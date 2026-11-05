import contextlib
import io
import os
import subprocess
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts" / "agent"))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from codex_test_support import CONNECTOR, REPOSITORY, SCRIPTS, SESSION, owned_directory  # noqa: E402
import finalize_codex_auth_session as MODULE  # noqa: E402


DIGEST = "d" * 64


class FinalizeCodexAuthSessionTest(unittest.TestCase):
    def environment(self, **overrides):
        values = {"II_OS_CONNECTOR_URL": CONNECTOR, "II_OS_CODEX_AUTH_SESSION_ID": SESSION,
                  "II_OS_CODEX_AUTH_REPOSITORY": REPOSITORY, "II_OS_CODEX_SECRET_DIGEST": DIGEST,
                  "GITHUB_REPOSITORY": REPOSITORY, "GITHUB_RUN_ID": "100", "GITHUB_RUN_ATTEMPT": "1"}
        values.update(overrides)
        return {key: value for key, value in values.items() if value is not None}

    def test_posts_only_the_cleanup_proven_digest(self):
        with mock.patch.dict(os.environ, self.environment(), clear=True), \
                mock.patch.object(MODULE, "post_json") as post, contextlib.redirect_stdout(io.StringIO()) as out:
            self.assertEqual(MODULE.main(), 0)
        connector, route, body = post.call_args.args
        self.assertEqual((connector, route), (CONNECTOR, f"v1/codex-auth-sessions/{SESSION}/events"))
        self.assertEqual(body, {"status": "succeeded", "secretDigest": DIGEST, "runId": 100, "runAttempt": 1,
                                "runUrl": f"https://github.com/{REPOSITORY}/actions/runs/100/attempts/1"})
        self.assertEqual(out.getvalue(), "Codex authentication finalized after runtime cleanup proof.\n")

    def test_rejects_foreign_repository_or_malformed_digest(self):
        for overrides in ({"II_OS_CODEX_AUTH_REPOSITORY": "acme-co/other-app"},
                          {"II_OS_CODEX_SECRET_DIGEST": "D" * 64}, {"II_OS_CODEX_AUTH_SESSION_ID": "../x"}):
            with self.subTest(overrides=overrides), mock.patch.dict(os.environ, self.environment(**overrides), clear=True), \
                    mock.patch.object(MODULE, "post_json") as post:
                with self.assertRaises(MODULE.SessionFailure) as error:
                    MODULE.main()
            self.assertEqual(error.exception.code, "codex_auth_configuration_missing")
            post.assert_not_called()

    def test_refuses_to_start_without_a_valid_connector_setting(self):
        for connector, code in ((None, "ii_os_connector_missing"),
                                ("http://ii-os.example.com/api", "ii_os_connector_invalid"),
                                ("https://ii-os.example.com/api#x", "ii_os_connector_invalid")):
            with self.subTest(connector=connector), \
                    mock.patch.dict(os.environ, self.environment(II_OS_CONNECTOR_URL=connector), clear=True), \
                    mock.patch.object(MODULE, "post_json") as post:
                with self.assertRaises(MODULE.SessionFailure) as error:
                    MODULE.main()
            self.assertEqual(error.exception.code, code)
            self.assertIn("II_OS_CONNECTOR_URL", error.exception.detail)
            post.assert_not_called()

    def test_cli_names_the_missing_connector_setting(self):
        with owned_directory() as root:
            environment = {"PATH": os.environ.get("PATH", ""), "PYTHONDONTWRITEBYTECODE": "1",
                           **self.environment(II_OS_CONNECTOR_URL=None)}
            result = subprocess.run([sys.executable, str(SCRIPTS / "finalize_codex_auth_session.py")],
                                    env=environment, cwd=root, text=True, capture_output=True,
                                    timeout=20, check=False)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertIn("II_OS_CONNECTOR_URL", result.stderr)


if __name__ == "__main__":
    unittest.main()
