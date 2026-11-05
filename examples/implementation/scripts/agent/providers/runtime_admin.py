"""Run the authorized Connect Codex, credential verification and permission
installer clients in a trusted controller on the bound host.

The ii-os session broker (or the two-person permission approval) has already
authorized the job. This adapter owns only the durable deployment intent, the
job-scoped secret handoff on stdin, and cleanup confirmation.
"""

import base64
import copy
import hashlib
import json
import os
from pathlib import Path
import re
import sys

from .host import (MAX_OUTPUT, LocalController, digest, durable, execution_state, load_host, owner_for,
                   private_directory, private_json, state_root)
from .runtime_ticket import github_output
from .runtime_ticket_inputs import allocation, connector_url


SCRIPTS = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
KINDS = {"codex-auth", "codex-auth-verify", "permission-installer"}
TIMEOUTS = {"codex-auth": 1800, "codex-auth-verify": 900, "permission-installer": 600}


def execution_binding(kind, host, worker):
    if (kind == "permission-installer") != (worker is None):
        raise RuntimeError("administrative runtime worker binding is invalid")
    return {"host": host["hostId"], "daemon": host["daemon"], "worker": worker,
            **{key: host[key] for key in ["iiOsRepository", "iiOsCommit", "runtimeRevision", "codexVersion"]}}


def controller_receipt(value, owner, kind):
    if not isinstance(value, dict) or value.get("schemaVersion") != 1 or value.get("owner") != owner or type(value.get("controllerAbsent")) is not bool or not isinstance(value.get("daemon"), str) or not value["daemon"]:
        raise RuntimeError("administrative controller receipt identifies another execution")
    outcome = value.get("outcome")
    if not isinstance(outcome, dict) or outcome.get("schemaVersion") != 1 or type(outcome.get("operationSucceeded")) is not bool:
        raise RuntimeError("administrative controller receipt is invalid")
    outputs = outcome.get("outputs")
    allowed = {"profile_b64", "proof_b64"} if kind == "permission-installer" else {"secret_digest"} if kind == "codex-auth-verify" else set()
    if not isinstance(outputs, dict) or not set(outputs) <= allowed or outcome["operationSucceeded"] and set(outputs) != allowed:
        raise RuntimeError("administrative runtime output is invalid")
    for item in outputs.values():
        if not isinstance(item, str):
            raise RuntimeError("administrative runtime output is invalid")
        if kind == "permission-installer":
            try:
                decoded = base64.b64decode(item, validate=True)
            except ValueError:
                raise RuntimeError("administrative runtime output is invalid") from None
            if len(decoded) > 1048576:
                raise RuntimeError("administrative runtime output is invalid")
        elif not re.fullmatch(r"[a-f0-9]{64}", item):
            raise RuntimeError("administrative runtime output is invalid")
    if len(json.dumps(value, separators=(",", ":")).encode()) > MAX_OUTPUT:
        raise RuntimeError("administrative controller receipt exceeded its bound")
    return outcome


def cleanup_confirmed(receipt, outcome):
    return receipt.get("controllerAbsent") is True and outcome.get("credentialCleanupConfirmed") is True \
        and outcome.get("execution", {}).get("outcome", {}).get("cleanupConfirmed") is True


