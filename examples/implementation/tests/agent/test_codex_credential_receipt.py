import json
import os
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts" / "agent"))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from codex_test_support import REPOSITORY, owned_directory  # noqa: E402
import codex_credential_receipt as MODULE  # noqa: E402


class CredentialReceiptTest(unittest.TestCase):
    def journal(self, root):
        directory = root / "state" / "credential-rotation"
        directory.mkdir(mode=0o700, parents=True)
        (root / "state").chmod(0o700)
        path = directory / "journal.json"
        value = {"schemaVersion": 1, "phase": "committed", "owner": {
            "kind": "codex-auth-verify", "repository": REPOSITORY,
            "repositoryId": 42, "runId": 100, "runAttempt": 1,
        }, "originalDigest": "a" * 64, "candidateDigest": "b" * 64,
                 "commit": {"committed": True, "secretDigest": "b" * 64,
                            "secretUpdatedAt": "2026-10-30T20:00:00Z", "generation": 1, "changed": True}}
        path.write_text(json.dumps(value))
        path.chmod(0o600)
        return path, value

    def read(self, root, **options):
        with mock.patch.dict(os.environ, {
            "II_OS_CONTROLLER_STATE_DIR": options.get("state", str(root / "state")),
            "GITHUB_REPOSITORY": REPOSITORY, "GITHUB_REPOSITORY_ID": "42", "GITHUB_RUN_ID": "100",
        }, clear=True):
            return MODULE.committed_credential("codex-auth-verify", original_digest=options.get("original", "a" * 64))

    def test_returns_only_committed_run_metadata(self):
        with owned_directory() as root:
            self.journal(root)
            self.assertEqual(self.read(root), {
                "secretDigest": "b" * 64, "secretUpdatedAt": "2026-10-30T20:00:00Z",
                "generation": 1, "changed": True,
            })

    def test_receipt_location_comes_from_the_controller_state_directory(self):
        with owned_directory() as root:
            self.journal(root)
            for state in ("", "state", str(root / "elsewhere"), str(root / "state") + "/../state"):
                with self.subTest(state=state):
                    with self.assertRaises(MODULE.SessionFailure) as error:
                        self.read(root, state=state)
                    self.assertEqual(error.exception.code, "credential_refresh_unconfirmed")

    def test_foreign_or_incomplete_handoff_cannot_attest_the_saved_secret(self):
        for field, value in (("phase", "written"), ("owner.runId", 101),
                             ("owner.kind", "codex-auth"), ("candidateDigest", "c" * 64),
                             ("commit.committed", False), ("commit.generation", True),
                             ("commit.secretUpdatedAt", "not-a-version")):
            with self.subTest(field=field), owned_directory() as root:
                path, journal = self.journal(root)
                target, key = (journal, field) if "." not in field else (journal[field.split(".")[0]], field.split(".")[1])
                target[key] = value
                path.write_text(json.dumps(journal))
                with self.assertRaises(MODULE.SessionFailure):
                    self.read(root)

    def test_original_snapshot_must_match_even_when_new_digest_is_valid(self):
        with owned_directory() as root:
            self.journal(root)
            with self.assertRaises(MODULE.SessionFailure):
                self.read(root, original="c" * 64)

    def test_symlink_public_or_hardlinked_receipt_is_rejected(self):
        for fault in ("public", "symlink", "hardlink", "public-parent"):
            with self.subTest(fault=fault), owned_directory() as root:
                path, _ = self.journal(root)
                if fault == "public":
                    path.chmod(0o644)
                elif fault == "public-parent":
                    path.parent.chmod(0o755)
                elif fault == "hardlink":
                    os.link(path, path.with_name("other.json"))
                else:
                    path.rename(path.with_name("original.json"))
                    path.symlink_to("original.json")
                with self.assertRaises(MODULE.SessionFailure):
                    self.read(root)


if __name__ == "__main__":
    unittest.main()
