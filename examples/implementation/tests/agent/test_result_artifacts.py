"""Collected agent result artifacts and consumer receipts."""

import base64
import hashlib
import json
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

import agent_artifact_receipts as RECEIPTS  # noqa: E402
import agent_task_result as RESULT  # noqa: E402

DISPATCH = "dispatch:item"
SCOPE = hashlib.sha256(DISPATCH.encode()).hexdigest()[:32]
HEAD = "ii-os-agent/" + SCOPE
EXPECTED = {
    "dispatch_id": DISPATCH,
    "repository": "acme-co/example-app",
    "repository_id": 123,
    "issue_number": 1,
    "project_item_id": "item",
}
BUNDLE_PATH = "artifacts/ii-os-agent-change.bundle"


def _ready_result():
    return {
        **EXPECTED,
        "outcome": "ready_for_qa",
        "status": "ready_for_qa",
        "comments": ["Exact QA evidence."],
        "automation_failure": None,
        "pull_request": {
            "repository": "acme-co/example-app",
            "repository_id": 123,
            "head": HEAD,
            "base": "dev",
            "head_sha": "1" * 40,
            "base_sha": "2" * 40,
            "expected_old_head_sha": None,
        },
    }


class _Collected:
    """A private artifact root holding one collected run's result."""

    def __init__(self, root: Path, runtime="runtime-a"):
        self.root = root
        self.storage_path = f"ii-os-agent/{SCOPE}/{runtime}/{RESULT.RESULT_PATH}"
        self.path = root / self.storage_path
        self.path.parent.mkdir(parents=True, mode=0o700)

    def write(self, value):
        encoded = value if isinstance(value, bytes) else json.dumps(
            value, separators=(",", ":")
        ).encode()
        self.path.write_bytes(encoded)
        return {
            "path": RESULT.RESULT_PATH,
            "storage_path": self.storage_path,
            "size_bytes": len(encoded),
            "sha256": hashlib.sha256(encoded).hexdigest(),
            "content_type": "application/json",
        }


