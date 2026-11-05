"""Work-ticket coordinator: frozen inputs, one launch, publication gates."""

import base64
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest

KIT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(KIT / "scripts" / "agent"))
sys.dont_write_bytecode = True

from agent_task_profile import canonical_profile_digest  # noqa: E402
from providers import host, runtime_ticket  # noqa: E402

REPOSITORY = "acme-co/example-app"
SOURCE = "3" * 40
DEV = "4" * 40
DISPATCH = "human:" + "a" * 32 + ":PVTI_example"
OIDC_SECRET = "oidc-request-token-not-for-retention"
HOST = {"hostId": "acme-agent-host", "daemon": "ABCD:EFGH:IJKL:MNOP", "executionDirectory": "/opt/ii-os/agent_execution",
        "iiOsRepository": "acme-co/ii-os", "iiOsCommit": "1" * 40,
        "runtimeRevision": json.loads((KIT / ".ii-os/runtimes/execution-binding.json").read_text())["runtimeRevision"],
        "codexVersion": "0.164.0"}


def runtime_file(name):
    return (KIT / ".ii-os/runtimes" / name).read_bytes()


def profile():
    return {
        "schema_version": 4, "engine": "codex", "id": "repository-maintainer", "version": "2026-11-04.1",
        "display_name": "Repository maintainer", "description": "Implements and verifies repository changes.",
        "allowed_actions": ["Read and edit files in the selected repository"],
        "denied_actions": ["Use credentials not declared by this profile"],
        "repository_actions": {"mode": "maintain_dev"},
        "runtime": {
            "configuration": {"path": ".ii-os/runtimes/repository-maintainer.json",
                              "sha256": hashlib.sha256(runtime_file("repository-maintainer.json")).hexdigest()},
            "execution_binding": {"path": ".ii-os/runtimes/execution-binding.json",
                                  "sha256": hashlib.sha256(runtime_file("execution-binding.json")).hexdigest()},
        },
        "workflow": {"file": "ii-os-agent-task.yml", "ref": "dev"},
    }


class FakeGitHub:
    def __init__(self, approved):
        self.approved = approved

    def get(self, path):
        if path == "repos/" + REPOSITORY:
            return {"full_name": REPOSITORY, "id": 101}
        if path == "repos/" + REPOSITORY + "/git/ref/heads/dev":
            return {"object": {"sha": DEV}}
        raise AssertionError(path)

    def file(self, repository, path, revision):
        assert repository == REPOSITORY and revision == SOURCE
        if path == ".ii-os/agent-permissions/repository-maintainer.json":
            return json.dumps(self.approved).encode()
        return (KIT / path).read_bytes()


