"""Job-scoped, inode-bound credential handoff staging and cleanup."""

import base64
import hashlib
import json
import os
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
KIT = Path(__file__).resolve().parents[2]
SCRIPTS = KIT / "scripts" / "agent"
for _path in (SCRIPTS / "worker", SCRIPTS):
    if str(_path) not in sys.path:
        sys.path.insert(0, str(_path))

import agent_credential_handoff as HANDOFF  # noqa: E402

SCRIPT = SCRIPTS / "agent_credential_handoff.py"
CODEX_AUTH = json.dumps(
    {
        "OPENAI_API_KEY": None,
        "tokens": {
            "id_token": "example.id.token",
            "access_token": "example-access-token",
            "refresh_token": "example-refresh-token",
            "account_id": "example-account",
        },
        "last_refresh": "2026-01-01T00:00:00Z",
    },
    separators=(",", ":"),
)
USAGE_KEY = (
    "iiosu_v1.12345678-1234-1234-1234-123456789abc."
    + "a" * 43
)
PROMPT = json.dumps(
    {
        "schema_version": 1,
        "repository": "acme-co/example-app",
        "repository_id": 999,
        "issue_number": 7,
        "title": "Fix the example",
        "body": "Approved body from alice@example.com",
    },
    separators=(",", ":"),
).encode()
SOURCE_FILES = {
    "agent-work-ticket-core.sh": "#!/bin/bash\n# core\n",
    "agent-work-ticket-status.sh": "#!/bin/bash\n# status\n",
    "agent-work-ticket-prepare.sh": "#!/bin/bash\n# prepare\n",
    "agent-work-ticket-execute.sh": "#!/bin/bash\n# execute\n",
    "agent_workspace_materialize.py": "#!/usr/bin/env python3\n",
    "report-codex-exec-usage.mjs": "export {};\n",
}
STAGED_NAMES = {
    "github-api.token",
    "codex-auth.json",
    "agent-usage.key",
    "ticket-prompt.json",
    "agent-work-ticket-core.sh",
    "agent-work-ticket-status.sh",
    "agent-work-ticket-prepare.sh",
    "agent-work-ticket-execute.sh",
    "agent-workspace-materialize.py",
    "report-codex-exec-usage.mjs",
}
OWNER_MARKER = ".ii-os-disposable-owner.json"


class _Job:
    """One disposable runner temp, checkout, and GitHub file-command set."""

    def __init__(self, base: Path, run_id: str = "101", attempt: str = "1"):
        self.base = base
        self.runner_temp = base / "runner-temp"
        self.runner_temp.mkdir(mode=0o700)
        self.checkout = base / "checkout"
        worker = self.checkout / "scripts" / "agent" / "worker"
        worker.mkdir(parents=True)
        for name, value in SOURCE_FILES.items():
            (worker / name).write_text(value)
        self.github_env = base / "github-env"
        self.github_output = base / "github-output"
        self.github_env.write_text("")
        self.github_output.write_text("")
        self.run_id = run_id
        self.attempt = attempt
        self.child = f"{run_id}-{attempt}"
        self.stage_root = self.runner_temp / "ii-os-agent-handoff" / "stage"
        self.ledger_root = self.runner_temp / "ii-os-agent-handoff" / "ledger"
        self.environment = {
            "PATH": os.environ.get("PATH", ""),
            "PYTHONDONTWRITEBYTECODE": "1",
            "RUNNER_TEMP": str(self.runner_temp),
            "GITHUB_ENV": str(self.github_env),
            "GITHUB_OUTPUT": str(self.github_output),
            "GITHUB_RUN_ID": run_id,
            "GITHUB_RUN_ATTEMPT": attempt,
            "GITHUB_REPOSITORY_ID": "999",
            "II_OS_AGENT_JOB_ID": f"github:999:{run_id}:{attempt}:work-ticket",
            "API_TOKEN": "example-read-token",
            "CODEX_AUTH_JSON": CODEX_AUTH,
            "CODEX_SECRET_DIGEST": hashlib.sha256(
                CODEX_AUTH.encode()
            ).hexdigest(),
            "II_OS_AGENT_USAGE_API_KEY": USAGE_KEY,
            "IIAUTO_TICKET_PROMPT_B64": base64.b64encode(PROMPT).decode(),
            "IIAUTO_TICKET_PROMPT_SHA256": hashlib.sha256(PROMPT).hexdigest(),
        }

    def run(self, operation, **overrides):
        environment = dict(self.environment)
        for key, value in overrides.items():
            if value is None:
                environment.pop(key, None)
            else:
                environment[key] = value
        return subprocess.run(
            [sys.executable, str(SCRIPT), operation],
            cwd=self.checkout,
            env=environment,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=60,
            check=False,
        )

    def exported(self):
        values = {}
        for line in self.github_env.read_text().splitlines():
            name, value = line.split("=", 1)
            values[name] = value
        return values

    def staged(self):
        return self.stage_root / self.child

    def no_residue(self):
        staged = (
            list(self.stage_root.iterdir()) if self.stage_root.exists() else []
        )
        ledger = (
            list(self.ledger_root.iterdir())
            if self.ledger_root.exists()
            else []
        )
        return staged == [] and ledger == []


