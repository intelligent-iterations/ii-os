import hashlib
import os
import tempfile
import unittest
import zipfile
from pathlib import Path

import application_artifact_archive as archive


class ApplicationArtifactArchiveTest(unittest.TestCase):
    def test_archive_is_deterministic_and_preserves_safe_links(self) -> None:
        with tempfile.TemporaryDirectory(prefix="ii-app-archive-test-") as owned:
            root = Path(owned) / "Example.app"
            binary = root / "Contents" / "MacOS" / "example"
            binary.parent.mkdir(parents=True)
            binary.write_bytes(b"application")
            binary.chmod(0o755)
            link = root / "Contents" / "current"
            link.symlink_to("MacOS/example")
            first = Path(owned) / "first.zip"
            second = Path(owned) / "second.zip"

            archive.archive_artifact(str(root), first)
            archive.archive_artifact(str(root), second)

            self.assertEqual(
                hashlib.sha256(first.read_bytes()).digest(),
                hashlib.sha256(second.read_bytes()).digest(),
            )
            with zipfile.ZipFile(first) as value:
                self.assertEqual(
                    value.read("Example.app/Contents/current"), b"MacOS/example"
                )
                mode = value.getinfo(
                    "Example.app/Contents/MacOS/example"
                ).external_attr >> 16
                self.assertTrue(mode & 0o100)

    def test_link_escape_and_existing_output_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory(prefix="ii-app-archive-test-") as owned:
            root = Path(owned) / "bundle"
            root.mkdir()
            (root / "outside").symlink_to("../outside")
            destination = Path(owned) / "artifact.zip"
            with self.assertRaisesRegex(RuntimeError, "unsafe link|broken link|escapes"):
                archive.archive_artifact(str(root), destination)

            os.unlink(root / "outside")
            (root / "application").write_bytes(b"app")
            destination.write_bytes(b"existing")
            with self.assertRaisesRegex(RuntimeError, "must be new"):
                archive.archive_artifact(str(root), destination)


if __name__ == "__main__":
    unittest.main()
