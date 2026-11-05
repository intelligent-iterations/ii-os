"""The bound host: explicit identity, toolchain pins and controller lifecycle."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unittest

KIT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(KIT / "scripts" / "agent"))
sys.dont_write_bytecode = True

from providers import host  # noqa: E402

COMMIT = "1" * 40
RUNTIME = json.loads((KIT / ".ii-os/runtimes/execution-binding.json").read_text())["runtimeRevision"]
NODE = shutil.which("node")


class FakeSystem:
    def __init__(self, **overrides):
        self.files = {
            str(host.HOST_ID_FILE): b"acme-agent-host\n",
            str(host.CONTROLLER_FILE): json.dumps({"schemaVersion": 1, "iiOsRepository": "acme-co/ii-os", "iiOsCommit": COMMIT,
                                                  "codexVersion": "0.164.0", "runtimeRevision": RUNTIME}).encode(),
        }
        self.results = {
            "node": (0, b"v22.16.0\n"), "codex": (0, b"codex-cli 0.164.0\n"),
            "docker": (0, b'"ABCD:EFGH:IJKL:MNOP"\n'), "sudo": (0, b""), "tofu": (0, b"OpenTofu v1.12.6\n"),
            "gh": (0, b"gh version 2.45.0\n"),
        }
        self.results.update(overrides.pop("results", {}))
        self.files.update(overrides.pop("files", {}))
        self.workspace_error = overrides.pop("workspace_error", None)

    def read(self, path, maximum=65536):
        value = self.files.get(str(path))
        if value is None:
            raise FileNotFoundError(path)
        return value

    def run(self, command, *, timeout=30, maximum=65536):
        return self.results[Path(command[0]).name]

    def workspace(self):
        if self.workspace_error:
            raise host.HostBindingError(self.workspace_error)


def repository(commit=COMMIT):
    root = Path(tempfile.mkdtemp())
    (root / ".ii-os" / "runtimes").mkdir(parents=True)
    shutil.copy(KIT / ".ii-os/runtimes/execution-binding.json", root / ".ii-os/runtimes/execution-binding.json")
    (root / ".ii-os/agent-controller.json").write_text(json.dumps(
        {"schemaVersion": 1, "iiOsRepository": "acme-co/ii-os", "iiOsCommit": commit, "codexVersion": "0.164.0"}))
    return root


ENV = {"II_OS_AGENT_HOST_ID": "acme-agent-host"}


class HostBindingTest(unittest.TestCase):
    def test_bound_host_is_accepted_and_reports_its_daemon(self):
        binding = host.load_host(ENV, repository(), system=FakeSystem())
        self.assertEqual(binding["hostId"], "acme-agent-host")
        self.assertEqual(binding["daemon"], "ABCD:EFGH:IJKL:MNOP")
        self.assertEqual(binding["iiOsCommit"], COMMIT)

    def assertNamed(self, message, *, environment=ENV, root=None, **system):
        with self.assertRaises(host.HostBindingError) as raised:
            host.load_host(environment, root or repository(), system=FakeSystem(**system))
        self.assertIn(message, str(raised.exception))

    def test_unconfigured_or_different_host_is_refused(self):
        self.assertNamed("II_OS_AGENT_HOST_ID is not configured", environment={})
        self.assertNamed("different agent host", files={str(host.HOST_ID_FILE): b"another-host\n"})

    def test_a_runner_without_the_host_identity_is_not_an_agent_host(self):
        system = FakeSystem()
        del system.files[str(host.HOST_ID_FILE)]
        with self.assertRaises(host.HostBindingError) as raised:
            host.load_host(ENV, repository(), system=system)
        self.assertIn("not an ii-os agent host", str(raised.exception))

    def test_placeholder_pin_must_be_replaced(self):
        self.assertNamed("placeholder ii-os commit", root=repository("0" * 40))
        self.assertNamed("placeholder ii-os commit", root=KIT)

    def test_controller_toolchain_must_match_reviewed_pins(self):
        changed = json.dumps({"schemaVersion": 1, "iiOsRepository": "acme-co/ii-os", "iiOsCommit": "2" * 40,
                              "codexVersion": "0.164.0", "runtimeRevision": RUNTIME}).encode()
        self.assertNamed("does not match the reviewed", files={str(host.CONTROLLER_FILE): changed})
        self.assertNamed("Node.js 22.16", results={"node": (0, b"v22.15.9\n")})
        self.assertNamed("Codex does not match", results={"codex": (0, b"codex-cli 0.165.0\n")})

    def test_host_capabilities_fail_by_name(self):
        self.assertNamed("Docker Engine", results={"docker": (1, b"")})
        self.assertNamed("passwordless sudo for iptables", results={"sudo": (1, b"")})
        self.assertNamed("OpenTofu", results={"tofu": (127, b"")})
        self.assertNamed("GitHub CLI", results={"gh": (127, b"")})
        self.assertNamed("/workspace/repository", workspace_error="/workspace/repository must be absent or empty before a run")


class StateRootTest(unittest.TestCase):
    def test_state_directory_must_be_absolute_canonical_and_private(self):
        with self.assertRaises(host.HostBindingError):
            host.state_root({"II_OS_AGENT_STATE_DIR": "relative/state"})
        root = Path(os.path.realpath(tempfile.mkdtemp()))
        os.chmod(root, 0o755)  # nosemgrep: python.lang.security.audit.insecure-file-permissions.insecure-file-permissions -- The rejection test deliberately creates a directory accessible to other users.
        with self.assertRaises(host.HostBindingError):
            host.state_root({"II_OS_AGENT_STATE_DIR": str(root)})
        os.chmod(root, 0o700)  # nosemgrep: python.lang.security.audit.insecure-file-permissions.insecure-file-permissions -- Directory traversal is required; mode 0700 grants access only to its owner.
        self.assertEqual(host.state_root({"II_OS_AGENT_STATE_DIR": str(root)}), root)
        link = Path(os.path.realpath(tempfile.mkdtemp())) / "link"
        link.symlink_to(root)
        with self.assertRaises(host.HostBindingError):
            host.state_root({"II_OS_AGENT_STATE_DIR": str(link)})


FAKE_CONTROLLER = r"""
import { readFileSync, writeFileSync } from 'node:fs';
const input = readFileSync(0, 'utf8');
const { settings } = JSON.parse(input);
writeFileSync(process.env.II_OS_CONTROLLER_STATE_DIR + '/seen-' + settings.controllerAttempt + '.json', JSON.stringify({
  settings, env: Object.keys(process.env).sort(), cwd: process.cwd() }), { mode: 0o600 });