class HandoffSubscriptionOAuthTest(unittest.TestCase):
    def test_refuses_api_key_and_incomplete_oauth_credentials(self):
        refused = {
            "api key alongside tokens": json.dumps({
                "OPENAI_API_KEY": "example-api-key-value",
                "tokens": {
                    "access_token": "example-access-token",
                    "refresh_token": "example-refresh-token",
                },
            }),
            "api key only": json.dumps({"OPENAI_API_KEY": "example-api-key-value"}),
            "missing refresh token": json.dumps({
                "OPENAI_API_KEY": None,
                "tokens": {"access_token": "example-access-token"},
            }),
            "empty refresh token": json.dumps({
                "tokens": {
                    "access_token": "example-access-token",
                    "refresh_token": "",
                },
            }),
            "missing access token": json.dumps({
                "tokens": {"refresh_token": "example-refresh-token"},
            }),
            "not an object": json.dumps(["example-access-token"]),
            "not json": "example-raw-api-key-value",
        }
        for label, credential in refused.items():
            with self.subTest(label), tempfile.TemporaryDirectory() as value:
                job = _Job(Path(value).resolve())
                completed = job.run(
                    "stage",
                    CODEX_AUTH_JSON=credential,
                    CODEX_SECRET_DIGEST=hashlib.sha256(
                        credential.encode()
                    ).hexdigest(),
                )
                self.assertNotEqual(completed.returncode, 0)
                self.assertIn(
                    "CODEX_AUTH_JSON must be a subscription OAuth credential; "
                    "API keys are not accepted",
                    completed.stderr,
                )
                self.assertNotIn(credential, completed.stderr)
                self.assertTrue(job.no_residue())
                self.assertEqual(job.github_env.read_text(), "")

    def test_accepts_null_or_empty_api_key_field_with_oauth_tokens(self):
        for api_key in (None, ""):
            with self.subTest(api_key=api_key):
                credential = json.dumps({
                    "OPENAI_API_KEY": api_key,
                    "tokens": {
                        "access_token": "example-access-token",
                        "refresh_token": "example-refresh-token",
                    },
                })
                HANDOFF.require_subscription_oauth(credential.encode())


class HandoffRunnerTempTest(unittest.TestCase):
    def test_refuses_missing_runner_temp_by_name(self):
        with tempfile.TemporaryDirectory() as value:
            job = _Job(Path(value).resolve())
            completed = job.run("stage", RUNNER_TEMP=None)
            self.assertNotEqual(completed.returncode, 0)
            self.assertIn("RUNNER_TEMP", completed.stderr)
            self.assertFalse((job.runner_temp / "ii-os-agent-handoff").exists())

    def test_exports_a_canonical_directory_through_a_symlinked_runner_temp(self):
        with tempfile.TemporaryDirectory() as value:
            job = _Job(Path(value).resolve())
            alias = job.base / "runner-temp-alias"
            alias.symlink_to(job.runner_temp, target_is_directory=True)
            completed = job.run("stage", RUNNER_TEMP=str(alias))
            self.assertEqual(completed.returncode, 0, completed.stderr)
            exported = job.exported()
            self.assertEqual(exported["II_OS_AGENT_HANDOFF_DIR"], str(job.staged()))
            self.assertEqual(
                os.path.realpath(exported["II_OS_AGENT_HANDOFF_DIR"]),
                exported["II_OS_AGENT_HANDOFF_DIR"],
            )
            job.environment.update(exported)
            completed = job.run("cleanup", RUNNER_TEMP=str(alias))
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertTrue(job.no_residue())

    def test_refuses_relative_runner_temp_by_name(self):
        with tempfile.TemporaryDirectory() as value:
            job = _Job(Path(value).resolve())
            for operation in ("stage", "cleanup", "recover"):
                with self.subTest(operation=operation):
                    completed = job.run(operation, RUNNER_TEMP="runner-temp")
                    self.assertNotEqual(completed.returncode, 0)
                    self.assertIn("RUNNER_TEMP", completed.stderr)
            self.assertFalse((job.checkout / "runner-temp").exists())


