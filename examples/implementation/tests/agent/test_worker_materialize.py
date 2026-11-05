"""The workspace materializer publishes only reviewed copies of guest files."""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE / "../../scripts/agent"), str(HERE / "../../scripts/agent/worker")]
sys.dont_write_bytecode = True  # never leave a cache inside scripts/agent/worker

import agent_workspace_materialize as materialize  # noqa: E402

SOURCE = HERE / "../../scripts/agent/worker/agent_workspace_materialize.py"
NAME = "example-app-bot[bot]"
EMAIL = "example-app-bot[bot]@users.noreply.github.com"


def git(directory, *arguments):
    return subprocess.run(
        ["git", "-c", "user.name=Example Maintainer", "-c", "user.email=alice@example.com",
         "-c", "commit.gpgsign=false", *arguments],
        cwd=directory, check=True, text=True, capture_output=True,
        env={"PATH": os.environ["PATH"], "HOME": str(directory),
             "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull},
    ).stdout


class WorkerMaterializeTest(unittest.TestCase):
    def setUp(self):
        self._temporary = tempfile.TemporaryDirectory(prefix="worker-materialize-")
        self.root = Path(self._temporary.name).resolve()
        self.addCleanup(self._temporary.cleanup)
        self.source = self.repository(self.root / "workspace/repository")
        self.start = git(self.source, "rev-parse", "HEAD").strip()
        self.bundle = self.root / "result/change.bundle"

    def repository(self, path, files=None):
        path.mkdir(parents=True)
        git(path, "init", "-q")
        git(path, "checkout", "-q", "-b", "dev")
        for name, text in (files or {"README.md": "base\n"}).items():
            (path / name).parent.mkdir(parents=True, exist_ok=True)
            (path / name).write_text(text)
        git(path, "add", "-A")
        git(path, "commit", "-q", "-m", "base")
        return path

    def commit(self, branch="ii-os-agent/" + "a" * 32, **overrides):
        arguments = dict(source=self.source, start_sha=self.start, branch=branch, bundle=self.bundle,
                         name=NAME, email=EMAIL, message="Auto-agent work for #17")
        arguments.update(overrides)
        return materialize.materialize_commit(**arguments)

    def fetched(self, branch):
        git(self.source, "fetch", "-q", str(self.bundle), f"refs/heads/{branch}:refs/remotes/test/result")
        return "refs/remotes/test/result"

    def test_commit_writes_a_verified_bundle_without_guest_hooks_or_global_config(self):
        (self.source / "README.md").write_text("changed\n")
        (self.source / "docs").mkdir()
        (self.source / "docs/new.md").write_text("new\n")
        escaped = self.root / "hook-ran"
        hook = self.source / ".git/hooks/pre-commit"
        hook.write_text(f"#!/bin/sh\nprintf escaped > {escaped}\n")
        hook.chmod(0o755)
        hostile_home = self.root / "hostile-home"
        hostile_home.mkdir()
        (hostile_home / ".gitconfig").write_text("[commit]\n\tgpgsign = true\n")
        branch = "ii-os-agent/" + "d" * 32
        with mock.patch.dict(os.environ, {"HOME": str(hostile_home)}):
            result = self.commit(branch=branch)
        self.assertRegex(result["head_sha"], r"^[0-9a-f]{40}$")
        self.assertEqual(result["changed_files"], ["README.md", "docs/new.md"])
        self.assertFalse(escaped.exists())
        self.assertEqual(self.bundle.stat().st_mode & 0o777, 0o600)
        reference = self.fetched(branch)
        self.assertEqual(git(self.source, "rev-parse", reference).strip(), result["head_sha"])
        self.assertEqual(git(self.source, "rev-parse", reference + "^").strip(), self.start)
        self.assertEqual(git(self.source, "show", "-s", "--format=%an <%ae>|%s", reference).strip(),
                         f"{NAME} <{EMAIL}>|Auto-agent work for #17")

    def test_the_result_note_is_never_committed(self):
        (self.source / "README.md").write_text("changed\n")
        (self.source / ".auto-agent-result.md").write_text("Ready for QA: Yes\n")
        self.assertEqual(self.commit()["changed_files"], ["README.md"])

    def test_no_change_returns_the_start_commit_without_a_bundle(self):
        result = self.commit()
        self.assertEqual(result["head_sha"], self.start)
        self.assertEqual(result["changed_files"], [])
        self.assertFalse(self.bundle.exists())

    def test_a_symlink_escaping_the_workspace_is_refused(self):
        (self.source / "README.md").write_text("changed\n")
        (self.source / "escape").symlink_to("/etc/passwd")
        with self.assertRaisesRegex(RuntimeError, "link or special file"):
            self.commit()
        self.assertFalse(self.bundle.exists())

    def test_a_directory_symlink_escaping_the_workspace_is_refused(self):
        outside = self.root / "outside"
        outside.mkdir()
        (outside / "secret.txt").write_text("outside\n")
        (self.source / "vendor").symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(RuntimeError, "link or special file"):
            self.commit()
        self.assertFalse(self.bundle.exists())

    def test_a_hard_link_to_a_file_outside_the_workspace_is_refused(self):
        outside = self.root / "outside.txt"
        outside.write_text("outside\n")
        os.link(outside, self.source / "copied.txt")
        with self.assertRaisesRegex(RuntimeError, "link or special file"):
            self.commit()

    def test_moved_guest_history_is_refused(self):
        (self.source / "README.md").write_text("guest commit\n")
        git(self.source, "commit", "-q", "-am", "guest")
        with self.assertRaisesRegex(RuntimeError, "guest Git metadata changed"):
            self.commit()

    def test_tracked_symlinks_are_restored_from_the_base(self):
        (self.source / "CLAUDE.md").write_text("trusted rules\n")
        (self.source / "AGENTS.md").symlink_to("CLAUDE.md")
        git(self.source, "add", "CLAUDE.md", "AGENTS.md")
        git(self.source, "commit", "-q", "-m", "add agent rules")
        self.start = git(self.source, "rev-parse", "HEAD").strip()
        (self.source / "README.md").write_text("changed\n")
        (self.source / "AGENTS.md").unlink()
        (self.source / "AGENTS.md").symlink_to("/etc/passwd")
        branch = "ii-os-agent/" + "b" * 32
        self.assertEqual(self.commit(branch=branch)["changed_files"], ["README.md"])
        reference = self.fetched(branch)
        self.assertTrue(git(self.source, "ls-tree", reference, "AGENTS.md").startswith("120000 blob "))
        self.assertEqual(git(self.source, "show", f"{reference}:AGENTS.md"), "CLAUDE.md")

    def test_ignored_generated_files_are_excluded(self):
        (self.source / ".gitignore").write_text(".dart_tool/\nbuild/\n")
        git(self.source, "add", ".gitignore")
        git(self.source, "commit", "-q", "-m", "ignore build output")
        self.start = git(self.source, "rev-parse", "HEAD").strip()
        (self.source / "README.md").write_text("changed\n")
        (self.source / ".dart_tool").mkdir()
        (self.source / ".dart_tool/plugin-link").symlink_to("/etc/passwd")
        (self.source / "build").mkdir()
        (self.source / "build/artifact").write_text("generated\n")
        os.link(self.source / "build/artifact", self.source / "build/artifact-hard-link")
        (self.source / "lib").mkdir()
        (self.source / "lib/new.dart").write_text("void main() {}\n")
        self.assertEqual(self.commit()["changed_files"], ["README.md", "lib/new.dart"])

    def test_initialized_submodules_are_preserved_and_excluded(self):
        child = self.repository(self.root / "child")
        git(self.source, "-c", "protocol.file.allow=always", "submodule", "add", "-q", str(child), "vendor/child")
        git(self.source, "commit", "-q", "-am", "add child")
        self.start = git(self.source, "rev-parse", "HEAD").strip()
        (self.source / "README.md").write_text("parent change\n")
        (self.source / "vendor/child/README.md").write_text("unpublished child change\n")
        self.assertEqual(self.commit()["changed_files"], ["README.md"])

    def test_invalid_inputs_are_refused_before_any_copy(self):
        (self.source / "README.md").write_text("changed\n")
        for overrides in ({"branch": "main"}, {"branch": "ii-os-agent/" + "A" * 32}, {"start_sha": "HEAD"},
                          {"bundle": Path("relative.bundle")}, {"name": "two\nlines"}, {"message": ""}):
            with self.subTest(overrides=overrides), self.assertRaisesRegex(RuntimeError, "inputs are invalid"):
                self.commit(**overrides)
        self.bundle.parent.mkdir(parents=True)
        self.bundle.write_text("existing")
        with self.assertRaisesRegex(RuntimeError, "already exists"):
            self.commit()
        self.assertEqual(self.bundle.read_text(), "existing")


class WorkerMaterializeCommandTest(unittest.TestCase):
    """The result policy feeds the reviewed source to /usr/bin/python3 on stdin."""

    def setUp(self):
        self._temporary = tempfile.TemporaryDirectory(prefix="worker-materialize-cli-")
        self.root = Path(self._temporary.name).resolve()
        self.addCleanup(self._temporary.cleanup)
        self.source = self.root / "repository"
        self.source.mkdir()
        git(self.source, "init", "-q")
        (self.source / "README.md").write_text("base\n")
        git(self.source, "add", "README.md")
        git(self.source, "commit", "-q", "-m", "base")

    def run_helper(self, *arguments):
        return subprocess.run([sys.executable, "-", *arguments], input=SOURCE.read_bytes(), capture_output=True,
                              cwd=self.root, env={"PATH": os.environ["PATH"], "HOME": str(self.root)})

    def test_note_is_read_bounded_and_absent_notes_are_empty(self):
        self.assertEqual(self.run_helper("note", str(self.source)).stdout, b"")
        (self.source / ".auto-agent-result.md").write_text("Ready for QA: No\n")
        self.assertEqual(self.run_helper("note", str(self.source)).stdout, b"Ready for QA: No\n")
        (self.source / ".auto-agent-result.md").write_text("x" * 12001)
        self.assertNotEqual(self.run_helper("note", str(self.source)).returncode, 0)

    def test_a_linked_note_is_refused(self):
        outside = self.root / "outside.md"
        outside.write_text("Ready for QA: Yes\n")
        (self.source / ".auto-agent-result.md").symlink_to(outside)
        completed = self.run_helper("note", str(self.source))
        self.assertNotEqual(completed.returncode, 0)
        self.assertEqual(completed.stdout, b"")

    def test_commit_prints_one_json_receipt(self):
        start = git(self.source, "rev-parse", "HEAD").strip()
        (self.source / "README.md").write_text("changed\n")
        bundle = self.root / "change.bundle"
        completed = self.run_helper("commit", str(self.source), start, "ii-os-agent/" + "c" * 32, str(bundle),
                                    NAME, EMAIL, "Auto-agent work for #17")
        self.assertEqual(completed.returncode, 0, completed.stderr.decode())
        receipt = json.loads(completed.stdout)
        self.assertEqual(sorted(receipt), ["changed_files", "copied_bytes", "copied_files", "head_sha"])
        self.assertEqual(receipt["changed_files"], ["README.md"])
        self.assertTrue(bundle.is_file())

    def test_unknown_commands_are_refused(self):
        self.assertNotEqual(self.run_helper("push", str(self.source)).returncode, 0)


if __name__ == "__main__":
    unittest.main()