if (settings.sleepMs) await new Promise(resolve => setTimeout(resolve, settings.sleepMs));
process.stdout.write(JSON.stringify({ schemaVersion: 1, credentialCleanupConfirmed: true,
  execution: { outcome: { cleanupConfirmed: true, status: 'completed' } } }) + '\n');
"""


@unittest.skipUnless(NODE, "node is required")
class LocalControllerTest(unittest.TestCase):
    def setUp(self):
        self.root = Path(os.path.realpath(tempfile.mkdtemp()))
        os.chmod(self.root, 0o700)  # nosemgrep: python.lang.security.audit.insecure-file-permissions.insecure-file-permissions -- Directory traversal is required; mode 0700 grants access only to its owner.
        self.scripts = Path(tempfile.mkdtemp())
        (self.scripts / "controller.mjs").write_text(FAKE_CONTROLLER)
        self.owner = "a" * 64
        self.state = host.execution_state(self.root, self.owner)
        self.binding = {"hostId": "acme-agent-host", "daemon": "ABCD:EFGH:IJKL:MNOP", "executionDirectory": str(KIT)}

    def controller(self):
        controller = host.LocalController(self.binding, self.state, scripts=self.scripts)
        controller._spawn = self.spawn_with(controller._spawn)
        return controller

    def spawn_with(self, original):
        def spawn(child_ref, command, **kwargs):
            return original(child_ref, [NODE, *command[1:]], **kwargs)
        return spawn

    def request(self, operation, attempt, token="oidc-request-token-value"):
        return {"owner": self.owner, "purpose": "work-ticket", "inputDigest": "sha256:" + "b" * 64, "timeoutSeconds": 60,
                "operation": operation, "attempt": attempt, "admissionDirectory": str(host.private_directory(self.root / "admission")),
                "envelope": {"settings": {"oidc": {"requestToken": token}}, "handoff": {}}}

    def test_execute_runs_one_controller_and_retains_no_envelope(self):
        receipt = self.controller().run(self.request("execute", 1), entry="controller.mjs")
        self.assertTrue(receipt["controllerAbsent"])
        self.assertEqual(receipt["outcome"]["credentialCleanupConfirmed"], True)
        seen = json.loads((self.state / "controller" / "seen-1.json").read_text())
        self.assertEqual(seen["settings"]["mode"], "execute")
        self.assertRegex(seen["settings"]["controller"]["id"], r"^[a-f0-9]{64}$")
        self.assertEqual(seen["settings"]["controller"]["daemon"], "ABCD:EFGH:IJKL:MNOP")
        self.assertNotIn("previousControllersAbsent", seen["settings"])
        # The controller's environment is explicit; no workflow secret leaks in.
        self.assertNotIn("CODEX_AUTH_JSON", seen["env"])
        self.assertNotIn("II_OS_GITHUB_APP_PRIVATE_KEY", seen["env"])
        for path in self.state.glob("*.json"):
            self.assertNotIn("oidc-request-token-value", path.read_text(), path.name)
        # The job-scoped scratch area is removed after the controller exits.
        self.assertFalse(Path(seen["cwd"]).exists())

    def test_a_second_launch_is_refused_and_retries_only_recover(self):
        self.controller().run(self.request("execute", 1), entry="controller.mjs")
        with self.assertRaisesRegex(RuntimeError, "recover the original execution"):
            self.controller().run(self.request("execute", 1), entry="controller.mjs")
        with self.assertRaisesRegex(RuntimeError, "only the first observer may launch"):
            self.controller().run(self.request("execute", 2), entry="controller.mjs")
        self.controller().run(self.request("recover", 2), entry="controller.mjs")
        seen = json.loads((self.state / "controller" / "seen-2.json").read_text())
        proof = seen["settings"]["previousControllersAbsent"]
        original = json.loads((self.state / "controller-1.json").read_text())
        self.assertEqual(proof["originalController"], {"id": original["id"], "name": original["name"]})
        self.assertRegex(original["name"], r"^ii-os-controller-[A-Za-z0-9-]{1,128}$")
        self.assertEqual(proof["daemon"], self.binding["daemon"])

    def test_recovery_waits_for_the_original_controller_to_exit(self):
        request = self.request("execute", 1)
        request["envelope"]["settings"]["sleepMs"] = 3000
        first = threading.Thread(target=lambda: self.controller().run(request, entry="controller.mjs"))
        first.start()
        time.sleep(1)
        # The provider and its controller hold the lock for their whole lives.
        with self.assertRaisesRegex(RuntimeError, "still running"):
            with host.operation_lock(self.state, wait_seconds=0):
                pass
        first.join()
        with host.operation_lock(self.state, wait_seconds=0):
            pass

    def test_recovery_without_intent_proves_nothing_started(self):
        controller = self.controller()
        original = host.bounded_process

        def inventory(command, **kwargs):
            if command[0] == "docker":
                return 0, b""
            return original(command, **kwargs)
        host.bounded_process = inventory
        try:
            receipt = controller.run(self.request("recover", 1), entry="controller.mjs")
        finally:
            host.bounded_process = original
        outcome = receipt["outcome"]["execution"]["outcome"]
        self.assertEqual(outcome["status"], "never-acquired")
        self.assertEqual(outcome["phase"], "provider-startup")
        self.assertFalse((self.state / "controller" / "seen-1.json").exists())

    def test_runtime_resources_left_by_another_run_make_absence_ambiguous(self):
        controller = self.controller()
        original = host.bounded_process
        host.bounded_process = lambda command, **kwargs: (0, b"0123456789ab\n")
        try:
            with self.assertRaisesRegex(RuntimeError, "ambiguous"):
                controller.run(self.request("recover", 1), entry="controller.mjs")
        finally:
            host.bounded_process = original


class CollectionArtifactTest(unittest.TestCase):
    def test_only_collected_files_with_matching_digest_are_read(self):
        state = Path(os.path.realpath(tempfile.mkdtemp()))
        collection = state / "controller" / "collections" / "collection-AbC123"
        collection.mkdir(parents=True)
        path = collection / "result.json"
        path.write_bytes(b'{"ok":true}')
        os.chmod(path, 0o600)
        import hashlib
        reference = {"reference": str(path), "digest": "sha256:" + hashlib.sha256(b'{"ok":true}').hexdigest(), "bytes": 11}
        self.assertEqual(host.read_collection_artifact(state, reference), b'{"ok":true}')
        with self.assertRaisesRegex(RuntimeError, "changed"):
            host.read_collection_artifact(state, {**reference, "digest": "sha256:" + "0" * 64})
        outside = state / "elsewhere.json"
        outside.write_bytes(b"{}")
        with self.assertRaisesRegex(RuntimeError, "descriptor is invalid"):
            host.read_collection_artifact(state, {**reference, "reference": str(outside)})


if __name__ == "__main__":
    unittest.main()
