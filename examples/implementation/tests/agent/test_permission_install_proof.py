"""Permission installer proof for the ii-os readiness contract."""

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

import agent_permission_install as INSTALLER  # noqa: E402
from agent_task_profile import canonical_profile_digest  # noqa: E402

INSTALLER_SCRIPT = SCRIPTS / "agent_permission_install.py"
GIT_ENVIRONMENT = {
    "PATH": os.environ.get("PATH", ""),
    "HOME": os.devnull,
    "GIT_CONFIG_GLOBAL": os.devnull,
    "GIT_CONFIG_NOSYSTEM": "1",
    "GIT_TERMINAL_PROMPT": "0",
}
# permissionInstallerProofCheck: the exact key set for a runtime profile.
RUNTIME_PROOF_KEYS = {
    "schema_version",
    "security_contract",
    "approval_id",
    "dispatch_id",
    "profile_id",
    "profile_version",
    "profile_digest",
    "installer_run_id",
    "installer_run_attempt",
    "installer_source_sha",
    "trusted_source_blob_shas",
    "trusted_source_modes",
    "workflow_namespace_blob_shas",
    "workflow_namespace_modes",
    "runtime_configuration_sha256",
    "execution_binding_sha256",
}
PROFILE_ID = "repository-maintainer"
REVIEWED = {
    ".github/workflows/ii-os-agent-task.yml": "name: agent task\n",
    ".github/workflows/ii-os-agent-permissions-impl.yml": (
        "name: permissions\njobs:\n  install:\n"
        "    environment: ii-os-agent-bootstrap\n"
    ),
    "scripts/agent/reviewed_helper.py": "VALUE = 1\n",
    "scripts/agent/worker/run-step.sh": "#!/bin/bash\nexit 0\n",
}
EXECUTABLE = {"scripts/agent/worker/run-step.sh"}