def coordinate(environment, *, root, host, worker, controller_factory=LocalController, recover=False):
    kind = environment.get("II_OS_RUNTIME_KIND")
    if kind not in KINDS:
        raise RuntimeError("administrative runtime purpose is unsupported")
    binding = execution_binding(kind, host, worker)
    identity = {"repository": environment.get("GITHUB_REPOSITORY", "")}
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", identity["repository"]):
        raise RuntimeError("administrative runtime repository is invalid")
    if not recover and kind != "permission-installer" and environment.get("II_OS_CODEX_AUTH_REPOSITORY") != identity["repository"]:
        raise RuntimeError("authentication target differs from the workflow repository")
    for field, variable in {"repositoryId": "GITHUB_REPOSITORY_ID", "runId": "GITHUB_RUN_ID", "runAttempt": "GITHUB_RUN_ATTEMPT"}.items():
        value = environment.get(variable, "")
        if not re.fullmatch(r"[1-9][0-9]{0,15}", value) or int(value) > 9007199254740991:
            raise RuntimeError("administrative runtime workflow identity is invalid")
        identity[field] = int(value)
    if identity["runAttempt"] > 100:
        raise RuntimeError("administrative recovery exceeds its attempt ceiling")
    owner = owner_for(identity, kind)
    state = execution_state(root, owner)
    launch_file = state / "admin-launch.json"
    if recover:
        if not launch_file.exists():
            raise RuntimeError("original administrative runtime intent is unavailable")
        launch = private_json(launch_file)
        saved = launch["settings"]
        if launch.get("binding") != binding or any(saved["identity"].get(key) != identity[key] for key in ["repository", "repositoryId", "runId"]) or saved.get("kind") != kind or saved.get("authorized") is not True:
            raise RuntimeError("administrative recovery changed the original execution")
        expected_digest = digest({"settings": saved, "binding": binding})
        if launch["deployment"].get("owner") != owner or launch["deployment"].get("purpose") != kind or launch["deployment"].get("inputDigest") != expected_digest:
            raise RuntimeError("administrative recovery changed the original execution")
    else:
        if environment.get("II_OS_RUNTIME_AUTHORIZED") != "1" or identity["runAttempt"] != 1 or launch_file.exists():
            raise RuntimeError("an administrative launch requires the original broker-authorized job")
        session_id = environment.get("II_OS_CODEX_AUTH_SESSION_ID", "")
        if kind != "permission-installer" and not re.fullmatch(r"[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}", session_id):
            raise RuntimeError("administrative session identity is invalid")
        settings = {"kind": kind, "mode": "execute", "identity": identity, "authorized": True, "sessionId": session_id,
                    "implementationSha": environment.get("GITHUB_SHA", ""), "sourceSha": host["iiOsCommit"],
                    "connector": connector_url(environment)}
        if not re.fullmatch(r"[a-f0-9]{40}", settings["implementationSha"]):
            raise RuntimeError("administrative runtime source binding is invalid")
        if kind == "codex-auth":
            reauthenticate = environment.get("II_OS_CODEX_AUTH_REAUTHENTICATE", "false")
            if reauthenticate not in {"true", "false"}:
                raise RuntimeError("administrative reauthentication choice is invalid")
            settings["reauthenticate"] = reauthenticate == "true"
        if kind != "permission-installer":
            settings["allocation"] = allocation(environment)
            encoded = environment.get("CODEX_AUTH_JSON", "").encode()
            settings["credentialRotation"] = {"originalDigest": hashlib.sha256(encoded).hexdigest() if encoded else ""}
        if kind == "permission-installer":
            fields = ["APPROVAL_ID", "DISPATCH_ID", "DISPATCH_FENCE", "WORKSPACE_ID", "PROFILE_ID", "PROFILE_JSON", "PROFILE_VERSION", "PROFILE_DIGEST"]
            settings["installation"] = {name: environment[name] for name in fields}
        input_digest = digest({"settings": settings, "binding": binding})
        deployment = {"owner": owner, "purpose": kind, "inputDigest": input_digest, "timeoutSeconds": TIMEOUTS[kind]}
        durable(launch_file, {"schemaVersion": 1, "settings": settings, "deployment": deployment, "binding": binding})
        launch = private_json(launch_file)
    github_output(environment, "runtime_requested", "true")
    delivery_file = state / "admin-delivery.json"
    if delivery_file.exists():
        # An independent observer re-reads the original cleanup proof. It
        # never starts another client or receives credentials.
        receipt = private_json(delivery_file)
        outcome = controller_receipt(receipt.get("controller"), owner, kind)
        if receipt.get("owner") != owner or receipt.get("deploymentInputDigest") != launch["deployment"]["inputDigest"] or receipt.get("cleanupConfirmed") is not True or not cleanup_confirmed(receipt["controller"], outcome):
            raise RuntimeError("administrative cleanup receipt is unavailable")
        return {**receipt, "operationSucceeded": outcome["operationSucceeded"], "outputs": outcome["outputs"]}
    settings = copy.deepcopy(launch["settings"])
    settings["identity"]["runAttempt"] = identity["runAttempt"]
    settings["mode"] = "recover" if recover else "execute"
    if kind != "permission-installer":
        settings["deploymentInputDigest"] = launch["deployment"]["inputDigest"]
        settings["credentialRotationOidc"] = {"tokenUrl": environment["ACTIONS_ID_TOKEN_REQUEST_URL"], "requestToken": environment["ACTIONS_ID_TOKEN_REQUEST_TOKEN"]}
    if not recover:
        if kind != "permission-installer":
            settings["oidc"] = {"tokenUrl": environment["ACTIONS_ID_TOKEN_REQUEST_URL"], "requestToken": environment["ACTIONS_ID_TOKEN_REQUEST_TOKEN"]}
        if kind == "permission-installer":
            settings["secrets"] = {"GITHUB_SOURCE_READ_TOKEN": environment["GITHUB_SOURCE_READ_TOKEN"]}
        elif kind == "codex-auth-verify" or kind == "codex-auth" and not settings["reauthenticate"] and environment.get("CODEX_AUTH_JSON"):
            settings["secrets"] = {"CODEX_AUTH_JSON": environment["CODEX_AUTH_JSON"]}
        else:
            settings["secrets"] = {}
    observers = list(state.glob("admin-observer-*.json"))
    if len(observers) >= 100:
        raise RuntimeError("administrative cleanup exceeded its observer ceiling")
    attempt = max([private_json(path)["providerAttempt"] for path in observers] or [0]) + 1
    durable(state / ("admin-observer-" + str(attempt) + ".json"), {
        "providerAttempt": attempt, "workflowAttempt": identity["runAttempt"], "mode": settings["mode"]})
    request = {**launch["deployment"], "operation": settings["mode"], "attempt": attempt,
               "admissionDirectory": str(private_directory(root / "admission")), "envelope": {"settings": settings}}
    receipt = controller_factory(host, state, scripts=SCRIPTS).run(request, entry="runtime_admin_controller.mjs")
    outcome = controller_receipt(receipt, owner, kind)
    durable(state / ("admin-controller-" + str(attempt) + ".json"), receipt)
    if not cleanup_confirmed(receipt, outcome):
        raise RuntimeError("administrative runtime cleanup is unconfirmed")
    delivery = {"owner": owner, "deploymentInputDigest": launch["deployment"]["inputDigest"], "cleanupConfirmed": True, "controller": receipt}
    if len(json.dumps(delivery, separators=(",", ":")).encode()) > MAX_OUTPUT:
        raise RuntimeError("administrative delivery receipt exceeded its bound")
    durable(delivery_file, delivery)
    return {**delivery, "operationSucceeded": outcome["operationSucceeded"], "outputs": outcome["outputs"]}


