"""Trusted post-cleanup publication of one exact agent change bundle."""

import base64
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
KIT = Path(__file__).resolve().parents[2]
SCRIPTS = KIT / "scripts" / "agent"
for _path in (SCRIPTS / "worker", SCRIPTS):
    if str(_path) not in sys.path:
        sys.path.insert(0, str(_path))

import agent_task_push as PUSH  # noqa: E402

DISPATCH = "dispatch:item"
SCOPE = hashlib.sha256(DISPATCH.encode()).hexdigest()[:32]
BRANCH = "ii-os-agent/" + SCOPE
GIT_ENVIRONMENT = {
    "PATH": os.environ.get("PATH", ""),
    "HOME": os.devnull,
    "GIT_CONFIG_GLOBAL": os.devnull,
    "GIT_CONFIG_NOSYSTEM": "1",
    "GIT_TERMINAL_PROMPT": "0",
}


def git(directory, *arguments):
    return subprocess.run(
        [
            "git",
            "-c", "user.name=Alice Example",
            "-c", "user.email=alice@example.com",
            "-c", "commit.gpgsign=false",
            "-c", "tag.gpgsign=false",
            "-c", "init.defaultBranch=dev",
            *arguments,
        ],
        cwd=directory,
        env=GIT_ENVIRONMENT,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    ).stdout.strip()


class _Repository:
    """A disposable remote, one agent clone, and a private artifact root."""

    _template = None

    @classmethod
    def create(cls, root: Path):
        """Copy one class-wide template instead of rebuilding history."""
        if cls._template is None:
            cls._template_directory = tempfile.TemporaryDirectory()
            cls._template = cls(Path(cls._template_directory.name).resolve())
        for name in ("source", "remote.git", "work", "artifacts"):
            shutil.copytree(
                cls._template.root / name, root / name, symlinks=True
            )
        repository = cls.__new__(cls)
        repository.root = root
        repository.remote = root / "remote.git"
        repository.work = root / "work"
        repository.artifacts = root / "artifacts"
        # The copied clone must keep fetching from this test's own remote.
        git(repository.work, "remote", "set-url", "origin", str(repository.remote))
        return repository

    @classmethod
    def discard_template(cls):
        if cls._template is not None:
            cls._template_directory.cleanup()
            cls._template = None

    def __init__(self, root: Path):
        self.root = root
        source = root / "source"
        source.mkdir()
        git(source, "init", "-q")
        git(source, "checkout", "-q", "-B", "dev")
        (source / "README.md").write_text("base\n")
        git(source, "add", "README.md")
        git(source, "commit", "-q", "-m", "base")
        self.remote = root / "remote.git"
        git(root, "clone", "-q", "--bare", str(source), str(self.remote))
        self.work = root / "work"
        git(root, "clone", "-q", str(self.remote), str(self.work))
        self.artifacts = root / "artifacts"
        self.artifacts.mkdir(mode=0o700)

    def agent_commit(self, *, allow_empty=False):
        git(self.work, "checkout", "-q", "-B", BRANCH, "origin/dev")
        base_sha = git(self.work, "rev-parse", "HEAD")
        if allow_empty:
            git(self.work, "commit", "-q", "--allow-empty", "-m", "empty")
        else:
            (self.work / "change.txt").write_text("reviewed\n")
            git(self.work, "add", "change.txt")
            git(self.work, "commit", "-q", "-m", "reviewed")
        return base_sha, git(self.work, "rev-parse", "HEAD")

    def bundle(self, *revisions):
        storage_path = f"ii-os-agent/{SCOPE}/runtime-a/{PUSH.BUNDLE_PATH}"
        path = self.artifacts / storage_path
        path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        if path.exists():
            path.unlink()
        git(self.work, "bundle", "create", "-q", str(path), *revisions)
        encoded = path.read_bytes()
        return {
            "path": PUSH.BUNDLE_PATH,
            "storage_path": storage_path,
            "size_bytes": len(encoded),
            "sha256": hashlib.sha256(encoded).hexdigest(),
            "content_type": "application/octet-stream",
        }

    def remote_head(self, branch=BRANCH):
        completed = subprocess.run(
            ["git", "--git-dir", str(self.remote), "rev-parse", "--verify",
             "--quiet", f"refs/heads/{branch}"],
            env=GIT_ENVIRONMENT,
            text=True,
            stdout=subprocess.PIPE,
            check=False,
        )
        return completed.stdout.strip()


