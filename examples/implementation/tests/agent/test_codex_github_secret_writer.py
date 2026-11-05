import contextlib
import io
import json
import os
import subprocess
import sys
import types
import unittest
from pathlib import Path
from unittest import mock

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts" / "agent"))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from codex_test_support import REPOSITORY, SCRIPTS, owned_directory  # noqa: E402
import codex_github_secret_writer as MODULE  # noqa: E402


SCRIPT = SCRIPTS / "codex_github_secret_writer.py"
TOKEN = "synthetic-writer-token"
VERSION = "2026-10-30T20:00:00Z"
BEFORE = "HTTP/2.0 200 OK\ncontent-type: application/json\n\n" + VERSION + "\n"
REVOKE = ["gh", "api", "--method", "DELETE", "/installation/token"]


def write(repository, path, token=TOKEN, **options):
    return MODULE.write_repository_secret(
        repository, path, token, expected_secret_updated_at=options.get("expected", VERSION),
        expected_absent=options.get("absent", False),
    )


def candidate(root):
    private = root / "private"
    private.mkdir(mode=0o700)
    path = private / "auth.json"
    path.write_text(json.dumps({"tokens": {
        "access_token": "synthetic-access-" + "a" * 64,
        "refresh_token": "synthetic-refresh-" + "b" * 64,
    }}))
    path.chmod(0o600)
    return path


def github(command, **options):
    output = BEFORE if "--include" in command else VERSION if "--jq" in command else ""
    return subprocess.CompletedProcess(command, 0, output, "")