class AgentResultArtifactTest(unittest.TestCase):
    def test_result_requires_exact_digest_and_dispatch(self):
        with tempfile.TemporaryDirectory() as value:
            collected = _Collected(Path(value))
            descriptor = collected.write(_ready_result())
            self.assertEqual(
                RESULT.verified_agent_result_artifact(
                    descriptor, value, EXPECTED
                ),
                _ready_result(),
            )
            with self.assertRaises(RuntimeError):
                RESULT.verified_agent_result_artifact(
                    descriptor, value, {**EXPECTED, "dispatch_id": "other:item"}
                )
            with self.assertRaisesRegex(RuntimeError, "another artifact"):
                RESULT.verified_agent_result_artifact(
                    {**descriptor, "path": BUNDLE_PATH}, value, EXPECTED
                )
            with self.assertRaisesRegex(RuntimeError, "digest is invalid"):
                RESULT.verified_agent_result_artifact(
                    {**descriptor, "sha256": "0" * 64}, value, EXPECTED
                )

    def test_descriptor_and_storage_locator_are_closed(self):
        with tempfile.TemporaryDirectory() as value:
            collected = _Collected(Path(value))
            descriptor = collected.write(_ready_result())
            invalid = [
                {**descriptor, "path": "../result.json"},
                {**descriptor, "uri": collected.path.as_uri()},
                {**descriptor, "size_bytes": True},
                {**descriptor, "storage_path": (
                    f"ii-os-agent/{SCOPE}/../{RESULT.RESULT_PATH}"
                )},
                {**descriptor, "storage_path": (
                    f"ii-os-agent/{'0' * 32}/runtime-a/{RESULT.RESULT_PATH}"
                )},
                {**descriptor, "storage_path": (
                    f"ii-os-agent/{SCOPE}/{RESULT.RESULT_PATH}"
                )},
                {**descriptor, "storage_path": (
                    f"other-root/{SCOPE}/runtime-a/{RESULT.RESULT_PATH}"
                )},
            ]
            for candidate in invalid:
                with self.subTest(candidate=candidate):
                    with self.assertRaises(RuntimeError):
                        RESULT.read_verified_artifact(
                            value,
                            candidate,
                            scope=SCOPE,
                            maximum=32768,
                            label="agent result",
                        )
            with self.assertRaises(RuntimeError):
                RESULT.read_verified_artifact(
                    value, descriptor, scope="short",
                    maximum=32768, label="agent result",
                )

    def test_read_refuses_group_writable_or_oversized_files(self):
        with tempfile.TemporaryDirectory() as value:
            collected = _Collected(Path(value))
            descriptor = collected.write(_ready_result())
            with self.assertRaisesRegex(RuntimeError, "bounded owned regular"):
                RESULT.read_verified_artifact(
                    value, descriptor, scope=SCOPE, maximum=8,
                    label="agent result",
                )
            collected.path.parent.chmod(0o770)
            with self.assertRaisesRegex(RuntimeError, "privately controlled"):
                RESULT.read_verified_artifact(
                    value, descriptor, scope=SCOPE, maximum=32768,
                    label="agent result",
                )

    def test_result_rejects_type_confusion_and_inconsistent_status(self):
        with tempfile.TemporaryDirectory() as value:
            collected = _Collected(Path(value))
            for change in (
                {"issue_number": True},
                {"repository_id": True},
                {"outcome": "not_ready", "status": "done",
                 "pull_request": None, "comments": []},
                {"outcome": "ready_for_qa", "status": "ready_for_qa",
                 "pull_request": None},
                {"comments": ["x" * 8001]},
                {"comments": [" padded "]},
                {"unreviewed": True},
                {"automation_failure": {"code": "x", "detail": "y"}},
            ):
                with self.subTest(change=change):
                    descriptor = collected.write({**_ready_result(), **change})
                    with self.assertRaises(RuntimeError):
                        RESULT.verified_agent_result_artifact(
                            descriptor, value, EXPECTED
                        )

    def test_not_ready_todo_may_carry_one_bounded_failure(self):
        with tempfile.TemporaryDirectory() as value:
            collected = _Collected(Path(value))
            result = {
                **_ready_result(),
                "outcome": "not_ready",
                "status": "todo",
                "comments": [],
                "pull_request": None,
                "automation_failure": {
                    "code": "agent_result_missing",
                    "detail": "The run ended without a result.",
                },
            }
            descriptor = collected.write(result)
            self.assertEqual(
                RESULT.verified_agent_result_artifact(
                    descriptor, value, EXPECTED
                ),
                result,
            )

    def test_pull_request_intent_is_bound_to_the_dispatch_branch(self):
        valid = _ready_result()["pull_request"]
        self.assertTrue(RESULT._valid_pull_request(valid, DISPATCH))
        self.assertTrue(RESULT._valid_pull_request(None, DISPATCH))
        for value in (
            {**valid, "head": "ii-os-agent/" + "0" * 32},
            {**valid, "base": "main"},
            {**valid, "title": "untrusted"},
            {**valid, "repository": "not-a-repository"},
            {**valid, "repository_id": 0},
            {**valid, "head_sha": "Z" * 40},
            {**valid, "expected_old_head_sha": "short"},
            "dev",
        ):
            with self.subTest(value=value):
                self.assertFalse(RESULT._valid_pull_request(value, DISPATCH))


def _encode(value):
    return base64.b64encode(
        json.dumps(value, separators=(",", ":")).encode()
    ).decode()


