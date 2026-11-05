"""Runtime (schema 4) agent permission profile validation."""

import hashlib
import json
import sys
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
KIT = Path(__file__).resolve().parents[2]
SCRIPTS = KIT / "scripts" / "agent"
for _path in (SCRIPTS / "worker", SCRIPTS):
    if str(_path) not in sys.path:
        sys.path.insert(0, str(_path))

import agent_task_profile as PROFILE  # noqa: E402


def runtime_profile():
    return {
        "schema_version": 4,
        "engine": "codex",
        "id": "repository-maintainer",
        "version": "2026-01-01.1",
        "display_name": "Repository maintainer",
        "description": "Maintains acme-co/example-app.",
        "allowed_actions": ["Edit code"],
        "denied_actions": ["Create tickets"],
        "repository_actions": {"mode": "pull_request"},
        "runtime": {
            "configuration": {
                "path": ".ii-os/runtimes/codex.json",
                "sha256": "a" * 64,
            },
            "execution_binding": {
                "path": ".ii-os/runtimes/docker.json",
                "sha256": "b" * 64,
            },
        },
        "workflow": {"file": "ii-os-agent-task.yml", "ref": "dev"},
    }


class RuntimeProfileTest(unittest.TestCase):
    def test_accepts_file_references_without_copying_runtime_policy(self):
        profile = runtime_profile()
        PROFILE.validate_executable_profile(profile)
        PROFILE.validate_executable_profile(
            profile, expected_id="repository-maintainer"
        )
        with self.assertRaises(SystemExit):
            PROFILE.validate_executable_profile(profile, expected_id="other")

    def test_rejects_unreviewed_or_shadow_runtime_policy(self):
        for mutate in (
            lambda p: p["runtime"]["configuration"].update(
                path="../other.json"
            ),
            lambda p: p["runtime"]["configuration"].update(
                path=".ii-os/runtimes/a//b.json"
            ),
            lambda p: p["runtime"]["configuration"].update(sha256="mutable"),
            lambda p: p["runtime"]["execution_binding"].update(
                path=".ii-os/runtimes/codex.json"
            ),
            lambda p: p["runtime"].update(image="unapproved-shadow-policy"),
            lambda p: p.update(unreviewed=True),
            lambda p: p.update(engine="another-engine"),
            lambda p: p.update(workflow={"file": "other.yml", "ref": "dev"}),
            lambda p: p.update(
                workflow={"file": "ii-os-agent-task.yml", "ref": "main"}
            ),
            lambda p: p.update(repository_actions={"mode": "admin"}),
            lambda p: p.update(allowed_actions=[]),
            lambda p: p.update(denied_actions=["dup", "dup"]),
            lambda p: p.update(display_name=" padded "),
            lambda p: p.update(description="x" * 1001),
        ):
            profile = runtime_profile()
            mutate(profile)
            with self.subTest(profile=profile):
                with self.assertRaises(SystemExit):
                    PROFILE.validate_executable_profile(profile)

    def test_rejects_json_type_confusion(self):
        for field, value in (
            ("schema_version", True),
            ("schema_version", 4.0),
            ("id", 1),
            ("version", 1),
            ("allowed_actions", "Edit code"),
        ):
            profile = runtime_profile()
            profile[field] = value
            with self.subTest(field=field):
                with self.assertRaises(SystemExit):
                    PROFILE.validate_executable_profile(profile)

    def test_only_runtime_profiles_are_executable(self):
        legacy = runtime_profile()
        legacy.pop("runtime")
        legacy.pop("engine")
        legacy["schema_version"] = 2
        legacy["secret_injection"] = {"environment": "x", "bindings": []}
        with self.assertRaises(SystemExit):
            PROFILE.validate_executable_profile(legacy)

    def test_canonical_digest_is_key_order_independent(self):
        profile = runtime_profile()
        reordered = json.loads(
            json.dumps(dict(reversed(list(profile.items()))))
        )
        self.assertEqual(
            PROFILE.canonical_profile_digest(profile),
            PROFILE.canonical_profile_digest(reordered),
        )
        self.assertEqual(
            PROFILE.canonical_profile_digest(profile),
            hashlib.sha256(
                json.dumps(
                    profile, sort_keys=True, separators=(",", ":"),
                    ensure_ascii=False,
                ).encode()
            ).hexdigest(),
        )
        profile["description"] = "Maintains acme-co/example-app -- gently."
        self.assertIn(
            "--".encode(),
            json.dumps(profile, ensure_ascii=False).encode(),
        )
        self.assertRegex(PROFILE.canonical_profile_digest(profile), "^[0-9a-f]{64}$")


if __name__ == "__main__":
    unittest.main()
