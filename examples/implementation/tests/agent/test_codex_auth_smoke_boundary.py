"""Python side of the trusted auth adapter boundary, with no provider invoked."""

import json
import os
import subprocess
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts" / "agent"))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from codex_test_support import REPOSITORY, owned_directory  # noqa: E402
import codex_github_secret_writer as writer  # noqa: E402
import verify_stored_codex_auth as verifier  # noqa: E402


AUTH = {"tokens": {"access_token": "synthetic-original-access-token",
                   "refresh_token": "synthetic-original-refresh-token"}}


class CodexAuthSmokeBoundaryTest(unittest.TestCase):
    def fixture(self, root):
        for relative in ("scratch", "state", "scratch/client", "scratch/client/codex", "scratch/client/smoke"):
            (root / relative).mkdir(mode=0o700)
        auth = root / "scratch/client/codex/auth.json"
        auth.write_text(json.dumps(AUTH))
        auth.chmod(0o600)
        return auth

    def test_secret_writer_rejects_unsafe_credentials_before_requesting_write_authority(self):
        for mutation in ("symlink", "hardlink", "readable", "parent", "api-key"):
            with self.subTest(mutation=mutation), owned_directory() as root:
                auth = self.fixture(root)
                if mutation == "symlink":
                    auth.rename(auth.with_name("original.json"))
                    auth.symlink_to("original.json")
                elif mutation == "hardlink":
                    os.link(auth, auth.with_name("alias.json"))
                elif mutation == "readable":
                    auth.chmod(0o644)
                elif mutation == "parent":
                    auth.parent.chmod(0o755)
                else:
                    auth.write_text(json.dumps({"OPENAI_API_KEY": "synthetic-api-key-" * 10}))
                with mock.patch.object(writer.subprocess, "run") as provider:
                    with self.assertRaises(writer.SecretWriterFailure) as failure:
                        writer.read_oauth_file(auth)
                self.assertEqual(failure.exception.code, "codex_auth_file_invalid")
                provider.assert_not_called()

    def test_stored_verifier_consumes_environment_secret_and_uses_private_runner_scratch(self):
        with owned_directory() as root:
            output = root / "github-output"
            environment = {"CODEX_AUTH_JSON": json.dumps(AUTH), "RUNNER_TEMP": str(root), "GITHUB_OUTPUT": str(output)}

            def smoke(codex_home, smoke_dir):
                self.assertNotIn("CODEX_AUTH_JSON", os.environ)
                self.assertEqual(codex_home.parent.parent, root)
                self.assertEqual(smoke_dir.parent, codex_home.parent)
                self.assertEqual((codex_home / "auth.json").stat().st_mode & 0o777, 0o600)
            with mock.patch.dict(os.environ, environment, clear=True), mock.patch.object(verifier, "smoke_codex", smoke), \
                    mock.patch.object(verifier, "committed_credential", return_value={"secretDigest": "c" * 64}):
                verifier.main()
            self.assertRegex(output.read_text(), r"^secret_digest=[a-f0-9]{64}\n$")
            self.assertEqual(list(root.glob("ii-os-stored-codex-*")), [])

    def test_secret_writer_receives_only_its_own_authority_and_revokes_it(self):
        with owned_directory() as root:
            auth = self.fixture(root)
            commands = []

            def run(command, **kwargs):
                commands.append(command)
                self.assertEqual(kwargs["env"]["GH_TOKEN"], "synthetic-one-time-writer")
                for name in ("CODEX_HOME", "CODEX_AUTH_JSON", "GITHUB_TOKEN", "ACTIONS_ID_TOKEN_REQUEST_TOKEN"):
                    self.assertNotIn(name, kwargs["env"])
                if command[1:3] == ["secret", "set"]:
                    self.assertEqual(json.loads(kwargs["input"]), AUTH)
                output = "2026-10-29T12:00:00Z\n"
                if "--include" in command:
                    output = "HTTP/2.0 200 OK\n\n" + output
                return subprocess.CompletedProcess(command, 0, output, "")
            with mock.patch.object(writer.subprocess, "run", run), \
                    mock.patch.dict(os.environ, {"CODEX_AUTH_JSON": "must-not-propagate", "GITHUB_TOKEN": "must-not-propagate"}):
                updated_at = writer.write_repository_secret(
                    REPOSITORY, auth, "synthetic-one-time-writer",
                    expected_secret_updated_at="2026-10-29T12:00:00Z", expected_absent=False,
                )
            self.assertEqual(updated_at, "2026-10-29T12:00:00Z")
            self.assertEqual(commands[-1], ["gh", "api", "--method", "DELETE", "/installation/token"])
            self.assertEqual(len(commands), 4)


if __name__ == "__main__":
    unittest.main()