class ConsumptionReceiptTest(unittest.TestCase):
    def setUp(self):
        self.finalization = {
            "schema_version": 1,
            "finalized": True,
            "workspace_id": "workspace-1",
            "project_item_id": "item-1",
            "dispatch_id": "dispatch:receipt",
            "repository": "acme-co/example-app",
            "repository_id": 123,
            "issue_number": 17,
            "run_id": 808,
            "run_attempt": 1,
            "result_digest": "d" * 64,
        }
        self.bundle = {
            "path": BUNDLE_PATH,
            "storage_path": f"ii-os-agent/{'a' * 32}/runtime/{BUNDLE_PATH}",
            "size_bytes": 10,
            "sha256": "e" * 64,
            "content_type": "application/octet-stream",
        }
        self.publication = {
            "schema_version": 1,
            "disposition": "published",
            "dispatch_id": "dispatch:receipt",
            "repository": "acme-co/example-ui",
            "repository_id": 456,
            "head": "ii-os-agent/" + "f" * 32,
            "head_sha": "1" * 40,
            "base": "dev",
            "base_sha": "2" * 40,
            "bundle_sha256": "e" * 64,
        }
        self.arguments = {
            "workspace_id": "workspace-1",
            "project_item_id": "item-1",
            "dispatch_id": "dispatch:receipt",
            "repository": "acme-co/example-app",
            "repository_id": 123,
            "publication_repository": "acme-co/example-ui",
            "publication_repository_id": 456,
            "issue_number": 17,
            "run_id": 808,
            "run_attempt": 1,
        }

    def test_requires_exact_consumer_receipts(self):
        RECEIPTS.validate_consumption_receipts(
            _encode(self.finalization),
            _encode(self.publication),
            _encode(self.bundle),
            [self.bundle],
            **self.arguments,
        )
        RECEIPTS.validate_consumption_receipts(
            _encode(self.finalization), "", "", [], **self.arguments
        )
        refused = [
            (_encode(self.finalization), "", _encode(self.bundle),
             [self.bundle]),
            (_encode(self.finalization),
             _encode({**self.publication, "repository_id": 999}),
             _encode(self.bundle), [self.bundle]),
            (_encode(self.finalization), "", "", [self.bundle]),
            (_encode(self.finalization), _encode(self.publication), "", []),
            (_encode({**self.finalization, "finalized": False}), "", "", []),
            (_encode({**self.finalization, "run_attempt": 2}), "", "", []),
            ("", "", "", []),
            ("not-base64", "", "", []),
            (_encode(self.finalization),
             _encode({**self.publication, "bundle_sha256": "0" * 64}),
             _encode(self.bundle), [self.bundle]),
            (_encode(self.finalization), "", "",
             [{**self.bundle, "path": "artifacts/other.bin"}]),
        ]
        for finalization, publication, bundle, cleanup in refused:
            with self.subTest(publication=publication, cleanup=cleanup):
                with self.assertRaises(RuntimeError):
                    RECEIPTS.validate_consumption_receipts(
                        finalization, publication, bundle, cleanup,
                        **self.arguments,
                    )

    def test_publication_defaults_to_the_ticket_repository(self):
        arguments = dict(self.arguments)
        del arguments["publication_repository"]
        del arguments["publication_repository_id"]
        publication = {
            **self.publication,
            "repository": "acme-co/example-app",
            "repository_id": 123,
        }
        RECEIPTS.validate_consumption_receipts(
            _encode(self.finalization),
            _encode(publication),
            _encode(self.bundle),
            [self.bundle],
            **arguments,
        )

    def test_artifact_descriptor_allows_only_result_and_bundle(self):
        RECEIPTS.validate_artifact_descriptor(self.bundle)
        for change in (
            {"path": "artifacts/secret.txt"},
            {"size_bytes": -1},
            {"size_bytes": True},
            {"sha256": "E" * 64},
            {"content_type": ""},
            {"extra": 1},
        ):
            with self.subTest(change=change):
                with self.assertRaises(RuntimeError):
                    RECEIPTS.validate_artifact_descriptor(
                        {**self.bundle, **change}
                    )


if __name__ == "__main__":
    unittest.main()