def _result(base_sha, head_sha, expected_old=None):
    return {
        "dispatch_id": DISPATCH,
        "repository": "acme-co/example-tracker",
        "repository_id": 999,
        "pull_request": {
            "repository": "acme-co/example-app",
            "repository_id": 123,
            "head": BRANCH,
            "base": "dev",
            "head_sha": head_sha,
            "base_sha": base_sha,
            "expected_old_head_sha": expected_old,
        },
    }


class BundlePublicationTest(unittest.TestCase):
    @classmethod
    def tearDownClass(cls):
        _Repository.discard_template()

    def publish(self, repository, artifact, result, lookup=lambda: 123):
        return PUSH.publish_agent_bundle_artifact(
            artifact,
            repository.artifacts,
            result,
            push_token="example-push-token",
            remote_url=repository.remote.as_uri(),
            repository_id_lookup=lookup,
        )

    def test_publishes_exact_head_once_and_recovers_idempotently(self):
        with tempfile.TemporaryDirectory() as value:
            repository = _Repository.create(Path(value).resolve())
            base_sha, head_sha = repository.agent_commit()
            artifact = repository.bundle(f"refs/heads/{BRANCH}", f"^{base_sha}")
            result = _result(base_sha, head_sha)
            receipt = self.publish(repository, artifact, result)
            self.assertEqual(
                receipt,
                {
                    "schema_version": 1,
                    "disposition": "published",
                    "dispatch_id": DISPATCH,
                    "repository": "acme-co/example-app",
                    "repository_id": 123,
                    "head": BRANCH,
                    "head_sha": head_sha,
                    "base": "dev",
                    "base_sha": base_sha,
                    "bundle_sha256": artifact["sha256"],
                },
            )
            self.assertEqual(repository.remote_head(), head_sha)
            self.assertEqual(self.publish(repository, artifact, result), receipt)

    def test_refuses_an_expected_old_head(self):
        with tempfile.TemporaryDirectory() as value:
            repository = _Repository.create(Path(value).resolve())
            base_sha, head_sha = repository.agent_commit()
            artifact = repository.bundle(f"refs/heads/{BRANCH}", f"^{base_sha}")
            with self.assertRaisesRegex(RuntimeError, "previously absent"):
                self.publish(
                    repository, artifact, _result(base_sha, head_sha, base_sha)
                )
            self.assertEqual(repository.remote_head(), "")

    def test_refuses_an_unrelated_existing_branch(self):
        with tempfile.TemporaryDirectory() as value:
            repository = _Repository.create(Path(value).resolve())
            base_sha = git(repository.work, "rev-parse", "origin/dev")
            git(repository.work, "checkout", "-q", "--orphan", BRANCH)
            git(repository.work, "rm", "-q", "-rf", ".")
            (repository.work / "unrelated.txt").write_text("unrelated\n")
            git(repository.work, "add", "-A")
            git(repository.work, "commit", "-q", "-m", "unrelated")
            planted = git(repository.work, "rev-parse", "HEAD")
            (repository.work / "change.txt").write_text("reviewed\n")
            git(repository.work, "add", "change.txt")
            git(repository.work, "commit", "-q", "-m", "reviewed")
            head_sha = git(repository.work, "rev-parse", "HEAD")
            git(
                repository.work, "push", "-q", str(repository.remote),
                f"{planted}:refs/heads/{BRANCH}",
            )
            artifact = repository.bundle(f"refs/heads/{BRANCH}")
            with self.assertRaises(RuntimeError):
                self.publish(repository, artifact, _result(base_sha, head_sha))
            self.assertEqual(repository.remote_head(), planted)

    def test_refuses_when_the_base_moved_after_checkout(self):
        with tempfile.TemporaryDirectory() as value:
            repository = _Repository.create(Path(value).resolve())
            base_sha, head_sha = repository.agent_commit()
            artifact = repository.bundle(f"refs/heads/{BRANCH}", f"^{base_sha}")
            git(repository.work, "checkout", "-q", "-B", "moved", "origin/dev")
            (repository.work / "other.txt").write_text("moved\n")
            git(repository.work, "add", "other.txt")
            git(repository.work, "commit", "-q", "-m", "moved")
            git(repository.work, "push", "-q", "origin", "moved:dev")
            with self.assertRaisesRegex(RuntimeError, "refs changed"):
                self.publish(repository, artifact, _result(base_sha, head_sha))
            self.assertEqual(repository.remote_head(), "")

    def test_refuses_a_bundle_without_a_meaningful_diff(self):
        with tempfile.TemporaryDirectory() as value:
            repository = _Repository.create(Path(value).resolve())
            base_sha, head_sha = repository.agent_commit(allow_empty=True)
            artifact = repository.bundle(f"refs/heads/{BRANCH}", f"^{base_sha}")
            with self.assertRaisesRegex(RuntimeError, "meaningful diff"):
                self.publish(repository, artifact, _result(base_sha, head_sha))
            self.assertEqual(repository.remote_head(), "")

    def test_refuses_a_bundle_resolving_to_another_head(self):
        with tempfile.TemporaryDirectory() as value:
            repository = _Repository.create(Path(value).resolve())
            base_sha, head_sha = repository.agent_commit()
            artifact = repository.bundle(f"refs/heads/{BRANCH}", f"^{base_sha}")
            with self.assertRaisesRegex(RuntimeError, "reviewed head"):
                self.publish(
                    repository, artifact, _result(base_sha, "0" * 40)
                )
            tampered = dict(artifact, sha256="0" * 64)
            with self.assertRaisesRegex(RuntimeError, "digest is invalid"):
                self.publish(repository, tampered, _result(base_sha, head_sha))
            self.assertEqual(repository.remote_head(), "")

    def test_refuses_a_changed_numeric_repository_identity(self):
        with tempfile.TemporaryDirectory() as value:
            repository = _Repository.create(Path(value).resolve())
            base_sha, head_sha = repository.agent_commit()
            artifact = repository.bundle(f"refs/heads/{BRANCH}", f"^{base_sha}")
            with self.assertRaisesRegex(RuntimeError, "repository identity"):
                self.publish(
                    repository, artifact, _result(base_sha, head_sha),
                    lookup=lambda: 124,
                )
            self.assertEqual(repository.remote_head(), "")
            with self.assertRaises(RuntimeError):
                PUSH._require_repository_identity(lambda: True, 1)

    def test_bundle_and_intent_must_travel_together(self):
        with tempfile.TemporaryDirectory() as value:
            repository = _Repository.create(Path(value).resolve())
            base_sha, head_sha = repository.agent_commit()
            artifact = repository.bundle(f"refs/heads/{BRANCH}", f"^{base_sha}")
            no_intent = {**_result(base_sha, head_sha), "pull_request": None}
            self.assertIsNone(self.publish(repository, None, no_intent))
            with self.assertRaisesRegex(RuntimeError, "requires a PR intent"):
                self.publish(repository, artifact, no_intent)
            with self.assertRaisesRegex(RuntimeError, "exact change bundle"):
                self.publish(repository, None, _result(base_sha, head_sha))