class GitHubSecretWriterTest(unittest.TestCase):
    def test_exact_key_stdin_only_and_revoke_before_return(self):
        with owned_directory() as root:
            path = candidate(root)
            calls = []

            def run(command, **options):
                calls.append(command)
                self.assertNotIn(TOKEN, command)
                self.assertEqual(options["env"]["GH_TOKEN"], TOKEN)
                self.assertNotIn("OPENAI_API_KEY", options["env"])
                self.assertNotIn("GITHUB_TOKEN", options["env"])
                self.assertNotIn("ACTIONS_ID_TOKEN_REQUEST_TOKEN", options["env"])
                if command[1:3] == ["secret", "set"]:
                    self.assertEqual(command, ["gh", "secret", "set", "CODEX_AUTH_JSON", "--repo", REPOSITORY])
                    self.assertEqual(options["input"], path.read_text())
                else:
                    self.assertNotIn("input", options)
                return github(command, **options)

            with mock.patch.object(MODULE.subprocess, "run", side_effect=run):
                self.assertEqual(write(REPOSITORY, path), VERSION)
            self.assertEqual(len(calls), 4)
            self.assertEqual(calls[-1], REVOKE)

    def test_write_failure_and_unknown_transport_still_revoke(self):
        for failure in (subprocess.CompletedProcess([], 1, "", "synthetic secret error"),
                        subprocess.TimeoutExpired(["gh"], 60)):
            with self.subTest(failure=type(failure).__name__), owned_directory() as root:
                path = candidate(root)
                with mock.patch.object(MODULE.subprocess, "run", side_effect=[
                    subprocess.CompletedProcess([], 0, BEFORE, ""),
                    failure, subprocess.CompletedProcess([], 0, "", ""),
                ]) as run:
                    with self.assertRaises(MODULE.SecretWriterFailure) as raised:
                        write(REPOSITORY, path)
                self.assertIn(raised.exception.code, {"github_secret_write_failed", "github_secret_write_unconfirmed"})
                self.assertEqual(run.call_args_list[-1].args[0][-1], "/installation/token")
                self.assertNotIn("synthetic secret error", str(raised.exception))

    def test_unknown_revocation_withholds_success_even_after_successful_write(self):
        for failure in (subprocess.CompletedProcess([], 1, "", ""), subprocess.TimeoutExpired(["gh"], 30)):
            with self.subTest(failure=type(failure).__name__), owned_directory() as root:
                with mock.patch.object(MODULE.subprocess, "run", side_effect=[
                    subprocess.CompletedProcess([], 0, BEFORE, ""),
                    subprocess.CompletedProcess([], 0, "", ""),
                    subprocess.CompletedProcess([], 0, VERSION, ""), failure,
                ]):
                    with self.assertRaises(MODULE.SecretWriterFailure) as raised:
                        write(REPOSITORY, candidate(root))
                self.assertEqual(raised.exception.code, "github_secret_writer_revoke_failed")

    def test_invalid_version_withholds_commit_but_revokes(self):
        for version in ("", "not-a-version", "2020-01-01T00:00:00Z"):
            with self.subTest(version=version), owned_directory() as root:
                with mock.patch.object(MODULE.subprocess, "run", side_effect=[
                    subprocess.CompletedProcess([], 0, BEFORE, ""),
                    subprocess.CompletedProcess([], 0, "", ""),
                    subprocess.CompletedProcess([], 0, version, ""),
                    subprocess.CompletedProcess([], 0, "", ""),
                ]) as run:
                    with self.assertRaises(MODULE.SecretWriterFailure) as raised:
                        write(REPOSITORY, candidate(root))
                self.assertEqual(raised.exception.code, "github_secret_metadata_failed")
                self.assertEqual(run.call_args_list[-1].args[0][-1], "/installation/token")

    def test_unsafe_oauth_never_writes_and_already_issued_token_is_revoked(self):
        for fault in ("public", "public-parent", "hardlink", "symlink", "api-key", "missing-refresh"):
            with self.subTest(fault=fault), owned_directory() as root:
                path = candidate(root)
                if fault == "public":
                    path.chmod(0o644)
                elif fault == "public-parent":
                    path.parent.chmod(0o755)
                elif fault == "hardlink":
                    os.link(path, path.with_name("second-link"))
                elif fault == "symlink":
                    link = path.with_name("link.json")
                    link.symlink_to(path)
                    path = link
                else:
                    value = json.loads(path.read_text())
                    if fault == "api-key":
                        value["OPENAI_API_KEY"] = "synthetic-forbidden-key"
                    else:
                        del value["tokens"]["refresh_token"]
                    path.write_text(json.dumps(value))
                with mock.patch.object(MODULE.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "", "")) as run:
                    with self.assertRaises(MODULE.SecretWriterFailure) as raised:
                        write(REPOSITORY, path)
                self.assertEqual(raised.exception.code, "codex_auth_file_invalid")
                self.assertEqual(run.call_count, 1)
                self.assertEqual(run.call_args.args[0], REVOKE)

    def test_api_key_credential_is_rejected_before_any_github_read_or_write(self):
        with owned_directory() as root:
            path = candidate(root)
            value = json.loads(path.read_text())
            value["OPENAI_API_KEY"] = "synthetic-forbidden-key"
            path.write_text(json.dumps(value))
            commands = []

            def run(command, **options):
                commands.append(command)
                return github(command, **options)

            with mock.patch.object(MODULE.subprocess, "run", side_effect=run):
                with self.assertRaises(MODULE.SecretWriterFailure) as raised:
                    write(REPOSITORY, path)
            self.assertEqual(raised.exception.code, "codex_auth_file_invalid")
            self.assertEqual(commands, [REVOKE])
            self.assertNotIn("synthetic-forbidden-key", str(raised.exception))

    def test_newer_or_unconfirmed_provider_version_prevents_put_and_revokes(self):
        for code, output in ((0, BEFORE.replace(VERSION, "2026-10-30T20:00:01Z")),
                             (1, "HTTP/2.0 403 Forbidden\n\nnull\n"),
                             (1, "HTTP/2.0 404 Not Found\n\nnull\n"), (1, "")):
            with self.subTest(code=code, output=output), owned_directory() as root:
                with mock.patch.object(MODULE.subprocess, "run", side_effect=[
                    subprocess.CompletedProcess([], code, output, ""),
                    subprocess.CompletedProcess([], 0, "", ""),
                ]) as run:
                    with self.assertRaises(MODULE.SecretWriterFailure) as raised:
                        write(REPOSITORY, candidate(root))
                self.assertEqual(raised.exception.code, "github_secret_snapshot_stale")
                self.assertEqual(run.call_count, 2)
                self.assertEqual(run.call_args.args[0][-1], "/installation/token")

    def test_firestore_and_github_timestamp_encodings_match_the_same_version(self):
        with owned_directory() as root:
            with mock.patch.object(MODULE.subprocess, "run", side_effect=[
                subprocess.CompletedProcess([], 0, BEFORE, ""),
                subprocess.CompletedProcess([], 0, "", ""),
                subprocess.CompletedProcess([], 0, VERSION, ""),
                subprocess.CompletedProcess([], 0, "", ""),
            ]):
                self.assertEqual(write(REPOSITORY, candidate(root),
                                       expected=VERSION.replace("Z", ".000Z")), VERSION)

    def test_initial_missing_secret_requires_confirmed_404(self):
        for status in (403, 404):
            with self.subTest(status=status), owned_directory() as root:
                responses = [subprocess.CompletedProcess([], 1, f"HTTP/2.0 {status} Response\n\nnull\n", "")]
                if status == 404:
                    responses.extend([subprocess.CompletedProcess([], 0, "", ""),
                                      subprocess.CompletedProcess([], 0, VERSION, "")])
                responses.append(subprocess.CompletedProcess([], 0, "", ""))
                with mock.patch.object(MODULE.subprocess, "run", side_effect=responses):
                    if status == 404:
                        self.assertEqual(write(REPOSITORY, candidate(root), expected=None, absent=True), VERSION)
                    else:
                        with self.assertRaises(MODULE.SecretWriterFailure):
                            write(REPOSITORY, candidate(root), expected=None, absent=True)

    def test_second_write_with_the_same_writer_is_refused(self):
        with owned_directory() as root:
            path = candidate(root)
            commands = []

            def run(command, **options):
                commands.append(command)
                return github(command, **options)

            with mock.patch.object(MODULE.subprocess, "run", side_effect=run):
                self.assertEqual(write(REPOSITORY, path), VERSION)
                self.assertEqual(len(commands), 4)
                for _ in range(2):
                    with self.assertRaises(MODULE.SecretWriterFailure) as raised:
                        write(REPOSITORY, path)
                    self.assertEqual(raised.exception.code, "github_secret_writer_reused")
                    self.assertNotIn(TOKEN, str(raised.exception))
                # The reused writer reaches GitHub for nothing: no read, write or revocation.
                self.assertEqual(len(commands), 4)
                # A freshly issued writer is a different authority and still works.
                self.assertEqual(write(REPOSITORY, path, token="synthetic-second-writer"), VERSION)
            self.assertEqual(len(commands), 8)
            self.assertEqual(sum(command[1:3] == ["secret", "set"] for command in commands), 2)
            ledger = [entry for entry in path.parent.iterdir() if entry.name != "auth.json"]
            for entry in ledger:
                self.assertEqual(entry.stat().st_mode & 0o777, 0o600)
                self.assertNotIn(TOKEN, entry.name)
                self.assertEqual(entry.read_bytes(), b"")

    def test_second_cli_invocation_with_the_same_writer_is_refused(self):
        with owned_directory() as root:
            path = candidate(root)
            request = json.dumps({"repository": REPOSITORY, "authFile": str(path), "token": TOKEN,
                                  "expectedSecretUpdatedAt": VERSION, "expectedAbsent": False})
            outputs = []
            for _ in range(2):
                captured = io.StringIO()
                stdin = types.SimpleNamespace(buffer=io.BytesIO(request.encode()))
                with mock.patch.object(MODULE.sys, "argv", [str(SCRIPT)]), \
                        mock.patch.object(MODULE.sys, "stdin", stdin), \
                        mock.patch.object(MODULE.subprocess, "run", side_effect=github) as run, \
                        contextlib.redirect_stdout(captured):
                    code = MODULE.main()
                outputs.append((code, json.loads(captured.getvalue()), run.call_count))
            self.assertEqual(outputs[0], (0, {"secretUpdatedAt": VERSION, "writerTokenRevoked": True}, 4))
            self.assertEqual(outputs[1], (1, {"error": "github_secret_writer_reused"}, 0))

    def test_cli_rejects_bad_input_without_echoing_it(self):
        result = subprocess.run([sys.executable, str(SCRIPT)], input="synthetic-private-input",
                                text=True, capture_output=True, check=False,
                                env={"PATH": os.environ.get("PATH", ""), "PYTHONDONTWRITEBYTECODE": "1"})
        self.assertEqual(result.returncode, 1)
        self.assertEqual(json.loads(result.stdout), {"error": "github_secret_writer_invocation_invalid"})
        self.assertEqual(result.stderr, "")


if __name__ == "__main__":
    unittest.main()
