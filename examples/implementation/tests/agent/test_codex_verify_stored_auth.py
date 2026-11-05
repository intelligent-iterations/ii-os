import hashlib
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

from codex_test_support import SCRIPTS, owned_directory  # noqa: E402
import verify_stored_codex_auth as MODULE  # noqa: E402


AUTH = {"tokens": {"access_token": "synthetic-access-" * 5,
                   "refresh_token": "synthetic-refresh-" * 5}}


class StoredCredentialVerificationTest(unittest.TestCase):
    def test_output_attests_committed_refresh_instead_of_original_snapshot(self):
        with owned_directory() as root:
            encoded = json.dumps(AUTH)
            output = root / "output"

            def smoke(home, _):
                self.assertNotIn("CODEX_AUTH_JSON", os.environ)
                self.assertEqual((home / "auth.json").read_text(), encoded)
                self.assertEqual((home / "auth.json").stat().st_mode & 0o777, 0o600)

            def committed(kind, *, original_digest):
                self.assertEqual(kind, "codex-auth-verify")
                self.assertEqual(original_digest, hashlib.sha256(encoded.encode()).hexdigest())
                return {"secretDigest": "b" * 64, "secretUpdatedAt": "2026-10-30T20:00:00Z"}

            with mock.patch.dict(os.environ, {"CODEX_AUTH_JSON": encoded, "RUNNER_TEMP": str(root),
                                              "GITHUB_OUTPUT": str(output)}, clear=True), \
                    mock.patch.object(MODULE, "smoke_codex", smoke), \
                    mock.patch.object(MODULE, "committed_credential", committed):
                MODULE.main()
            self.assertEqual(output.read_text(), "secret_digest=" + "b" * 64 + "\n")
            self.assertEqual(list(root.glob("ii-os-stored-codex-*")), [])

    def test_missing_commit_withholds_success_output_after_smoke(self):
        with owned_directory() as root:
            output = root / "output"
            with mock.patch.dict(os.environ, {"CODEX_AUTH_JSON": json.dumps(AUTH), "RUNNER_TEMP": str(root),
                                              "GITHUB_OUTPUT": str(output)}, clear=True), \
                    mock.patch.object(MODULE, "smoke_codex"), \
                    mock.patch.object(MODULE, "committed_credential", side_effect=MODULE.SessionFailure(
                        "credential_refresh_unconfirmed", "synthetic missing receipt")):
                with self.assertRaises(MODULE.SessionFailure):
                    MODULE.main()
            self.assertFalse(output.exists())

    def test_api_key_or_incomplete_oauth_is_rejected_before_any_credential_write(self):
        for value in ({**AUTH, "OPENAI_API_KEY": "synthetic-forbidden-key-" * 4},
                      {"OPENAI_API_KEY": "synthetic-forbidden-key-" * 8},
                      {**AUTH, "auth_mode": "apikey"},
                      {"tokens": {"access_token": "synthetic-access-" * 8}},
                      {"tokens": {"access_token": "synthetic-access-" * 8, "refresh_token": " "}}):
            with self.subTest(keys=sorted(value)), owned_directory() as root:
                output = root / "output"
                written = []
                real_open = os.open

                def guarded_open(path, flags, *args, **kwargs):
                    if flags & os.O_CREAT and str(path).endswith("auth.json"):
                        written.append(str(path))
                    return real_open(path, flags, *args, **kwargs)

                with mock.patch.dict(os.environ, {"CODEX_AUTH_JSON": json.dumps(value), "RUNNER_TEMP": str(root),
                                                  "GITHUB_OUTPUT": str(output)}, clear=True), \
                        mock.patch.object(MODULE.os, "open", guarded_open), \
                        mock.patch.object(MODULE, "smoke_codex") as smoke, \
                        mock.patch.object(MODULE, "committed_credential") as committed:
                    with self.assertRaises(MODULE.SessionFailure) as error:
                        MODULE.main()
                    self.assertNotIn("CODEX_AUTH_JSON", os.environ)
                self.assertEqual(error.exception.code, "codex_auth_repository_secret_invalid")
                self.assertNotIn("synthetic-", str(error.exception))
                self.assertEqual(written, [])
                smoke.assert_not_called()
                committed.assert_not_called()
                self.assertFalse(output.exists())
                self.assertEqual(list(root.glob("ii-os-stored-codex-*")), [])

    def test_cli_failure_names_only_the_error_code(self):
        with owned_directory() as root:
            output = root / "output"
            secret = json.dumps({**AUTH, "OPENAI_API_KEY": "synthetic-forbidden-key-" * 4})
            result = subprocess.run(
                [sys.executable, str(SCRIPTS / "verify_stored_codex_auth.py")],
                env={"PATH": os.environ.get("PATH", ""), "PYTHONDONTWRITEBYTECODE": "1",
                     "CODEX_AUTH_JSON": secret, "RUNNER_TEMP": str(root), "GITHUB_OUTPUT": str(output)},
                cwd=root, text=True, capture_output=True, timeout=20, check=False,
            )
            self.assertEqual(result.returncode, 1)
            self.assertEqual(result.stdout, "")
            self.assertIn("codex_auth_repository_secret_invalid", result.stderr)
            self.assertNotIn("synthetic-", result.stderr)
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