class PublicationCommandTest(unittest.TestCase):
    @classmethod
    def tearDownClass(cls):
        _Repository.discard_template()

    def _environment(self, repository, artifact, result):
        output = repository.root / "github-output"
        output.write_text("")
        return {
            "AGENT_RESULT_B64": base64.b64encode(
                json.dumps(result).encode()
            ).decode(),
            "AGENT_BUNDLE_ARTIFACT_B64": base64.b64encode(
                json.dumps(artifact).encode()
            ).decode(),
            "GITHUB_PUSH_TOKEN": "example-push-token",
            "PUSH_APP_LOGIN": "example-app-bot[bot]",
            "II_OS_AGENT_ARTIFACT_ROOT": str(repository.artifacts),
            "GITHUB_OUTPUT": str(output),
        }

    def test_command_writes_the_publication_receipt(self):
        with tempfile.TemporaryDirectory() as value:
            repository = _Repository.create(Path(value).resolve())
            base_sha, head_sha = repository.agent_commit()
            artifact = repository.bundle(f"refs/heads/{BRANCH}", f"^{base_sha}")
            environment = self._environment(
                repository, artifact, _result(base_sha, head_sha)
            )
            PUSH.run(
                environment,
                remote_url=repository.remote.as_uri(),
                repository_id_lookup=lambda: 123,
            )
            lines = Path(environment["GITHUB_OUTPUT"]).read_text().splitlines()
            self.assertEqual(len(lines), 1)
            name, encoded = lines[0].split("=", 1)
            self.assertEqual(name, "publication_receipt_b64")
            receipt = json.loads(base64.b64decode(encoded))
            self.assertEqual(receipt["head_sha"], head_sha)
            self.assertEqual(receipt["bundle_sha256"], artifact["sha256"])

    def test_command_requires_settings_and_a_publisher_app_login(self):
        with tempfile.TemporaryDirectory() as value:
            repository = _Repository.create(Path(value).resolve())
            base_sha, head_sha = repository.agent_commit()
            artifact = repository.bundle(f"refs/heads/{BRANCH}", f"^{base_sha}")
            valid = self._environment(
                repository, artifact, _result(base_sha, head_sha)
            )
            cases = [
                ({"PUSH_APP_LOGIN": None}, "PUSH_APP_LOGIN"),
                ({"PUSH_APP_LOGIN": ""}, "PUSH_APP_LOGIN"),
                ({"PUSH_APP_LOGIN": "alice"}, "PUSH_APP_LOGIN"),
                ({"PUSH_APP_LOGIN": "Example-App[bot]"}, "PUSH_APP_LOGIN"),
                ({"II_OS_AGENT_ARTIFACT_ROOT": None}, "II_OS_AGENT_ARTIFACT_ROOT"),
                ({"II_OS_AGENT_ARTIFACT_ROOT": "relative/artifacts"},
                 "II_OS_AGENT_ARTIFACT_ROOT"),
                ({"GITHUB_PUSH_TOKEN": None}, "GITHUB_PUSH_TOKEN"),
                ({"GITHUB_OUTPUT": None}, "GITHUB_OUTPUT"),
                ({"AGENT_RESULT_B64": None}, "AGENT_RESULT_B64"),
                ({"AGENT_BUNDLE_ARTIFACT_B64": None}, "AGENT_BUNDLE_ARTIFACT_B64"),
            ]
            for overrides, name in cases:
                environment = dict(valid)
                for key, change in overrides.items():
                    if change is None:
                        environment.pop(key)
                    else:
                        environment[key] = change
                with self.subTest(overrides=overrides):
                    with self.assertRaisesRegex(SystemExit, name):
                        PUSH.run(
                            environment,
                            remote_url=repository.remote.as_uri(),
                            repository_id_lookup=lambda: 123,
                        )
                    self.assertEqual(repository.remote_head(), "")
            self.assertEqual(Path(valid["GITHUB_OUTPUT"]).read_text(), "")

    def test_script_fails_by_name_before_any_network_call(self):
        completed = subprocess.run(
            [sys.executable, str(SCRIPTS / "agent_task_push.py")],
            env={
                "PATH": os.environ.get("PATH", ""),
                "PYTHONDONTWRITEBYTECODE": "1",
            },
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
            check=False,
        )
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("is required", completed.stderr)


if __name__ == "__main__":
    unittest.main()