class FakeController:
    """Stands in for LocalController; scenarios decide the controller outcome."""

    calls = []
    scenario = "completed"

    def __init__(self, host_binding, state, *, scripts):
        self.state = Path(state)

    def run(self, request, *, entry):
        FakeController.calls.append(json.loads(json.dumps(request)))
        assert entry == "runtime_ticket_controller.mjs"
        if FakeController.scenario == "cleanup-unconfirmed":
            return {"schemaVersion": 1, "owner": request["owner"], "daemon": HOST["daemon"], "controllerAbsent": True,
                    "outcome": {"schemaVersion": 1, "credentialCleanupConfirmed": True,
                                "execution": {"outcome": {"cleanupConfirmed": False, "status": "unknown"}}}}
        if FakeController.scenario == "admission-denied":
            execution = {"schemaVersion": 1, "executionId": "github:101:202:work-ticket", "attemptId": "1",
                         "inputDigest": "sha256:" + "c" * 64, "artifactDigest": "sha256:" + "d" * 64, "started": False,
                         "acquired": False, "phase": "admission", "status": "never-acquired",
                         "admission": {"disposition": "denied"}, "cleanupConfirmed": True,
                         "cleanup": [{"component": "runtime", "confirmed": True, "absent": True}]}
            return self.receipt(request, execution)
        settings = request["envelope"]["settings"]
        identity = settings["identity"]
        result = {"dispatch_id": identity["dispatchId"], "repository": REPOSITORY, "repository_id": 101, "issue_number": 7,
                  "project_item_id": identity["projectItemId"], "outcome": "ready_for_qa", "status": "ready_for_qa",
                  "comments": ["Implemented and verified."], "automation_failure": None,
                  "pull_request": {"repository": REPOSITORY, "repository_id": 101,
                                   "head": "ii-os-agent/" + hashlib.sha256(identity["dispatchId"].encode()).hexdigest()[:32],
                                   "base": "dev", "head_sha": "5" * 40, "base_sha": DEV, "expected_old_head_sha": None}}
        collection = host.private_directory(host.private_directory(host.private_directory(self.state / "controller") / "collections") / ("collection-Ab" + str(request["attempt"])))
        result_bytes = json.dumps(result).encode()
        bundle_bytes = b"# v2 git bundle\nexample\n"
        references = {}
        for name, value in [("result.json", result_bytes), ("change.bundle", bundle_bytes)]:
            path = collection / name
            descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            os.write(descriptor, value)
            os.close(descriptor)
            references[name] = {"reference": str(path), "digest": "sha256:" + hashlib.sha256(value).hexdigest(), "bytes": len(value)}
        execution = {"cleanupConfirmed": True, "status": "failed" if FakeController.scenario == "failed" else "completed",
                     "usage": {"reported": FakeController.scenario != "usage-unreported"},
                     "result": {"result": result, "resultArtifact": references["result.json"], "bundle": references["change.bundle"]}}
        return self.receipt(request, execution)

    def receipt(self, request, execution):
        return {"schemaVersion": 1, "owner": request["owner"], "daemon": HOST["daemon"], "host": HOST["hostId"],
                "controllerAbsent": True, "exitCode": 0,
                "outcome": {"schemaVersion": 1, "credentialCleanupConfirmed": True, "execution": {"outcome": execution}}}


