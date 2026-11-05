"""Connect Codex, verification and permission installer coordination."""

import base64
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest

KIT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(KIT / "scripts" / "agent"))
sys.dont_write_bytecode = True

from providers import runtime_admin  # noqa: E402

HOST = {"hostId": "acme-agent-host", "daemon": "ABCD:EFGH:IJKL:MNOP", "executionDirectory": "/opt/ii-os/agent_execution",
        "iiOsRepository": "acme-co/ii-os", "iiOsCommit": "1" * 40, "runtimeRevision": "2" * 40, "codexVersion": "0.164.0"}
SESSION = "0f0e0d0c-0b0a-4908-8706-050403020100"
SECRET = "github-source-read-token-value"


class FakeController:
    calls = []
    outputs = {}
    cleaned = True

    def __init__(self, host, state, *, scripts):
        pass

    def run(self, request, *, entry):
        FakeController.calls.append(json.loads(json.dumps(request)))
        assert entry == "runtime_admin_controller.mjs"
        return {"schemaVersion": 1, "owner": request["owner"], "daemon": HOST["daemon"], "controllerAbsent": True,
                "outcome": {"schemaVersion": 1, "operationSucceeded": True, "outputs": FakeController.outputs,
                            "credentialCleanupConfirmed": FakeController.cleaned,
                            "execution": {"outcome": {"cleanupConfirmed": FakeController.cleaned}}}}


