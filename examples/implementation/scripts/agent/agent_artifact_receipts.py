"""Validate exact consumer receipts before collected artifacts are removed.

The finalization receipt proves ii-os recorded the result; the publication
receipt proves the exact change bundle was pushed. Only then may the
retained result and bundle copies be deleted.
"""

import base64
import json
import re


_BUNDLE_PATH = "artifacts/ii-os-agent-change.bundle"
_ALLOWED_PATHS = {
    "artifacts/ii-os-agent-result.json",
    _BUNDLE_PATH,
}
_SHA = re.compile(r"^[0-9a-f]{40}$")
_DIGEST = re.compile(r"^[0-9a-f]{64}$")


def validate_artifact_descriptor(item):
    if (
        not isinstance(item, dict)
        or set(item)
        != {
            "path",
            "storage_path",
            "size_bytes",
            "sha256",
            "content_type",
        }
        or item.get("path") not in _ALLOWED_PATHS
        or type(item.get("size_bytes")) is not int
        or item["size_bytes"] < 0
        or item["size_bytes"] > (2 << 30)
        or not isinstance(item.get("sha256"), str)
        or not _DIGEST.fullmatch(item["sha256"])
        or not isinstance(item.get("content_type"), str)
        or not item["content_type"]
        or not isinstance(item.get("storage_path"), str)
    ):
        raise RuntimeError("artifact cleanup descriptor is invalid")


def validate_consumption_receipts(
    finalization_encoded,
    publication_encoded,
    bundle_encoded,
    cleanup_artifacts,
    *,
    workspace_id,
    project_item_id,
    dispatch_id,
    repository,
    repository_id,
    issue_number,
    run_id,
    run_attempt,
    publication_repository=None,
    publication_repository_id=None,
):
    publication_repository = publication_repository or repository
    publication_repository_id = publication_repository_id or repository_id
    finalization = _decode_receipt(
        finalization_encoded, "agent finalization receipt"
    )
    if (
        set(finalization)
        != {
            "schema_version",
            "finalized",
            "workspace_id",
            "project_item_id",
            "dispatch_id",
            "repository",
            "repository_id",
            "issue_number",
            "run_id",
            "run_attempt",
            "result_digest",
        }
        or finalization.get("schema_version") != 1
        or finalization.get("finalized") is not True
        or finalization.get("workspace_id") != workspace_id
        or finalization.get("project_item_id") != project_item_id
        or finalization.get("dispatch_id") != dispatch_id
        or finalization.get("repository") != repository
        or finalization.get("repository_id") != repository_id
        or finalization.get("issue_number") != issue_number
        or finalization.get("run_id") != run_id
        or finalization.get("run_attempt") != run_attempt
        or not isinstance(finalization.get("result_digest"), str)
        or not _DIGEST.fullmatch(finalization["result_digest"])
    ):
        raise RuntimeError("agent finalization receipt identity is invalid")
    if not isinstance(cleanup_artifacts, list) or len(cleanup_artifacts) > 2:
        raise RuntimeError("cleanup receipt artifacts are invalid")
    for descriptor in cleanup_artifacts:
        validate_artifact_descriptor(descriptor)
    if len({item["path"] for item in cleanup_artifacts}) != len(
        cleanup_artifacts
    ):
        raise RuntimeError("cleanup receipt artifacts are ambiguous")
    cleanup_bundles = [
        item for item in cleanup_artifacts if item["path"] == _BUNDLE_PATH
    ]
    if not bundle_encoded:
        if publication_encoded:
            raise RuntimeError("unexpected publication receipt without a bundle")
        if cleanup_bundles:
            raise RuntimeError(
                "cleanup cannot discard an unconsumed change bundle"
            )
        return
    bundle = _decode_receipt(bundle_encoded, "bundle descriptor")
    validate_artifact_descriptor(bundle)
    if bundle["path"] != _BUNDLE_PATH or cleanup_bundles != [bundle]:
        raise RuntimeError("bundle descriptor path is invalid")
    publication = _decode_receipt(
        publication_encoded, "agent publication receipt"
    )
    if (
        set(publication)
        != {
            "schema_version",
            "disposition",
            "dispatch_id",
            "repository",
            "repository_id",
            "head",
            "head_sha",
            "base",
            "base_sha",
            "bundle_sha256",
        }
        or publication.get("schema_version") != 1
        or publication.get("disposition") != "published"
        or publication.get("dispatch_id") != dispatch_id
        or publication.get("repository") != publication_repository
        or publication.get("repository_id") != publication_repository_id
        or publication.get("base") != "dev"
        or publication.get("bundle_sha256") != bundle["sha256"]
        or not isinstance(publication.get("head"), str)
        or not re.fullmatch(
            r"ii-os-agent/[0-9a-f]{32}", publication["head"]
        )
        or not isinstance(publication.get("head_sha"), str)
        or not _SHA.fullmatch(publication["head_sha"])
        or not isinstance(publication.get("base_sha"), str)
        or not _SHA.fullmatch(publication["base_sha"])
    ):
        raise RuntimeError("agent publication receipt identity is invalid")


def _decode_receipt(encoded, label):
    if not encoded:
        raise RuntimeError(f"{label} is required")
    try:
        value = json.loads(base64.b64decode(encoded, validate=True))
    except (ValueError, TypeError, json.JSONDecodeError) as error:
        raise RuntimeError(f"{label} is invalid") from error
    if not isinstance(value, dict):
        raise RuntimeError(f"{label} is invalid")
    return value