def git(directory, *arguments):
    return subprocess.run(
        [
            "git",
            "-c", "user.name=Alice Example",
            "-c", "user.email=alice@example.com",
            "-c", "commit.gpgsign=false",
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


class _Checkout:
    """A disposable operator repository prepared for one installer run."""

    _template = None

    @classmethod
    def create(cls, root: Path):
        """Copy one class-wide template instead of rebuilding history."""
        if cls._template is None:
            cls._template_directory = tempfile.TemporaryDirectory()
            cls._template = cls(Path(cls._template_directory.name).resolve())
        checkout = cls.__new__(cls)
        checkout.root = root / "example-app"
        shutil.copytree(cls._template.root, checkout.root, symlinks=True)
        checkout.manifest = json.loads(json.dumps(cls._template.manifest))
        checkout.head = cls._template.head
        checkout.profile = json.loads(json.dumps(cls._template.profile))
        return checkout

    @classmethod
    def discard_template(cls):
        if cls._template is not None:
            cls._template_directory.cleanup()
            cls._template = None

    def __init__(self, root: Path):
        self.root = root / "example-app"
        self.root.mkdir()
        git(self.root, "init", "-q")
        (self.root / ".ii-os-disposable-owner").write_text("test fixture\n")
        runtimes = self.root / ".ii-os" / "runtimes"
        runtimes.mkdir(parents=True)
        (runtimes / "codex.json").write_text('{"engine":"codex"}\n')
        (runtimes / "docker.json").write_text('{"provider":"docker"}\n')
        for path, content in REVIEWED.items():
            target = self.root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content)
            target.chmod(0o755 if path in EXECUTABLE else 0o644)
        (self.root / ".github/workflows/ci.yml").write_text("name: ci\n")
        self.manifest = self.write_manifest()
        git(self.root, "add", "-A")
        git(self.root, "commit", "-q", "-m", "reviewed inputs")
        self.head = git(self.root, "rev-parse", "HEAD")
        self.profile = {
            "schema_version": 4,
            "engine": "codex",
            "id": PROFILE_ID,
            "version": "2026-01-01.1",
            "display_name": "Repository maintainer",
            "description": "Maintains acme-co/example-app.",
            "allowed_actions": ["Edit code"],
            "denied_actions": [],
            "repository_actions": {"mode": "pull_request"},
            "runtime": {
                "configuration": {
                    "path": ".ii-os/runtimes/codex.json",
                    "sha256": self.sha256(".ii-os/runtimes/codex.json"),
                },
                "execution_binding": {
                    "path": ".ii-os/runtimes/docker.json",
                    "sha256": self.sha256(".ii-os/runtimes/docker.json"),
                },
            },
            "workflow": {"file": "ii-os-agent-task.yml", "ref": "dev"},
        }

    def sha256(self, path):
        return hashlib.sha256((self.root / path).read_bytes()).hexdigest()

    def write_manifest(self, **changes):
        manifest = {
            "schema_version": 1,
            "blob_shas": {
                path: git(self.root, "hash-object", "--", path)
                for path in REVIEWED
            },
            "executable_paths": sorted(EXECUTABLE),
            "python_import_namespaces": {
                "scripts/agent": ["reviewed_helper.py"],
                "scripts/agent/worker": [],
            },
        }
        manifest.update(changes)
        (self.root / ".ii-os/agent-trusted-source-manifest.json").write_text(
            json.dumps(manifest, indent=2, sort_keys=True) + "\n"
        )
        return manifest

    def commit(self, message="update"):
        git(self.root, "add", "-A")
        git(self.root, "commit", "-q", "-m", message)
        self.head = git(self.root, "rev-parse", "HEAD")

    def environment(self, profile=None, **overrides):
        profile = self.profile if profile is None else profile
        environment = {
            "PATH": os.environ.get("PATH", ""),
            "PYTHONDONTWRITEBYTECODE": "1",
            "HOME": os.devnull,
            "GIT_CONFIG_GLOBAL": os.devnull,
            "GIT_CONFIG_NOSYSTEM": "1",
            "PROFILE_ID": PROFILE_ID,
            "APPROVAL_ID": "approval-1",
            "DISPATCH_ID": "dispatch-0123456789abcdef",
            "PROFILE_VERSION": profile["version"],
            "PROFILE_DIGEST": canonical_profile_digest(profile),
            "PROFILE_JSON": json.dumps(profile),
            "GITHUB_RUN_ID": "100",
            "GITHUB_RUN_ATTEMPT": "2",
            "GITHUB_SHA": self.head,
        }
        for key, value in overrides.items():
            if value is None:
                environment.pop(key, None)
            else:
                environment[key] = value
        return environment

    def install(self, *arguments, cwd=None, **overrides):
        return subprocess.run(
            [sys.executable, str(INSTALLER_SCRIPT), *arguments],
            cwd=cwd or self.root,
            env=self.environment(**overrides),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=60,
            check=False,
        )

    @property
    def profile_path(self):
        return self.root / ".ii-os/agent-permissions" / f"{PROFILE_ID}.json"

    @property
    def proof_path(self):
        return self.root / ".ii-os/agent-permission-proofs" / f"{PROFILE_ID}.json"

    def nothing_installed(self):
        return not self.profile_path.exists() and not self.proof_path.exists()


class PermissionInstallProofTest(unittest.TestCase):
    @classmethod
    def tearDownClass(cls):
        _Checkout.discard_template()

    def test_runtime_proof_has_exactly_the_readiness_contract_keys(self):
        with tempfile.TemporaryDirectory() as value:
            checkout = _Checkout.create(Path(value).resolve())
            completed = checkout.install()
            self.assertEqual(completed.returncode, 0, completed.stderr)
            proof = json.loads(checkout.proof_path.read_text())
            self.assertEqual(set(proof), RUNTIME_PROOF_KEYS)
            self.assertEqual(len(proof), 16)
            self.assertEqual(proof["schema_version"], 2)
            self.assertEqual(proof["security_contract"], 7)
            self.assertEqual(proof["approval_id"], "approval-1")
            self.assertEqual(proof["dispatch_id"], "dispatch-0123456789abcdef")
            self.assertEqual(proof["profile_id"], PROFILE_ID)
            self.assertEqual(proof["profile_version"], "2026-01-01.1")
            self.assertEqual(
                proof["profile_digest"],
                canonical_profile_digest(checkout.profile),
            )
            self.assertIs(type(proof["installer_run_id"]), int)
            self.assertEqual(proof["installer_run_id"], 100)
            self.assertEqual(proof["installer_run_attempt"], 2)
            self.assertEqual(proof["installer_source_sha"], checkout.head)
            self.assertEqual(
                proof["runtime_configuration_sha256"],
                checkout.profile["runtime"]["configuration"]["sha256"],
            )
            self.assertEqual(
                proof["execution_binding_sha256"],
                checkout.profile["runtime"]["execution_binding"]["sha256"],
            )
            manifest = checkout.manifest
            self.assertEqual(
                proof["trusted_source_blob_shas"], manifest["blob_shas"]
            )
            self.assertEqual(
                proof["trusted_source_modes"],
                {
                    path: "100755" if path in EXECUTABLE else "100644"
                    for path in manifest["blob_shas"]
                },
            )
            workflows = {
                ".github/workflows/ci.yml",
                ".github/workflows/ii-os-agent-permissions-impl.yml",
                ".github/workflows/ii-os-agent-task.yml",
            }
            self.assertEqual(set(proof["workflow_namespace_blob_shas"]), workflows)
            self.assertEqual(
                proof["workflow_namespace_modes"],
                {path: "100644" for path in workflows},
            )
            for path in workflows:
                self.assertEqual(
                    proof["workflow_namespace_blob_shas"][path],
                    git(checkout.root, "rev-parse", f"HEAD:{path}"),
                )
            self.assertEqual(
                json.loads(checkout.profile_path.read_text()), checkout.profile
            )

    def test_changed_runtime_bytes_cannot_be_installed(self):
        with tempfile.TemporaryDirectory() as value:
            checkout = _Checkout.create(Path(value).resolve())
            (checkout.root / ".ii-os/runtimes/codex.json").write_text("{}\n")
            completed = checkout.install()
            self.assertNotEqual(completed.returncode, 0)
            self.assertIn("runtime input changed", completed.stderr)
            self.assertTrue(checkout.nothing_installed())

    def test_matching_hash_cannot_authorize_an_uncommitted_runtime_file(self):
        with tempfile.TemporaryDirectory() as value:
            checkout = _Checkout.create(Path(value).resolve())
            path = ".ii-os/runtimes/codex.json"
            (checkout.root / path).write_text('{"engine":"other"}\n')
            profile = json.loads(json.dumps(checkout.profile))
            profile["runtime"]["configuration"]["sha256"] = checkout.sha256(path)
            completed = checkout.install(
                PROFILE_JSON=json.dumps(profile),
                PROFILE_DIGEST=canonical_profile_digest(profile),
            )
            self.assertNotEqual(completed.returncode, 0)
            self.assertIn("committed regular source", completed.stderr)
            self.assertTrue(checkout.nothing_installed())

    def test_unreviewed_workflow_cannot_select_an_agent_environment(self):
        for environment in ("ii-os-agent-maintainer", "II-OS-AGENT-BOOTSTRAP"):
            with self.subTest(environment), tempfile.TemporaryDirectory() as value:
                checkout = _Checkout.create(Path(value).resolve())
                (checkout.root / ".github/workflows/unreviewed.yaml").write_text(
                    f"jobs:\n  steal:\n    environment: {environment}\n"
                )
                checkout.commit()
                completed = checkout.install()
                self.assertNotEqual(completed.returncode, 0)
                self.assertIn("unreviewed workflow", completed.stderr)
                self.assertTrue(checkout.nothing_installed())

    def test_trusted_sources_must_match_the_reviewed_manifest(self):
        with tempfile.TemporaryDirectory() as value:
            checkout = _Checkout.create(Path(value).resolve())
            (checkout.root / "scripts/agent/reviewed_helper.py").write_text(
                "VALUE = 2\n"
            )
            checkout.commit()
            completed = checkout.install()
            self.assertNotEqual(completed.returncode, 0)
            self.assertIn("scripts/agent/reviewed_helper.py", completed.stderr)
            self.assertTrue(checkout.nothing_installed())

    def test_trusted_source_modes_must_match_the_manifest(self):
        with tempfile.TemporaryDirectory() as value:
            checkout = _Checkout.create(Path(value).resolve())
            checkout.write_manifest(executable_paths=[])
            checkout.commit()
            completed = checkout.install()
            self.assertNotEqual(completed.returncode, 0)
            self.assertIn("scripts/agent/worker/run-step.sh", completed.stderr)
            self.assertTrue(checkout.nothing_installed())

    def test_uncommitted_trusted_source_edit_is_refused(self):
        with tempfile.TemporaryDirectory() as value:
            checkout = _Checkout.create(Path(value).resolve())
            (checkout.root / ".github/workflows/ii-os-agent-task.yml").write_text(
                "name: edited after checkout\n"
            )
            completed = checkout.install()
            self.assertNotEqual(completed.returncode, 0)
            self.assertTrue(checkout.nothing_installed())

    def test_manifest_follows_the_backend_schema(self):
        valid = {
            "schema_version": 1,
            "blob_shas": {
                "scripts/agent/reviewed_helper.py": "a" * 40,
                "scripts/agent/worker/run-step.sh": "b" * 40,
                ".github/workflows/ii-os-agent-task.yml": "c" * 40,
            },
            "executable_paths": ["scripts/agent/worker/run-step.sh"],
            "python_import_namespaces": {
                "scripts/agent": ["reviewed_helper.py"],
                "scripts/agent/worker": [],
            },
        }
        blob_shas, modes = INSTALLER.validate_trusted_source_manifest(valid)
        self.assertEqual(blob_shas, valid["blob_shas"])
        self.assertEqual(
            modes,
            {
                "scripts/agent/reviewed_helper.py": "100644",
                "scripts/agent/worker/run-step.sh": "100755",
                ".github/workflows/ii-os-agent-task.yml": "100644",
            },
        )
        cases = {
            "unknown key": {"extra": True},
            "missing key": {"executable_paths": None},
            "wrong schema": {"schema_version": 2},
            "boolean schema": {"schema_version": True},
            "empty blobs": {"blob_shas": {}},
            "unsafe path": {"blob_shas": {"../escape.sh": "a" * 40}},
            "dot segment": {"blob_shas": {"./run.sh": "a" * 40}},
            "absolute path": {"blob_shas": {"/etc/run.sh": "a" * 40}},
            "short sha": {"blob_shas": {"run.sh": "a"}},
            "executable outside blobs": {"executable_paths": ["other.sh"]},
            "duplicate executable": {"executable_paths": [
                "scripts/agent/worker/run-step.sh",
                "scripts/agent/worker/run-step.sh",
            ]},
            "python not namespaced": {"python_import_namespaces": {}},
            "namespace names unreviewed file": {"python_import_namespaces": {
                "scripts/agent": ["reviewed_helper.py", "other.py"],
            }},
            "unsafe namespace": {"python_import_namespaces": {
                "scripts/../agent": ["reviewed_helper.py"],
            }},
        }
        for label, change in cases.items():
            manifest = {**valid, **change}
            if change.get("executable_paths", "") is None:
                del manifest["executable_paths"]
            with self.subTest(label):
                with self.assertRaisesRegex(SystemExit, "manifest"):
                    INSTALLER.validate_trusted_source_manifest(manifest)

    def test_installer_refuses_an_invalid_committed_manifest(self):
        with tempfile.TemporaryDirectory() as value:
            checkout = _Checkout.create(Path(value).resolve())
            checkout.write_manifest(python_import_namespaces={})
            checkout.commit()
            completed = checkout.install()
            self.assertNotEqual(completed.returncode, 0)
            self.assertIn("manifest", completed.stderr)
            self.assertTrue(checkout.nothing_installed())

    def test_manifest_must_be_present_and_committed(self):
        with tempfile.TemporaryDirectory() as value:
            checkout = _Checkout.create(Path(value).resolve())
            manifest = checkout.root / ".ii-os/agent-trusted-source-manifest.json"
            manifest.write_text(manifest.read_text() + "\n")
            completed = checkout.install()
            self.assertNotEqual(completed.returncode, 0)
            self.assertIn("agent-trusted-source-manifest.json", completed.stderr)
            git(checkout.root, "rm", "-q", "--cached", str(manifest))
            manifest.unlink()
            checkout.commit()
            completed = checkout.install()
            self.assertNotEqual(completed.returncode, 0)
            self.assertIn("agent-trusted-source-manifest.json", completed.stderr)
            self.assertTrue(checkout.nothing_installed())

    def test_identity_and_profile_inputs_are_checked(self):
        with tempfile.TemporaryDirectory() as value:
            checkout = _Checkout.create(Path(value).resolve())
            legacy = {**checkout.profile, "schema_version": 2}
            cases = [
                ({"PROFILE_DIGEST": "0" * 64}, "digest"),
                ({"PROFILE_VERSION": "2026-01-02.1"}, "version"),
                ({"DISPATCH_ID": "short"}, "identity"),
                ({"APPROVAL_ID": "approval/1"}, "identity"),
                ({"PROFILE_ID": "other-profile"}, "mismatch"),
                ({"GITHUB_SHA": "abc"}, "GITHUB_SHA"),
                ({"GITHUB_RUN_ID": "x"}, "GITHUB_RUN_ID"),
                ({"GITHUB_RUN_ATTEMPT": "0"}, "GITHUB_RUN_ATTEMPT"),
                ({"PROFILE_JSON": json.dumps(legacy)}, "schema"),
                ({"PROFILE_JSON": "not json"}, "PROFILE_JSON"),
            ]
            for name in (
                "PROFILE_ID", "APPROVAL_ID", "DISPATCH_ID", "PROFILE_JSON",
                "PROFILE_VERSION", "PROFILE_DIGEST", "GITHUB_RUN_ID",
                "GITHUB_RUN_ATTEMPT", "GITHUB_SHA",
            ):
                cases.append(({name: None}, f"{name} is required"))
            for overrides, message in cases:
                with self.subTest(overrides=overrides):
                    # Inputs are refused before the working tree is read.
                    with self.assertRaisesRegex(SystemExit, message):
                        INSTALLER.build_installation(
                            checkout.environment(**overrides)
                        )
            completed = checkout.install(PROFILE_DIGEST="0" * 64)
            self.assertNotEqual(completed.returncode, 0)
            self.assertIn("digest", completed.stderr)
            self.assertTrue(checkout.nothing_installed())

    def test_installer_runs_only_from_the_repository_root(self):
        with tempfile.TemporaryDirectory() as value:
            checkout = _Checkout.create(Path(value).resolve())
            completed = checkout.install(cwd=checkout.root / "scripts")
            self.assertNotEqual(completed.returncode, 0)
            self.assertIn("repository root", completed.stderr)
            self.assertTrue(checkout.nothing_installed())

    def test_delivered_files_must_match_the_frozen_source_verifier(self):
        with tempfile.TemporaryDirectory() as value:
            checkout = _Checkout.create(Path(value).resolve())
            self.assertEqual(checkout.install().returncode, 0)
            profile = checkout.profile_path.read_bytes()
            proof = checkout.proof_path.read_bytes()
            completed = checkout.install(
                "receive",
                PROFILE_B64=base64.b64encode(profile).decode(),
                PROOF_B64=base64.b64encode(proof).decode(),
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            tampered = json.loads(proof)
            tampered["installer_run_id"] += 1
            completed = checkout.install(
                "receive",
                PROFILE_B64=base64.b64encode(profile).decode(),
                PROOF_B64=base64.b64encode(
                    (json.dumps(tampered, indent=2, sort_keys=True) + "\n").encode()
                ).decode(),
            )
            self.assertNotEqual(completed.returncode, 0)
            self.assertIn("differs from the approved source proof", completed.stderr)
            completed = checkout.install("receive", PROOF_B64=None)
            self.assertNotEqual(completed.returncode, 0)
            self.assertIn("PROFILE_B64 is required", completed.stderr)


if __name__ == "__main__":
    unittest.main()
