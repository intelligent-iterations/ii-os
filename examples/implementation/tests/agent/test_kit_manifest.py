"""The generated reviewed-source values are valid for ii-os and the installer.

The manifest is deployment-owned: each adopter generates it from their own
copy, commits it, and passes it to ii-os. The kit ships the generator only.
"""

import json
from pathlib import Path
import sys
import unittest

KIT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(KIT / "scripts"))
sys.path.insert(0, str(KIT / "scripts" / "agent"))
sys.dont_write_bytecode = True

import agent_kit_manifest  # noqa: E402
import agent_permission_install  # noqa: E402


class KitManifestTest(unittest.TestCase):
    def test_generated_manifest_is_accepted_by_the_permission_installer(self):
        manifest = agent_kit_manifest.trusted_sources(KIT)
        agent_permission_install.validate_trusted_source_manifest(manifest)
        for path in [f".github/workflows/{name}" for name in agent_kit_manifest.WORKFLOWS]:
            self.assertIn(path, manifest["blob_shas"])
        for path in manifest["blob_shas"]:
            self.assertTrue((KIT / path).is_file(), path)
        self.assertEqual(manifest["python_import_namespaces"]["scripts/agent/providers"],
                         sorted(path.name for path in (KIT / "scripts/agent/providers").glob("*.py")))

    def test_the_kit_ships_no_reviewed_blob_identities(self):
        self.assertFalse((KIT / agent_kit_manifest.MANIFEST).exists())

    def test_profile_examples_reference_the_current_runtime_files(self):
        for profile_id, expected in agent_kit_manifest.profile_examples(KIT).items():
            committed = json.loads((KIT / "docs" / "agent-permission-examples" / f"{profile_id}.json").read_text())
            self.assertEqual(committed, expected, "run: python3 scripts/agent_kit_manifest.py profile-examples --write")


if __name__ == "__main__":
    unittest.main()