class HandoffStageAndCleanupTest(unittest.TestCase):
    def test_stage_writes_private_files_and_exact_digests(self):
        with tempfile.TemporaryDirectory() as value:
            job = _Job(Path(value).resolve())
            completed = job.run("stage")
            self.assertEqual(completed.returncode, 0, completed.stderr)
            staged = job.staged()
            exported = job.exported()
            self.assertEqual(
                set(exported),
                {
                    "II_OS_AGENT_HANDOFF_DIR",
                    "II_OS_AGENT_HANDOFF_DEVICE",
                    "II_OS_AGENT_HANDOFF_INODE",
                    "II_OS_AGENT_HANDOFF_DIGESTS",
                },
            )
            self.assertEqual(exported["II_OS_AGENT_HANDOFF_DIR"], str(staged))
            metadata = staged.stat()
            self.assertEqual(stat.S_IMODE(metadata.st_mode), 0o700)
            self.assertEqual(
                exported["II_OS_AGENT_HANDOFF_DEVICE"], str(metadata.st_dev)
            )
            self.assertEqual(
                exported["II_OS_AGENT_HANDOFF_INODE"], str(metadata.st_ino)
            )
            for directory in (
                job.runner_temp / "ii-os-agent-handoff",
                job.stage_root,
                job.ledger_root,
            ):
                self.assertEqual(
                    stat.S_IMODE(directory.stat().st_mode), 0o700, directory
                )
            names = {path.name for path in staged.iterdir()}
            self.assertEqual(names, STAGED_NAMES | {OWNER_MARKER})
            for path in staged.iterdir():
                self.assertEqual(
                    stat.S_IMODE(path.lstat().st_mode), 0o600, path.name
                )
                self.assertTrue(stat.S_ISREG(path.lstat().st_mode))
            encoded = exported["II_OS_AGENT_HANDOFF_DIGESTS"]
            digests = json.loads(encoded)
            self.assertEqual(
                encoded,
                json.dumps(digests, sort_keys=True, separators=(",", ":")),
            )
            self.assertEqual(set(digests), STAGED_NAMES)
            for name in STAGED_NAMES:
                self.assertEqual(
                    digests[name],
                    hashlib.sha256((staged / name).read_bytes()).hexdigest(),
                    name,
                )
            self.assertEqual(
                (staged / "codex-auth.json").read_text(), CODEX_AUTH
            )
            self.assertEqual((staged / "ticket-prompt.json").read_bytes(), PROMPT)
            self.assertEqual(
                (staged / "agent-workspace-materialize.py").read_text(),
                SOURCE_FILES["agent_workspace_materialize.py"],
            )
            owner = json.loads((staged / OWNER_MARKER).read_text())
            self.assertEqual(owner["owner"], "ii-os-agent-task")
            self.assertEqual(owner["job_id"], "github:999:101:1:work-ticket")
            self.assertEqual(owner["inode"], metadata.st_ino)
            ledger = json.loads((job.ledger_root / "101-1.json").read_text())
            self.assertEqual(ledger["phase"], "ready")
            for secret in ("example-read-token", USAGE_KEY, "example-access"):
                self.assertNotIn(secret, completed.stdout + completed.stderr)
                self.assertNotIn(secret, job.github_env.read_text())

    def test_cleanup_proves_removal_and_refuses_changed_identity(self):
        with tempfile.TemporaryDirectory() as value:
            job = _Job(Path(value).resolve())
            self.assertEqual(job.run("stage").returncode, 0)
            exported = job.exported()
            job.environment.update(exported)
            for name, changed in (
                (
                    "II_OS_AGENT_HANDOFF_INODE",
                    str(int(exported["II_OS_AGENT_HANDOFF_INODE"]) + 1),
                ),
                (
                    "II_OS_AGENT_HANDOFF_DEVICE",
                    str(int(exported["II_OS_AGENT_HANDOFF_DEVICE"]) + 1),
                ),
                ("II_OS_AGENT_HANDOFF_DIR", str(job.base / "elsewhere")),
                ("II_OS_AGENT_JOB_ID", "github:999:101:1:other-job"),
            ):
                with self.subTest(name=name):
                    completed = job.run("cleanup", **{name: changed})
                    self.assertNotEqual(completed.returncode, 0)
                    self.assertTrue(job.staged().is_dir())
                    self.assertEqual(
                        {path.name for path in job.staged().iterdir()},
                        STAGED_NAMES | {OWNER_MARKER},
                    )
                    self.assertNotIn("proven", job.github_output.read_text())
            completed = job.run("cleanup", II_OS_AGENT_HANDOFF_INODE=None)
            self.assertNotEqual(completed.returncode, 0)
            self.assertIn("II_OS_AGENT_HANDOFF_INODE", completed.stderr)
            self.assertTrue(job.staged().is_dir())

            completed = job.run("cleanup")
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertEqual(job.github_output.read_text(), "proven=true\n")
            self.assertFalse(job.staged().exists())
            self.assertTrue(job.no_residue())

    def test_cleanup_refuses_unexpected_file(self):
        with tempfile.TemporaryDirectory() as value:
            job = _Job(Path(value).resolve())
            self.assertEqual(job.run("stage").returncode, 0)
            job.environment.update(job.exported())
            (job.staged() / "planted.txt").write_text("unexpected")
            completed = job.run("cleanup")
            self.assertNotEqual(completed.returncode, 0)
            self.assertIn("unexpected file", completed.stderr)
            self.assertTrue((job.staged() / "planted.txt").exists())
            self.assertNotIn("proven", job.github_output.read_text())

    def test_recover_all_removes_an_owned_handoff(self):
        with tempfile.TemporaryDirectory() as value:
            job = _Job(Path(value).resolve())
            self.assertEqual(job.run("stage").returncode, 0)
            completed = job.run("recover")
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertTrue(job.staged().is_dir())
            completed = job.run("recover-all")
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertTrue(job.no_residue())

    def test_stage_refusals_leave_no_credential_residue(self):
        cases = {
            "usage key format": {"II_OS_AGENT_USAGE_API_KEY": "iiosu_v1.bad"},
            "codex digest changed": {"CODEX_SECRET_DIGEST": "0" * 64},
            "prompt digest changed": {
                "IIAUTO_TICKET_PROMPT_SHA256": "0" * 64,
            },
            "job identity of another run": {
                "II_OS_AGENT_JOB_ID": "github:999:102:1:work-ticket",
            },
            "job identity of another repository": {
                "II_OS_AGENT_JOB_ID": "github:998:101:1:work-ticket",
            },
            "missing read token": {"API_TOKEN": None},
        }
        for label, overrides in cases.items():
            with self.subTest(label), tempfile.TemporaryDirectory() as value:
                job = _Job(Path(value).resolve())
                completed = job.run("stage", **overrides)
                self.assertNotEqual(completed.returncode, 0)
                self.assertTrue(job.no_residue())
                self.assertEqual(job.github_env.read_text(), "")

    def test_stage_refuses_missing_reviewed_worker_source(self):
        with tempfile.TemporaryDirectory() as value:
            job = _Job(Path(value).resolve())
            (
                job.checkout / "scripts/agent/worker/report-codex-exec-usage.mjs"
            ).unlink()
            completed = job.run("stage")
            self.assertNotEqual(completed.returncode, 0)
            self.assertTrue(job.no_residue())

    def test_stage_refuses_a_second_stage_for_the_same_attempt(self):
        with tempfile.TemporaryDirectory() as value:
            job = _Job(Path(value).resolve())
            self.assertEqual(job.run("stage").returncode, 0)
            first = job.exported()
            completed = job.run("stage")
            self.assertNotEqual(completed.returncode, 0)
            self.assertTrue(job.staged().is_dir())
            self.assertEqual(
                str(job.staged().stat().st_ino),
                first["II_OS_AGENT_HANDOFF_INODE"],
            )