class CoordinatorTest(unittest.TestCase):
    def setUp(self):
        FakeController.calls = []
        FakeController.scenario = "completed"
        self.root = Path(os.path.realpath(tempfile.mkdtemp()))
        os.chmod(self.root, 0o700)  # nosemgrep: python.lang.security.audit.insecure-file-permissions.insecure-file-permissions -- Directory traversal is required; mode 0700 grants access only to its owner.
        handoff = Path(os.path.realpath(tempfile.mkdtemp()))
        os.chmod(handoff, 0o700)  # nosemgrep: python.lang.security.audit.insecure-file-permissions.insecure-file-permissions -- Directory traversal is required; mode 0700 grants access only to its owner.
        self.outputs = self.root / "github-output"
        self.outputs.write_text("")
        prompt = json.dumps({"repository": REPOSITORY, "repository_id": 101, "issue_number": 7,
                             "project_item_id": "PVTI_example", "title": "Add a greeting"}).encode()
        self.prompt_digest = hashlib.sha256(prompt).hexdigest()
        self.approved = profile()
        stat = handoff.stat()
        self.environment = {
            "GITHUB_REPOSITORY_ID": "101", "GITHUB_RUN_ID": "202", "GITHUB_RUN_ATTEMPT": "1", "DISPATCH_ID": DISPATCH,
            "PERMISSION_DIGEST": canonical_profile_digest(self.approved), "PERMISSION_PROFILE": "repository-maintainer",
            "PERMISSION_REF": "dev", "TRUSTED_SOURCE_SHA": SOURCE, "TARGET_REPOSITORY": REPOSITORY, "ISSUE_NUMBER": "7",
            "PROJECT_ITEM_ID": "PVTI_example", "WORKSPACE_ID": "acme-workspace", "II_OS_GITHUB_APP_SLUG": "acme-agent",
            "GITHUB_API_APP_SLUG": "acme-agent", "IIAUTO_TICKET_PROMPT_B64": base64.b64encode(prompt).decode(),
            "IIAUTO_TICKET_PROMPT_SHA256": self.prompt_digest, "IIAUTO_APPROVAL_CONSUMED": "1",
            "CODEX_SECRET_DIGEST": "e" * 64, "II_OS_CONNECTOR_URL": "https://ii-os.example.com/api",
            "OIDC_AUDIENCE": "https://ii-os.example.com/api/v1/codex-auth-sessions",
            "II_OS_AGENT_ALLOCATION": json.dumps({"allocationId": "acme-agents", "monthlyLimit": 100,
                                                  "capacity": {"cpu": 4, "memoryMiB": 8192, "diskGiB": 80}}),
            "ACTIONS_ID_TOKEN_REQUEST_URL": "https://pipelines.actions.githubusercontent.com/token?x=1",
            "ACTIONS_ID_TOKEN_REQUEST_TOKEN": OIDC_SECRET, "GITHUB_OUTPUT": str(self.outputs),
            "II_OS_AGENT_HANDOFF_DIR": str(handoff), "II_OS_AGENT_HANDOFF_DEVICE": str(stat.st_dev),
            "II_OS_AGENT_HANDOFF_INODE": str(stat.st_ino),
            "II_OS_AGENT_HANDOFF_DIGESTS": json.dumps({"ticket-prompt.json": self.prompt_digest}),
        }

    def coordinate(self, **overrides):
        return runtime_ticket.coordinate({**self.environment, **overrides}, root=self.root, host=HOST,
                                         controller_factory=FakeController, github=FakeGitHub(self.approved))

    def outputs_map(self):
        return dict(line.split("=", 1) for line in self.outputs.read_text().splitlines())

    def test_completed_run_authorizes_publication_of_the_exact_bundle(self):
        self.coordinate()
        outputs = self.outputs_map()
        self.assertEqual(outputs["runtime_cleanup_proven"], "true")
        self.assertEqual(outputs["runtime_usage_proven"], "true")
        result = json.loads(base64.b64decode(outputs["agent_result_b64"]))
        self.assertEqual(result["dispatch_id"], DISPATCH)
        bundle = json.loads(base64.b64decode(outputs["agent_bundle_artifact_b64"]))
        self.assertEqual(bundle["path"], "artifacts/ii-os-agent-change.bundle")
        request = FakeController.calls[0]
        self.assertEqual((request["operation"], request["attempt"]), ("execute", 1))
        settings = request["envelope"]["settings"]
        self.assertEqual(settings["authorization"]["ticketPromptDigest"], self.prompt_digest)
        self.assertEqual(settings["repositories"], [{"repository": REPOSITORY, "path": "", "commit": DEV}])
        self.assertEqual(settings["allocation"]["allocationId"], "acme-agents")
        self.assertEqual(settings["task"]["appSlug"], "acme-agent")
        # The OIDC request token travels only to the controller, never to disk.
        for path in self.root.rglob("*.json"):
            self.assertNotIn(OIDC_SECRET, path.read_text(), str(path))

    def test_worker_policy_receives_deferred_status_labels(self):
        # The worker policy maps option labels to status names and refuses a
        # transition when they are empty; ii-os applies the real Project change.
        self.coordinate()
        task = FakeController.calls[0]["envelope"]["settings"]["task"]
        labels = [task[key] for key in ["projectId", "statusFieldId", "todoOptionId", "inProgressOptionId", "readyOptionId", "humanOptionId"]]
        self.assertTrue(all(labels), labels)
        self.assertEqual(len(set(labels)), len(labels))

    def test_unreported_usage_blocks_publication_and_finalization(self):
        FakeController.scenario = "usage-unreported"
        with self.assertRaises(runtime_ticket.UsageDeliveryPending):
            self.coordinate()
        outputs = self.outputs_map()
        self.assertEqual(outputs["runtime_cleanup_proven"], "true")
        self.assertEqual(outputs["runtime_usage_proven"], "false")
        self.assertNotIn("agent_result_b64", outputs)
        self.assertNotIn("agent_bundle_artifact_b64", outputs)

    def test_unconfirmed_cleanup_never_reports_cleanup(self):
        FakeController.scenario = "cleanup-unconfirmed"
        with self.assertRaisesRegex(RuntimeError, "cleanup is unconfirmed"):
            self.coordinate()
        self.assertNotIn("runtime_cleanup_proven", self.outputs_map())

    def test_a_failed_execution_cannot_publish_its_bundle(self):
        FakeController.scenario = "failed"
        self.coordinate()
        outputs = self.outputs_map()
        self.assertNotIn("agent_result_b64", outputs)
        self.assertNotIn("agent_bundle_artifact_b64", outputs)
        self.assertEqual(outputs["retry_failure_code"], "agent_result_missing")

    def test_a_rerun_only_recovers_the_original_execution(self):
        FakeController.scenario = "usage-unreported"
        with self.assertRaises(runtime_ticket.UsageDeliveryPending):
            self.coordinate()
        FakeController.scenario = "completed"
        self.coordinate(GITHUB_RUN_ATTEMPT="2")
        self.assertEqual([(call["operation"], call["attempt"]) for call in FakeController.calls], [("execute", 1), ("recover", 2)])
        # The rerun reuses the frozen launch, not a fresh read of GitHub.
        self.assertEqual(FakeController.calls[0]["inputDigest"], FakeController.calls[1]["inputDigest"])

    def test_admission_refusal_finalizes_without_a_run(self):
        FakeController.scenario = "admission-denied"
        self.coordinate()
        outputs = self.outputs_map()
        self.assertEqual(outputs["runtime_execution_never_started"], "true")
        self.assertEqual(outputs["retry_failure_code"], "agent_runtime_admission_denied")
        self.assertEqual(outputs["runtime_usage_proven"], "false")

    def test_a_changed_profile_or_prompt_is_refused_before_launch(self):
        with self.assertRaisesRegex(RuntimeError, "changed after approval"):
            self.coordinate(PERMISSION_DIGEST="f" * 64)
        self.assertEqual(FakeController.calls, [])
        with self.assertRaisesRegex(RuntimeError, "another approved prompt"):
            runtime_ticket.coordinate({**self.environment, "GITHUB_RUN_ID": "203",
                                       "II_OS_AGENT_HANDOFF_DIGESTS": json.dumps({"ticket-prompt.json": "0" * 64})},
                                      root=self.root, host=HOST, controller_factory=FakeController, github=FakeGitHub(self.approved))
        self.assertEqual(FakeController.calls, [])

    def test_a_second_launch_for_the_same_run_is_refused(self):
        self.coordinate()
        with self.assertRaisesRegex(RuntimeError, "recover the original execution"):
            self.coordinate()



