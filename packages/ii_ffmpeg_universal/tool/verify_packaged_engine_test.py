import json
import copy
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import verify_packaged_engine as verifier


class PackagedEngineBoundaryTest(unittest.TestCase):
    def setUp(self):
        self.owned = tempfile.TemporaryDirectory(prefix="ii-packaged-proof-test-")
        self.root = Path(self.owned.name)
        self.application = self.root / "app"
        self.application.mkdir()
        (self.application / "app.bin").write_bytes(b"synthetic app")
        self.attestation = self.root / "attestation.json"

    def tearDown(self):
        self.owned.cleanup()

    def test_desktop_rejects_empty_malformed_duplicate_and_missing_roles(self):
        good = self.desktop_artifacts()
        for artifacts in ([], [{}, good[1]], [good[0], good[0]], [good[0]],
                          [{**good[0], "sha256": "z" * 64}, good[1]],
                          [{**good[0], "name": "../ffmpeg"}, good[1]],
                          [{**good[0], "architecture": "arm64"}, good[1]],
                          [{**good[0], "role": "unexpected"}, good[1]]):
            with self.subTest(artifacts=artifacts):
                self.write_desktop(artifacts)
                with self.assertRaises(RuntimeError):
                    verifier.verify_desktop(self.application, self.attestation, "linux")

    def desktop_artifacts(self):
        return [{"name": name, "role": name, "architecture": "x86_64",
                 "sha256": verifier.digest_bytes(name.encode())}
                for name in ("ffmpeg", "ffprobe")]

    def write_desktop(self, artifacts):
        self.attestation.write_text(json.dumps({"schema": 1, "platform": "linux",
                                               "architecture": "x86_64",
                                               "artifacts": artifacts}))

    def test_desktop_valid_producer_shape_binds_both_programs(self):
        directory = self.application / "data/flutter_assets/assets/desktop_engine"
        directory.mkdir(parents=True)
        for name in ("ffmpeg", "ffprobe"):
            (directory / name).write_bytes(name.encode())
        self.write_desktop(self.desktop_artifacts())
        result = verifier.verify_desktop(self.application, self.attestation, "linux")
        self.assertEqual(len(result["engine_files"]), 2)

    def test_ios_rejects_missing_partial_duplicate_and_unknown_bindings(self):
        for archives in ([], ["ffmpegkit=missing.zip"],
                         ["ffmpegkit=one.zip", "ffmpegkit=two.zip"],
                         ["unexpected=missing.zip"]):
            with self.subTest(archives=archives), mock.patch.object(
                verifier, "apple_security", return_value={}
            ), self.assertRaises(RuntimeError):
                verifier.verify_ios(self.application, archives, "ios-simulator")

    def test_web_rejects_empty_duplicate_and_malformed_records(self):
        good = [{"path": name, "sha256": "a" * 64}
                for name in ("ffmpeg.js", "ffmpeg-core.js", "ffmpeg-core.wasm")]
        cases = [[], good + [good[0]], good[:2]]
        for field, value in (("sha256", "z" * 64), ("path", "../ffmpeg.js")):
            changed = copy.deepcopy(good)
            changed[0][field] = value
            cases.append(changed)
        for artifacts in cases:
            self.attestation.write_text(json.dumps({"schema": 1, "artifacts": artifacts}))
            with self.subTest(artifacts=artifacts), self.assertRaises(RuntimeError):
                verifier.expected_engine_artifacts(self.attestation)

        self.attestation.write_text(json.dumps({"schema": 1, "artifacts": good}))
        self.assertEqual(verifier.expected_engine_artifacts(self.attestation),
                         {item["path"]: item["sha256"] for item in good})

    def test_shared_directory_verifier_refuses_empty_binding_proof(self):
        with self.assertRaises(RuntimeError):
            verifier.verify_directory_assets(self.application, {}, "/ffmpeg/", "test")


if __name__ == "__main__":
    unittest.main()
