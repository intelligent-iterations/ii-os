from __future__ import annotations

import json
import shutil
import tempfile
import unittest
from contextlib import contextmanager
from pathlib import Path

from application_artifact_manifest import build_manifest


@contextmanager
def owned_workspace():
    root = Path(tempfile.mkdtemp(prefix="ii_ffmpeg_manifest_test_"))
    marker = root / ".ii-disposable-owner"
    token = f"application-artifact-manifest-test:{root}"
    marker.write_text(token, encoding="utf-8")
    try:
        yield root
    finally:
        if marker.is_file() and not marker.is_symlink() and marker.read_text() == token:
            shutil.rmtree(root)


class ApplicationArtifactManifestTest(unittest.TestCase):
    def test_hashes_real_directory_bytes(self) -> None:
        with owned_workspace() as root:
            artifact = root / "application"
            artifact.mkdir()
            (artifact / "first.bin").write_bytes(b"first")
            (artifact / "second.bin").write_bytes(b"second")
            manifest = build_manifest("test", str(artifact))
            self.assertEqual(manifest["file_count"], 2)
            self.assertEqual(
                [item["path"] for item in manifest["files"]],
                ["first.bin", "second.bin"],
            )
            json.dumps(manifest)

    def test_records_safe_in_bundle_link_topology(self) -> None:
        with owned_workspace() as root:
            artifact = root / "application"
            artifact.mkdir()
            versions = artifact / "Versions"
            versions.mkdir()
            (versions / "A").write_bytes(b"framework")
            (artifact / "Current").symlink_to("Versions/A")
            manifest = build_manifest("test", str(artifact))
            link = next(item for item in manifest["files"] if item["path"] == "Current")
            self.assertEqual(link["type"], "symlink")
            self.assertEqual(link["target"], "Versions/A")

    def test_rejects_link_that_escapes_bundle(self) -> None:
        with owned_workspace() as root:
            artifact = root / "application"
            artifact.mkdir()
            outside = root / "outside"
            outside.write_bytes(b"outside")
            (artifact / "linked").symlink_to("../outside")
            with self.assertRaisesRegex(RuntimeError, "escapes"):
                build_manifest("test", str(artifact))


if __name__ == "__main__":
    unittest.main()