def verification_worker():
    configuration = json.loads((REPOSITORY_ROOT / ".ii-os" / "runtimes" / "codex-verification.json").read_text())["environment"]
    return {key: configuration[key] for key in ["cpu", "memoryMiB", "diskGiB"]}


def main():
    if sys.argv[1:] not in ([], ["recover"]):
        raise SystemExit("expected recover or no argument")
    os.umask(0o077)
    environment = dict(os.environ)
    try:
        root = state_root(environment)
        host = load_host(environment, REPOSITORY_ROOT)
    except RuntimeError as error:
        raise SystemExit("ii-os agent host: " + str(error)) from None
    worker = None if environment.get("II_OS_RUNTIME_KIND") == "permission-installer" else verification_worker()
    try:
        recovering = sys.argv[1:] == ["recover"]
        receipt = coordinate(environment, root=root, host=host, worker=worker,
                             recover=recovering or int(environment["GITHUB_RUN_ATTEMPT"]) > 1)
        github_output(environment, "runtime_cleanup_proven", "true")
        for key, value in receipt["outputs"].items():
            if environment["II_OS_RUNTIME_KIND"] == "permission-installer":
                if key not in {"profile_b64", "proof_b64"} or len(base64.b64decode(value, validate=True)) > 1048576:
                    raise RuntimeError("administrative runtime output is invalid")
            elif key != "secret_digest" or not re.fullmatch(r"[a-f0-9]{64}", value):
                raise RuntimeError("administrative runtime output is invalid")
            github_output(environment, key, value)
        if not recovering and not receipt["operationSucceeded"]:
            raise RuntimeError("the authentication or installation client did not complete")
        print(json.dumps({"cleanupConfirmed": True, "operationSucceeded": receipt["operationSucceeded"]}))
    except Exception:
        raise SystemExit("Administrative runtime requires recovery; no credential values were logged.") from None


if __name__ == "__main__":
    main()