class ApprovedEngineTest(unittest.TestCase):
    """Preflight refuses an engine without an executor before the approval is consumed."""

    def repository(self, value):
        root = Path(tempfile.mkdtemp())
        (root / ".ii-os" / "agent-permissions").mkdir(parents=True)
        (root / ".ii-os" / "agent-permissions" / "local-coder.json").write_text(json.dumps(value))
        return root

    def environment(self, value):
        return {"PERMISSION_PROFILE": "local-coder", "PERMISSION_DIGEST": canonical_profile_digest(value)}

    def test_codex_profile_is_accepted(self):
        value = {**profile(), "id": "local-coder"}
        runtime_ticket.check_approved_engine(self.environment(value), self.repository(value))

    def test_local_model_engine_is_refused_by_name(self):
        value = {**profile(), "id": "local-coder", "engine": "qwen38-local", "schema_version": 3}
        with self.assertRaisesRegex(host.HostBindingError, "qwen38-local.*no executor"):
            runtime_ticket.check_approved_engine(self.environment(value), self.repository(value))

    def test_a_profile_changed_after_approval_is_refused(self):
        value = {**profile(), "id": "local-coder"}
        with self.assertRaisesRegex(host.HostBindingError, "changed after approval"):
            runtime_ticket.check_approved_engine({**self.environment(value), "PERMISSION_DIGEST": "0" * 64}, self.repository(value))


if __name__ == "__main__":
    unittest.main()