class AdminCoordinatorTest(unittest.TestCase):
    def setUp(self):
        FakeController.calls = []
        FakeController.cleaned = True
        self.root = Path(os.path.realpath(tempfile.mkdtemp()))
        os.chmod(self.root, 0o700)  # nosemgrep: python.lang.security.audit.insecure-file-permissions.insecure-file-permissions -- Directory traversal is required; mode 0700 grants access only to its owner.
        output = self.root / "github-output"
        output.write_text("")
        self.base = {"GITHUB_REPOSITORY": "acme-co/example-app", "GITHUB_REPOSITORY_ID": "101", "GITHUB_RUN_ID": "303",
                     "GITHUB_RUN_ATTEMPT": "1", "GITHUB_SHA": "3" * 40, "GITHUB_OUTPUT": str(output),
                     "II_OS_CONNECTOR_URL": "https://ii-os.example.com/api", "II_OS_RUNTIME_AUTHORIZED": "1",
                     "ACTIONS_ID_TOKEN_REQUEST_URL": "https://pipelines.actions.githubusercontent.com/token?x=1",
                     "ACTIONS_ID_TOKEN_REQUEST_TOKEN": "oidc-request-token-value",
                     "II_OS_AGENT_ALLOCATION": json.dumps({"allocationId": "acme-agents", "monthlyLimit": 100,
                                                           "capacity": {"cpu": 4, "memoryMiB": 8192, "diskGiB": 80}})}

    def installer(self, **overrides):
        environment = {**self.base, "II_OS_RUNTIME_KIND": "permission-installer", "GITHUB_SOURCE_READ_TOKEN": SECRET,
                       "APPROVAL_ID": "approval-1", "DISPATCH_ID": "d" * 24, "DISPATCH_FENCE": "1", "WORKSPACE_ID": "acme-workspace",
                       "PROFILE_ID": "repository-maintainer", "PROFILE_JSON": "{}", "PROFILE_VERSION": "1", "PROFILE_DIGEST": "e" * 64,
                       **overrides}
        return environment

    def test_installer_runs_no_worker_and_retains_no_secret(self):
        FakeController.outputs = {"profile_b64": base64.b64encode(b"{}").decode(), "proof_b64": base64.b64encode(b"{}").decode()}
        receipt = runtime_admin.coordinate(self.installer(), root=self.root, host=HOST, worker=None, controller_factory=FakeController)
        self.assertTrue(receipt["operationSucceeded"])
        request = FakeController.calls[0]
        self.assertEqual(request["operation"], "execute")
        self.assertEqual(request["envelope"]["settings"]["secrets"], {"GITHUB_SOURCE_READ_TOKEN": SECRET})
        self.assertNotIn("oidc", request["envelope"]["settings"])
        for path in self.root.rglob("*.json"):
            self.assertNotIn(SECRET, path.read_text(), str(path))
        # An independent cleanup observer re-reads the proof and launches nothing.
        again = runtime_admin.coordinate(self.installer(), root=self.root, host=HOST, worker=None,
                                         controller_factory=FakeController, recover=True)
        self.assertEqual(again["outputs"], receipt["outputs"])
        self.assertEqual(len(FakeController.calls), 1)

    def test_unconfirmed_cleanup_stops_publication(self):
        FakeController.outputs = {"profile_b64": "e30=", "proof_b64": "e30="}
        FakeController.cleaned = False
        with self.assertRaisesRegex(RuntimeError, "cleanup is unconfirmed"):
            runtime_admin.coordinate(self.installer(), root=self.root, host=HOST, worker=None, controller_factory=FakeController)

    def test_codex_sign_in_is_bound_to_its_session_and_repository(self):
        FakeController.outputs = {}
        worker = {"cpu": 2, "memoryMiB": 2048, "diskGiB": 8}
        environment = {**self.base, "II_OS_RUNTIME_KIND": "codex-auth", "II_OS_CODEX_AUTH_SESSION_ID": SESSION,
                       "II_OS_CODEX_AUTH_REPOSITORY": "acme-co/example-app", "II_OS_CODEX_AUTH_REAUTHENTICATE": "true"}
        with self.assertRaisesRegex(RuntimeError, "session identity"):
            runtime_admin.coordinate({**environment, "II_OS_CODEX_AUTH_SESSION_ID": "not-a-session"}, root=self.root,
                                     host=HOST, worker=worker, controller_factory=FakeController)
        with self.assertRaisesRegex(RuntimeError, "differs from the workflow repository"):
            runtime_admin.coordinate({**environment, "II_OS_CODEX_AUTH_REPOSITORY": "acme-co/other"}, root=self.root,
                                     host=HOST, worker=worker, controller_factory=FakeController)
        runtime_admin.coordinate(environment, root=self.root, host=HOST, worker=worker, controller_factory=FakeController)
        settings = FakeController.calls[0]["envelope"]["settings"]
        # Reconnecting deliberately starts without the stored credential.
        self.assertEqual(settings["secrets"], {})
        self.assertEqual(settings["connector"], "https://ii-os.example.com/api")
        self.assertEqual(settings["allocation"]["allocationId"], "acme-agents")

    def test_recovery_requires_the_original_intent_and_never_gets_secrets(self):
        with self.assertRaisesRegex(RuntimeError, "intent is unavailable"):
            runtime_admin.coordinate(self.installer(), root=self.root, host=HOST, worker=None,
                                     controller_factory=FakeController, recover=True)
        FakeController.outputs = {}
        FakeController.cleaned = False
        with self.assertRaises(RuntimeError):
            runtime_admin.coordinate(self.installer(), root=self.root, host=HOST, worker=None, controller_factory=FakeController)
        FakeController.cleaned = True
        FakeController.outputs = {"profile_b64": "e30=", "proof_b64": "e30="}
        runtime_admin.coordinate(self.installer(GITHUB_RUN_ATTEMPT="2"), root=self.root, host=HOST, worker=None,
                                 controller_factory=FakeController, recover=True)
        recovery = FakeController.calls[-1]
        self.assertEqual(recovery["operation"], "recover")
        self.assertNotIn("secrets", recovery["envelope"]["settings"])

    def test_a_different_host_cannot_recover_the_execution(self):
        FakeController.outputs = {}
        FakeController.cleaned = False
        with self.assertRaises(RuntimeError):
            runtime_admin.coordinate(self.installer(), root=self.root, host=HOST, worker=None, controller_factory=FakeController)
        with self.assertRaisesRegex(RuntimeError, "changed the original execution"):
            runtime_admin.coordinate(self.installer(), root=self.root, host={**HOST, "daemon": "OTHER:DAEMON:ID"}, worker=None,
                                     controller_factory=FakeController, recover=True)


if __name__ == "__main__":
    unittest.main()
