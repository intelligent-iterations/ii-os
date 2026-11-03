import hashlib
import json
import os
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path


SCRIPT = (
    Path(__file__).parents[1]
    / "third_party/ffmpeg_kit_flutter_mobile_full/scripts/setup_ios.sh"
)
FRAMEWORKS = (
    "ffmpegkit",
    "libavcodec",
    "libavdevice",
    "libavfilter",
    "libavformat",
    "libavutil",
    "libswresample",
    "libswscale",
)


class IosLocalEngineSetupTest(unittest.TestCase):
    def setUp(self):
        self.owned = tempfile.TemporaryDirectory(prefix="ii-ios-engine-setup-test-")
        self.root = Path(self.owned.name)
        self.archives = self.root / "archives"
        self.archives.mkdir()
        artifacts = []
        for framework in FRAMEWORKS:
            archive = self.archives / f"{framework}.xcframework.zip"
            with zipfile.ZipFile(archive, "w") as output:
                output.writestr(
                    f"{framework}.xcframework/ios-arm64/"
                    f"{framework}.framework/{framework}",
                    framework,
                )
            artifacts.append(
                {
                    "path": archive.name,
                    "sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
                }
            )
        self.attestation = self.root / "attestation.json"
        self.attestation.write_text(
            json.dumps({"schema": 1, "platform": "ios", "artifacts": artifacts})
        )
        self.install = self.root / "install"
        self.install.mkdir()

    def tearDown(self):
        self.owned.cleanup()

    def _run(self):
        environment = {
            **os.environ,
            "II_FFMPEG_IOS_ARCHIVE_DIR": str(self.archives),
            "II_FFMPEG_IOS_ATTESTATION": str(self.attestation),
            "II_FFMPEG_REQUIRE_RELEASE_ENGINE": "true",
        }
        return subprocess.run(
            ["bash", str(SCRIPT)],
            cwd=self.install,
            env=environment,
            check=False,
            capture_output=True,
            text=True,
        )

    def test_installs_and_rechecks_exact_local_archives(self):
        first = self._run()
        self.assertEqual(first.returncode, 0, first.stderr)
        second = self._run()
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(
            {
                path.name
                for path in (self.install / "Frameworks").iterdir()
                if path.is_dir()
            },
            {f"{name}.xcframework" for name in FRAMEWORKS},
        )

    def test_rejects_archive_changed_after_attestation(self):
        target = self.archives / "libavutil.xcframework.zip"
        target.write_bytes(target.read_bytes() + b"tampered")
        result = self._run()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Checksum mismatch", result.stderr)

    def test_rejects_implicit_prebuilt_fallback(self):
        environment = {
            key: value
            for key, value in os.environ.items()
            if not key.startswith("II_FFMPEG_")
        }
        result = subprocess.run(
            ["bash", str(SCRIPT)],
            cwd=self.install,
            env=environment,
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("source-attested local iOS FFmpeg engine", result.stderr)

    def test_debug_fallback_is_explicit_and_incompatible_with_release_gate(self):
        environment = {
            **os.environ,
            "II_FFMPEG_ALLOW_DEBUG_FALLBACK": "true",
            "II_FFMPEG_REQUIRE_RELEASE_ENGINE": "true",
        }
        result = subprocess.run(
            ["bash", str(SCRIPT)],
            cwd=self.install,
            env=environment,
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("cannot be combined", result.stderr)


if __name__ == "__main__":
    unittest.main()
