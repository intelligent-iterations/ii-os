"""Compose the workflow's consumed approval, the bound host and the runtime.

No model, authentication, QA or publication policy lives here: the ii-os
agent_execution package and the reviewed worker helpers own those behaviours.
The workflow publishes only after this coordinator proves worker, controller
and credential cleanup, and every result path reports usage or says why not.

Capacity across runs is ii-os's own admission ledger (agent_execution
openAdmission) over the operator's explicitly partitioned allocation in
II_OS_AGENT_ALLOCATION. A retried workflow recovers the original execution;
it never launches the agent a second time.
"""

from __future__ import annotations

import base64
import copy
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import uuid

from agent_task_profile import canonical_profile_digest
from agent_task_result import verified_agent_result_artifact
from .host import (HostBindingError, LocalController, canonical, digest, durable, execution_state, load_host, owner_for,
                   private_directory, private_json, read_collection_artifact, state_root)
from .runtime_ticket_inputs import allocation, github_from_environment, resolve_inputs


SCRIPTS = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
DEFAULT_TIMEOUT_MINUTES = 60


class UsageDeliveryPending(RuntimeError):
    pass


def github_output(environment, name, value):
    if "\n" in value or "\r" in value:
        raise RuntimeError("workflow output exceeded its transport boundary")
    with open(environment["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
        output.write(name + "=" + value + "\n")


def encode(value):
    return base64.b64encode(canonical(value)).decode()


def retain_artifact(state, reference, path, artifact_root, scope, owner):
    """Copy one collected runtime file into the retained artifact store."""
    if not isinstance(reference, dict):
        raise RuntimeError("runtime result artifact is unavailable")
    maximum = 32768 if path.endswith(".json") else 67108864
    if type(reference.get("bytes")) is not int or not 0 <= reference["bytes"] <= maximum:
        raise RuntimeError("runtime artifact exceeded its size ceiling")
    value = read_collection_artifact(state, reference, maximum)
    relative = "/".join(["ii-os-agent", scope, owner[:32], path])
    destination = artifact_root / relative
    parent = artifact_root
    for part in Path(relative).parts[:-1]:
        parent = private_directory(parent / part)
    if destination.exists():
        if destination.is_symlink() or destination.read_bytes() != value:
            raise RuntimeError("retained runtime artifact changed")
    else:
        descriptor = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        try:
            offset = 0
            while offset < len(value):
                offset += os.write(descriptor, value[offset:])
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
        descriptor = os.open(parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
    return {"path": path, "storage_path": relative, "size_bytes": len(value),
            "sha256": reference["digest"].removeprefix("sha256:"),
            "content_type": "application/json" if path.endswith(".json") else "application/octet-stream"}


def validate_never_acquired(execution, *, settings, owner, controller, deployment):
    identity = settings["identity"]
    expected_id = f'github:{identity["repositoryId"]}:{identity["runId"]}:work-ticket'
    if execution.get("phase") == "provider-startup":
        proof = execution.get("provider")
        if not isinstance(proof, dict) or set(proof) != {"owner", "daemon", "deploymentInputDigest", "inventoriesEmpty"} or any([
            execution.get("schemaVersion") != 1, execution.get("started") is not False,
            execution.get("acquired") is not False, execution.get("deploymentInputDigest") != deployment["inputDigest"],
            execution.get("cleanup") != [{"component": "runtime", "confirmed": True, "absent": True}],
            "usage" in execution, "result" in execution, proof.get("owner") != owner,
            proof.get("daemon") != controller.get("daemon"), proof.get("inventoriesEmpty") is not True,
            proof.get("deploymentInputDigest") != deployment["inputDigest"],
        ]) or not isinstance(proof.get("daemon"), str) or not re.fullmatch(r"[A-Za-z0-9:-]{8,256}", proof["daemon"]):
            raise RuntimeError("runtime absence proof changed its provider startup binding")
        return "agent_runtime_startup_interrupted", "Deployment stopped before its execution controller started. No agent was acquired; cleanup is confirmed. This pass cannot launch on retry."
    invalid = (
        execution.get("schemaVersion") != 1 or execution.get("executionId") != expected_id
        or execution.get("attemptId") != "1"
        or execution.get("started") is not False or execution.get("acquired") is not False
        or execution.get("cleanup") != [{"component": "runtime", "confirmed": True, "absent": True}]
        or "usage" in execution or "result" in execution
    )
    if invalid:
        raise RuntimeError("runtime absence proof is invalid")
    if execution.get("phase") == "admission":
        if execution.get("admission", {}).get("disposition") not in {"denied", "waiting-for-capacity"} or any(
            not isinstance(execution.get(key), str) or not re.fullmatch(r"sha256:[a-f0-9]{64}", execution[key])
            for key in ["inputDigest", "artifactDigest"]
        ):
            raise RuntimeError("runtime absence proof is invalid")
        return "agent_runtime_admission_denied", "The configured admission limits refused this deployment before any agent started. Cleanup is confirmed; this pass cannot launch on retry."
    if execution.get("phase") != "preparation":
        raise RuntimeError("runtime absence proof is invalid")
    preparation = execution.get("preparation")
    if not isinstance(preparation, dict) or set(preparation) not in (
        {"schemaVersion", "executionId", "attemptId", "binding"},
        {"schemaVersion", "executionId", "attemptId", "binding", "providerProof"},
    ) or preparation.get("schemaVersion") != 1 or preparation.get("executionId") != expected_id or preparation.get("attemptId") != "1" or execution.get("preparationDigest") != digest(preparation):
        raise RuntimeError("runtime absence proof changed its preparation binding")
    binding = preparation.get("binding", {})
    original = binding.get("controller", {})
    expected_identity = {key: identity[key] for key in ["repository", "repositoryId", "runId", "issueNumber", "dispatchId", "projectItemId", "workspaceId"] if key in identity}
    expected_binding = {"identity": expected_identity, "permissionDigest": settings["permissionDigest"],
                        "sourceRevision": settings["sourceRevision"],
                        "approvedPromptDigest": settings["authorization"]["ticketPromptDigest"],
                        "repositories": settings["repositories"], "controller": original}
    if binding != expected_binding or set(original) != {"id", "daemon"} or original.get("daemon") != controller.get("daemon") or not isinstance(original.get("daemon"), str) or not re.fullmatch(r"[A-Za-z0-9:-]{8,256}", original["daemon"]) or original.get("id") is not None and not re.fullmatch(r"[a-f0-9]{64}", original["id"]):
        raise RuntimeError("runtime absence proof changed its preparation binding")
    proof = preparation.get("providerProof")
    if proof is not None:
        previous = proof.get("originalController")
        if set(proof) != {"confirmed", "owner", "daemon", "deploymentInputDigest", "originalController"} or proof.get("confirmed") is not True or proof.get("owner") != owner or proof.get("daemon") != original["daemon"] or proof.get("deploymentInputDigest") != deployment["inputDigest"] or (previous is None and original["id"] is not None) or (previous is not None and (set(previous) != {"id", "name"} or previous.get("id") != original["id"] or not re.fullmatch(r"ii-os-controller-[A-Za-z0-9-]{1,128}", previous.get("name", "")))):
            raise RuntimeError("runtime absence proof changed its provider binding")
    elif original["id"] is None:
        raise RuntimeError("runtime absence proof has no original controller")
    return "agent_runtime_preparation_interrupted", "Deployment preparation stopped before any agent was acquired. Cleanup is confirmed; this pass cannot launch on retry."


def never_acquired_delivery(execution, *, settings, state, attempt, owner, controller, deployment, environment):
    code, detail = validate_never_acquired(execution, settings=settings, owner=owner, controller=controller, deployment=deployment)
    receipt = {"schemaVersion": 1, "owner": owner, "cleanupConfirmed": True,
               "executionNeverStarted": True, "controller": controller, "artifacts": {}, "result": None}
    durable(state / ("delivery-observer-" + attempt + ".json"), receipt)
    github_output(environment, "runtime_cleanup_proven", "true")
    github_output(environment, "runtime_usage_proven", "false")
    github_output(environment, "runtime_execution_never_started", "true")
    github_output(environment, "retry_failure_code", code)
    github_output(environment, "retry_failure_detail", detail)
    return receipt


def next_observer(state, *, workflow_attempt, mode, deployment):
    journals = list(state.glob("runtime-observer-*.json"))
    if len(journals) >= 100:
        raise RuntimeError("runtime cleanup exceeded its observer ceiling")
    ids = []
    for path in journals:
        saved = private_json(path)
        value = saved.get("providerAttempt")
        if type(value) is not int or not 1 <= value <= 100 or path.name != f"runtime-observer-{value}.json" or saved.get("deploymentInputDigest") != deployment["inputDigest"]:
            raise RuntimeError("runtime observer journal changed its execution binding")
        ids.append(value)
    observer = max(ids or [0]) + 1
    if observer > 100 or mode == "execute" and observer != 1:
        raise RuntimeError("runtime observer cannot authorize another launch")
    durable(state / f"runtime-observer-{observer}.json", {
        "schemaVersion": 1, "providerAttempt": observer, "workflowAttempt": int(workflow_attempt),
        "mode": mode, "deploymentInputDigest": deployment["inputDigest"], "nonce": str(uuid.uuid4()),
    })
    return observer


def cleanup_observation(execution, *, settings, state, observer, owner, controller, deployment, environment):
    never_started = execution.get("status") == "never-acquired"
    if never_started:
        code, detail = validate_never_acquired(execution, settings=settings, owner=owner, controller=controller, deployment=deployment)
    else:
        code, detail = "agent_runtime_execution_interrupted", "The original runtime was reconciled after interruption. Cleanup is confirmed; its retained output requires workflow recovery."
    reported = not never_started and execution.get("usage", {}).get("reported") is True
    if not never_started and not reported:
        code, detail = "agent_usage_reporting_unconfirmed", "Execution cleanup is confirmed. Rerun this workflow to recover usage delivery for the original run."
    receipt = {"schemaVersion": 1, "owner": owner, "cleanupConfirmed": True,
               "cleanupOnly": True, "executionNeverStarted": never_started, "controller": controller}
    durable(state / f"cleanup-observer-{observer}.json", receipt)
    github_output(environment, "runtime_cleanup_proven", "true")
    github_output(environment, "runtime_usage_proven", "true" if reported else "false")
    if never_started:
        github_output(environment, "runtime_execution_never_started", "true")
    github_output(environment, "retry_failure_code", code)
    github_output(environment, "retry_failure_detail", detail)
    return receipt


def staged_handoff(environment):
    """The job-scoped, inode-bound credential handoff staged on this host."""
    directory = environment.get("II_OS_AGENT_HANDOFF_DIR", "")
    device, inode = environment.get("II_OS_AGENT_HANDOFF_DEVICE", ""), environment.get("II_OS_AGENT_HANDOFF_INODE", "")
    try:
        digests = json.loads(environment.get("II_OS_AGENT_HANDOFF_DIGESTS", ""))
    except ValueError:
        digests = None
    if not os.path.isabs(directory) or os.path.realpath(directory) != directory or not re.fullmatch(r"[0-9]{1,20}", device) \
            or not re.fullmatch(r"[0-9]{1,20}", inode) or not isinstance(digests, dict) \
            or any(not isinstance(value, str) or not re.fullmatch(r"[a-f0-9]{64}", value) for value in digests.values()):
        raise RuntimeError("the staged credential handoff is unavailable")
    return {"directory": directory, "device": int(device), "inode": int(inode), "digests": digests}


def coordinate(environment, *, root, host, controller_factory=LocalController, github=None, cleanup_only=False):
    repository_id, run_id, attempt = [environment.get(key, "") for key in ["GITHUB_REPOSITORY_ID", "GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT"]]
    if any(not re.fullmatch(r"[1-9][0-9]{0,15}", value) for value in [repository_id, run_id, attempt]) or int(attempt) > 100:
        raise RuntimeError("runtime coordinator identity is invalid")
    owner = owner_for({"repositoryId": repository_id, "runId": run_id}, "work-ticket")
    state = execution_state(root, owner)
    launch_file = state / "launch.json"
    if int(attempt) == 1 and not cleanup_only:
        if launch_file.exists():
            raise RuntimeError("deployment already has an intent; recover the original execution")
        inputs = resolve_inputs(environment, github or github_from_environment(environment))
        settings, configuration = inputs["settings"], inputs["configuration"]
        minutes = configuration["limits"]["timeoutMinutes"]
        if type(minutes) is not int or not 1 <= minutes <= 120:
            raise RuntimeError("runtime execution deadline is invalid")
        settings["allocation"] = allocation(environment)
        deployment_input_digest = digest({"settings": settings, "host": host["hostId"], "daemon": host["daemon"],
                                          "controller": {key: host[key] for key in ["iiOsRepository", "iiOsCommit", "runtimeRevision", "codexVersion"]}})
        deployment = {"owner": owner, "purpose": "work-ticket", "inputDigest": deployment_input_digest,
                      "timeoutSeconds": minutes * 60 + 600}
        durable(launch_file, {"schemaVersion": 1, "settings": settings, "deployment": deployment,
                              "promptBase64": inputs["promptBase64"]})
    launch = private_json(launch_file)
    settings, deployment = launch["settings"], launch["deployment"]
    identity = settings["identity"]
    if identity["repositoryId"] != int(repository_id) or identity["runId"] != int(run_id) or identity["dispatchId"] != environment["DISPATCH_ID"] \
            or settings["permissionDigest"] != environment["PERMISSION_DIGEST"] or settings["sourceRevision"] != environment["TRUSTED_SOURCE_SHA"]:
        raise RuntimeError("recovery does not identify the original approved execution")
    settings = copy.deepcopy(settings)
    settings["identity"]["runAttempt"] = int(attempt)
    mode = "execute" if int(attempt) == 1 and not cleanup_only else "recover"
    github_output(environment, "runtime_requested", "true")
    observer = next_observer(state, workflow_attempt=attempt, mode=mode, deployment=deployment)
    settings["oidc"] = {"audience": environment["OIDC_AUDIENCE"], "tokenUrl": environment["ACTIONS_ID_TOKEN_REQUEST_URL"],
                        "requestToken": environment["ACTIONS_ID_TOKEN_REQUEST_TOKEN"]}
    # The handoff is the job's inode-bound stage on this same host. Only its
    # location and digests travel in the envelope; values stay in 0600 files.
    handoff = staged_handoff(environment)
    if handoff["digests"].get("ticket-prompt.json") != settings["authorization"]["ticketPromptDigest"]:
        raise RuntimeError("credential handoff contains another approved prompt")
    request = {**deployment, "operation": mode, "attempt": observer, "admissionDirectory": str(private_directory(root / "admission")),
               "envelope": {"settings": settings, "handoff": handoff}}
    receipt = controller_factory(host, state, scripts=SCRIPTS).run(request, entry="runtime_ticket_controller.mjs")
    durable(state / ("controller-observer-" + str(observer) + ".json"), receipt)
    execution = receipt.get("outcome", {}).get("execution", {}).get("outcome", {})
    if receipt.get("controllerAbsent") is not True or receipt.get("outcome", {}).get("credentialCleanupConfirmed") is not True or execution.get("cleanupConfirmed") is not True:
        raise RuntimeError("runtime cleanup is unconfirmed; the original execution stays reserved")
    if cleanup_only:
        return cleanup_observation(execution, settings=settings, state=state, observer=observer, owner=owner,
            controller=receipt, deployment=deployment, environment=environment)
    if execution.get("status") == "never-acquired":
        return never_acquired_delivery(execution, settings=settings, state=state, attempt=attempt, owner=owner,
            controller=receipt, deployment=deployment, environment=environment)
    if execution.get("usage", {}).get("reported") is not True:
        # Usage delivery is application recovery. Retain the original history
        # and block publication and finalization until a rerun recovers it.
        github_output(environment, "runtime_cleanup_proven", "true")
        github_output(environment, "runtime_usage_proven", "false")
        raise UsageDeliveryPending("usage delivery is unconfirmed")
    collection = execution.get("result")
    artifacts = {}
    artifact_root = private_directory(root / "artifacts")
    expected = {"dispatch_id": identity["dispatchId"], "repository": identity["repository"], "repository_id": identity["repositoryId"],
                "issue_number": identity["issueNumber"], "project_item_id": identity["projectItemId"]}
    result = None
    if collection is not None:
        scope = hashlib.sha256(identity["dispatchId"].encode()).hexdigest()[:32]
        artifacts["result"] = retain_artifact(state, collection["resultArtifact"], "artifacts/ii-os-agent-result.json", artifact_root, scope, owner)
        result = verified_agent_result_artifact(artifacts["result"], artifact_root, expected)
        if result != collection["result"]:
            raise RuntimeError("runtime collection and result artifact disagree")
        bundle = collection.get("bundle")
        if (result["pull_request"] is None) != (bundle is None):
            raise RuntimeError("runtime result and bundle intent disagree")
        if bundle:
            artifacts["bundle"] = retain_artifact(state, bundle, "artifacts/ii-os-agent-change.bundle", artifact_root, scope, owner)
    if result is not None and result.get("pull_request") is not None and execution.get("status") not in {"completed", "recovered-cleanup"}:
        # Preserve the collection for diagnosis; a failed execution cannot
        # authorize publication merely because it exported a bundle.
        result = None
    delivery = {"schemaVersion": 1, "owner": owner, "cleanupConfirmed": True, "controller": receipt,
                "artifacts": artifacts, "result": result, "artifactRoot": str(artifact_root)}
    durable(state / ("delivery-observer-" + attempt + ".json"), delivery)
    github_output(environment, "runtime_cleanup_proven", "true")
    github_output(environment, "runtime_usage_proven", "true")
    github_output(environment, "agent_artifact_root", delivery["artifactRoot"])
    if result is not None:
        github_output(environment, "agent_result_b64", encode(result))
    if result is not None and artifacts.get("bundle"):
        github_output(environment, "agent_bundle_artifact_b64", encode(artifacts["bundle"]))
    if result is None:
        github_output(environment, "retry_failure_code", "agent_result_missing")
        github_output(environment, "retry_failure_detail", "The original runtime was cleaned without an eligible bounded result. Its execution history is retained.")
    github_output(environment, "runtime_delivery_owner", owner)
    return delivery


def check_approved_engine(environment, repository_root):
    """Refuse, before the approval is consumed, a profile this kit cannot run.

    The checkout is the trusted source commit, so the approved profile is read
    locally and bound to the approval by its digest.
    """
    profile_id = environment.get("PERMISSION_PROFILE", "")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", profile_id):
        raise HostBindingError("the approved permission profile name is invalid")
    path = Path(repository_root) / ".ii-os" / "agent-permissions" / (profile_id + ".json")
    try:
        profile = json.loads(path.read_text())
    except (OSError, ValueError):
        raise HostBindingError("the approved permission profile is not installed at the trusted source commit") from None
    if not isinstance(profile, dict) or canonical_profile_digest(profile) != environment.get("PERMISSION_DIGEST"):
        raise HostBindingError("the approved permission profile changed after approval")
    engine = profile.get("engine")
    if engine != "codex" or profile.get("schema_version") != 4:
        raise HostBindingError(f"the approved profile selects the {engine} engine; this kit has no executor for it (only codex with schema 4 runtime profiles)")


def restore_recovery_handoff(environment, *, root):
    ids = [environment.get(key, "") for key in ["GITHUB_REPOSITORY_ID", "GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT"]]
    if any(not re.fullmatch(r"[1-9][0-9]{0,15}", value) for value in ids) or int(ids[2]) < 2:
        raise RuntimeError("cleanup observer identity is invalid")
    owner = owner_for({"repositoryId": ids[0], "runId": ids[1]}, "work-ticket")
    launch = private_json(execution_state(root, owner) / "launch.json")
    settings = launch["settings"]
    identity = settings["identity"]
    if identity["repositoryId"] != int(ids[0]) or identity["runId"] != int(ids[1]) or identity["dispatchId"] != environment["DISPATCH_ID"] \
            or settings["permissionDigest"] != environment["PERMISSION_DIGEST"] or settings["sourceRevision"] != environment["TRUSTED_SOURCE_SHA"]:
        raise RuntimeError("cleanup observer changed the original approval")
    prompt = launch["promptBase64"]
    prompt_digest = settings["authorization"]["ticketPromptDigest"]
    if hashlib.sha256(base64.b64decode(prompt, validate=True)).hexdigest() != prompt_digest:
        raise RuntimeError("original approved prompt changed")
    # Recovery never resolves or uses the OAuth binding, so the repository
    # secret may have rotated meanwhile; the staged handoff still verifies
    # every byte it delivers and no model launch is possible.
    oauth_digest = hashlib.sha256(environment["CODEX_AUTH_JSON"].encode()).hexdigest()
    with open(environment["GITHUB_ENV"], "a", encoding="utf-8") as output:
        output.write("IIAUTO_TICKET_PROMPT_B64=" + prompt + "\n")
        output.write("IIAUTO_TICKET_PROMPT_SHA256=" + prompt_digest + "\n")
        output.write("CODEX_SECRET_DIGEST=" + oauth_digest + "\n")
        output.write("IIAUTO_APPROVAL_CONSUMED=1\n")


def main():
    os.umask(0o077)
    environment = dict(os.environ)
    arguments = sys.argv[1:]
    if arguments not in ([], ["cleanup"], ["preflight"], ["restore"]):
        raise SystemExit("expected preflight, restore, cleanup, or no argument")
    try:
        root = state_root(environment)
        if arguments == ["restore"]:
            restore_recovery_handoff(environment, root=root)
            return
        if arguments == ["preflight"] and environment.get("PERMISSION_PROFILE"):
            check_approved_engine(environment, REPOSITORY_ROOT)
        host = load_host(environment, REPOSITORY_ROOT)
        if arguments == ["preflight"]:
            print(json.dumps({"ready": True, "hostId": host["hostId"], "iiOsCommit": host["iiOsCommit"],
                              "runtimeRevision": host["runtimeRevision"]}, sort_keys=True))
            return
    except RuntimeError as error:
        # Host binding errors are written for the operator and carry no secret.
        raise SystemExit("ii-os agent host: " + str(error)) from None
    try:
        coordinate(environment, root=root, host=host, cleanup_only=arguments == ["cleanup"])
    except UsageDeliveryPending:
        github_output(environment, "retry_failure_code", "agent_usage_reporting_unconfirmed")
        github_output(environment, "retry_failure_detail", "Execution cleanup is confirmed. Rerun this workflow to recover usage delivery for the original run.")
        raise SystemExit("Usage delivery requires recovery; execution cleanup is confirmed.") from None
    except Exception:
        # Neither provider exception bodies nor secret-bearing settings escape.
        github_output(environment, "retry_failure_code", "agent_runtime_execution_unconfirmed")
        github_output(environment, "retry_failure_detail", "Runtime execution or cleanup is not yet confirmed; the original execution remains reserved for recovery.")
        raise SystemExit("Agent runtime execution requires recovery.") from None


if __name__ == "__main__":
    main()