class HandoffCrashRecoveryTest(unittest.TestCase):
    """Ledger phases let an interrupted cleanup resume without guessing."""

    def _roots(self, base):
        root = base / "stage"
        ledger = base / "ledger"
        root.mkdir(mode=0o700)
        ledger.mkdir(mode=0o700)
        return root, ledger

    def test_resumes_partial_cleanup(self):
        with tempfile.TemporaryDirectory() as value:
            root, ledger = self._roots(Path(value).resolve())
            child = root / "202-1"
            child.mkdir(mode=0o700)
            (child / HANDOFF.OWNER_NAME).write_text("owned\n")
            metadata = child.stat()
            root_fd = os.open(root, os.O_RDONLY | os.O_DIRECTORY)
            ledger_fd = os.open(ledger, os.O_RDONLY | os.O_DIRECTORY)
            try:
                HANDOFF._write_ledger(
                    ledger_fd,
                    "202-1",
                    {
                        "schema_version": 1,
                        "owner": "ii-os-agent-task",
                        "child": "202-1",
                        "run_id": "202",
                        "run_attempt": "1",
                        "job_id": "github:999:202:1:work-ticket",
                        "phase": "cleaning",
                        "created_unix": int(time.time()),
                        "device": metadata.st_dev,
                        "inode": metadata.st_ino,
                    },
                    exclusive=True,
                )
                HANDOFF._resume_cleanup(
                    root_fd, ledger_fd, "202-1", require_complete=False
                )
                self.assertFalse(child.exists())
                self.assertFalse((ledger / "202-1.json").exists())
            finally:
                os.close(ledger_fd)
                os.close(root_fd)

    def test_removes_an_empty_directory_left_at_intent(self):
        with tempfile.TemporaryDirectory() as value:
            root, ledger = self._roots(Path(value).resolve())
            (root / "404-2").mkdir(mode=0o700)
            root_fd = os.open(root, os.O_RDONLY | os.O_DIRECTORY)
            ledger_fd = os.open(ledger, os.O_RDONLY | os.O_DIRECTORY)
            try:
                HANDOFF._write_ledger(
                    ledger_fd,
                    "404-2",
                    {
                        "schema_version": 1,
                        "owner": "ii-os-agent-task",
                        "child": "404-2",
                        "run_id": "404",
                        "run_attempt": "2",
                        "job_id": "github:999:404:2:work-ticket",
                        "phase": "intent",
                        "created_unix": int(time.time()),
                    },
                    exclusive=True,
                )
                HANDOFF._resume_cleanup(
                    root_fd, ledger_fd, "404-2", require_complete=False
                )
                self.assertEqual(list(root.iterdir()), [])
                self.assertEqual(list(ledger.iterdir()), [])
            finally:
                os.close(ledger_fd)
                os.close(root_fd)

    def test_rejects_replaced_directory(self):
        with tempfile.TemporaryDirectory() as value:
            root, ledger = self._roots(Path(value).resolve())
            child = root / "303-1"
            child.mkdir(mode=0o700)
            metadata = child.stat()
            root_fd = os.open(root, os.O_RDONLY | os.O_DIRECTORY)
            ledger_fd = os.open(ledger, os.O_RDONLY | os.O_DIRECTORY)
            try:
                HANDOFF._write_ledger(
                    ledger_fd,
                    "303-1",
                    {
                        "schema_version": 1,
                        "owner": "ii-os-agent-task",
                        "child": "303-1",
                        "run_id": "303",
                        "run_attempt": "1",
                        "job_id": "github:999:303:1:work-ticket",
                        "phase": "bound",
                        "created_unix": int(time.time()),
                        "device": metadata.st_dev,
                        "inode": metadata.st_ino,
                    },
                    exclusive=True,
                )
                child.rename(root / "moved")
                child.mkdir(mode=0o700)
                with self.assertRaisesRegex(RuntimeError, "inode changed"):
                    HANDOFF._resume_cleanup(
                        root_fd, ledger_fd, "303-1", require_complete=False
                    )
                self.assertTrue((root / "moved").is_dir())
                self.assertTrue((ledger / "303-1.json").exists())
            finally:
                os.close(ledger_fd)
                os.close(root_fd)


if __name__ == "__main__":
    unittest.main()
