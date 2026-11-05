"""Remove consumed delivery copies while retaining the original run history."""

from __future__ import annotations

import hashlib
import json
import os
import re
import stat
import sys

from agent_artifact_receipts import validate_consumption_receipts
from agent_task_result import read_verified_artifact
from .host import HostBindingError, durable, execution_state, private_json, state_root


AUTHORIZATION_FIELDS = {
    "GITHUB_REPOSITORY_ID", "GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT", "RUNTIME_DELIVERY_OWNER",
    "WORKSPACE_ID", "PROJECT_ITEM_ID", "DISPATCH_ID", "TARGET_REPOSITORY", "ISSUE_NUMBER",
    "AGENT_FINALIZATION_RECEIPT_B64", "AGENT_PUBLICATION_RECEIPT_B64", "AGENT_BUNDLE_ARTIFACT_B64",
    "AGENT_PUBLICATION_REPOSITORY", "AGENT_PUBLICATION_REPOSITORY_ID",
}


def cleanup(environment, *, root):
    owner = environment.get("RUNTIME_DELIVERY_OWNER", "")
    identity = [environment.get(key, "") for key in ["GITHUB_REPOSITORY_ID", "GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT"]]
    if not re.fullmatch(r"[a-f0-9]{64}", owner) or any(not re.fullmatch(r"[1-9][0-9]{0,15}", value) for value in identity):
        raise RuntimeError("runtime delivery ownership is invalid")
    expected = hashlib.sha256(("github:" + identity[0] + ":" + identity[1] + ":work-ticket").encode()).hexdigest()
    if owner != expected:
        raise RuntimeError("runtime delivery belongs to another workflow")
    state = execution_state(root, owner)
    delivery = private_json(state / ("delivery-observer-" + identity[2] + ".json"))
    artifact_root = root / "artifacts"
    if delivery.get("owner") != owner or delivery.get("cleanupConfirmed") is not True or delivery.get("artifactRoot") != str(artifact_root):
        raise RuntimeError("runtime delivery cleanup evidence is invalid")
    artifacts = list(delivery["artifacts"].values())
    validate_consumption_receipts(environment.get("AGENT_FINALIZATION_RECEIPT_B64", ""),
        environment.get("AGENT_PUBLICATION_RECEIPT_B64", ""), environment.get("AGENT_BUNDLE_ARTIFACT_B64", ""), artifacts,
        workspace_id=environment["WORKSPACE_ID"], project_item_id=environment["PROJECT_ITEM_ID"],
        dispatch_id=environment["DISPATCH_ID"], repository=environment["TARGET_REPOSITORY"],
        repository_id=int(identity[0]), issue_number=int(environment["ISSUE_NUMBER"]),
        run_id=int(identity[1]), run_attempt=int(identity[2]),
        publication_repository=environment.get("AGENT_PUBLICATION_REPOSITORY") or None,
        publication_repository_id=int(environment["AGENT_PUBLICATION_REPOSITORY_ID"]) if environment.get("AGENT_PUBLICATION_REPOSITORY_ID") else None)
    scope = hashlib.sha256(environment["DISPATCH_ID"].encode()).hexdigest()[:32]
    receipt = {"schemaVersion": 1, "owner": owner, "attempt": int(identity[2]), "artifacts": artifacts,
               "finalizationDigest": hashlib.sha256(environment["AGENT_FINALIZATION_RECEIPT_B64"].encode()).hexdigest(),
               "publicationDigest": hashlib.sha256(environment.get("AGENT_PUBLICATION_RECEIPT_B64", "").encode()).hexdigest(),
               "authorization": {field: environment.get(field, "") for field in AUTHORIZATION_FIELDS}}
    intent = state / ("consumption-" + identity[2] + ".json")
    resuming = intent.exists()
    durable(intent, receipt)
    # Verify every remaining file before removal. Recovery may accept an absent
    # file only after that exact intent was durably saved.
    for artifact in artifacts:
        parts = artifact["storage_path"].split("/")
        if len(parts) < 4 or parts[:3] != ["ii-os-agent", scope, owner[:32]]:
            raise RuntimeError("runtime artifact scope changed")
        path = artifact_root / artifact["storage_path"]
        if path.is_symlink():
            raise RuntimeError("runtime delivery was replaced by a symlink")
        if not path.exists() and resuming:
            continue
        read_verified_artifact(artifact_root, artifact, scope=scope, maximum=67108864, label="runtime delivery")
    for artifact in artifacts:
        path = artifact_root / artifact["storage_path"]
        if path.is_symlink():
            raise RuntimeError("runtime delivery was replaced by a symlink")
        if not path.exists():
            continue
        before = path.lstat()
        read_verified_artifact(artifact_root, artifact, scope=scope, maximum=67108864, label="runtime delivery")
        after = path.lstat()
        if not stat.S_ISREG(after.st_mode) or (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns) != (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns):
            raise RuntimeError("runtime delivery changed before removal")
        os.unlink(path)
        descriptor = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
    durable(state / ("consumed-" + identity[2] + ".json"), {**receipt, "confirmed": True})
    # The source configuration, input hashes, telemetry, original collection,
    # and recovery records remain in the private execution state.
    return {"confirmed": True, "owner": owner}


def recover(environment, *, root):
    values = [environment.get(key, "") for key in ["GITHUB_REPOSITORY_ID", "GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT"]]
    if any(not re.fullmatch(r"[1-9][0-9]{0,15}", value) for value in values) or int(values[2]) > 100:
        raise RuntimeError("runtime consumption recovery identity is invalid")
    owner = hashlib.sha256(("github:" + values[0] + ":" + values[1] + ":work-ticket").encode()).hexdigest()
    recovered = 0
    for attempt in range(1, int(values[2]) + 1):
        journal = root / "executions" / owner / ("consumption-" + str(attempt) + ".json")
        if not journal.exists():
            continue
        intent = private_json(journal)
        authorization = intent.get("authorization")
        if intent.get("owner") != owner or not isinstance(authorization, dict) or set(authorization) != AUTHORIZATION_FIELDS or any(
            authorization.get(key) != expected for key, expected in {
                "RUNTIME_DELIVERY_OWNER": owner, "GITHUB_REPOSITORY_ID": values[0], "GITHUB_RUN_ID": values[1], "GITHUB_RUN_ATTEMPT": str(attempt),
            }.items()
        ):
            raise RuntimeError("runtime consumption recovery changed ownership")
        cleanup(authorization, root=root)
        recovered += 1
    return {"confirmed": True, "alreadyConsumed": recovered > 0, "recovered": recovered}


def main():
    environment = dict(os.environ)
    try:
        root = state_root(environment)
    except HostBindingError as error:
        raise SystemExit("ii-os agent host: " + str(error)) from None
    if sys.argv[1:] == ["recover"]:
        print(json.dumps(recover(environment, root=root)))
    elif not sys.argv[1:]:
        cleanup(environment, root=root)
        print('{"confirmed":true,"scope":"local-delivery-copies"}')
    else:
        raise SystemExit("expected recover or no argument")


if __name__ == "__main__":
    main()
