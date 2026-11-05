from __future__ import annotations

import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

import stage_pinned_android_engine as stage


class PinnedAndroidEngineTest(unittest.TestCase):
    def _fixture(self, root: Path) -> tuple[Path, Path, str, str]:
        engine = root / "engine"
        artifacts = engine / "artifacts"
        tools = engine / "verification-tools"
        source = root / "source"
        artifacts.mkdir(parents=True)
        tools.mkdir()
        (source / "tool").mkdir(parents=True)

        source_sha = "a" * 40
        aar = artifacts / "ii-ffmpeg-mobile-android.aar"
        aar.write_bytes(b"reviewed-aar")
        aar_sha = hashlib.sha256(aar.read_bytes()).hexdigest()
        lock = source / "tool/mobile_engine_lock.json"
        lock.write_text('{"schema":1}\n', encoding="utf-8")
        builder = source / "tool/build_mobile_engine.py"
        builder.write_text("# reviewed builder\n", encoding="utf-8")
        ledger = {
            "schema": 1,
            "lock_sha256": hashlib.sha256(lock.read_bytes()).hexdigest(),
            "builder_sha256": hashlib.sha256(builder.read_bytes()).hexdigest(),
        }
        ledger_path = artifacts / "source-ledger.json"
        ledger_path.write_text(json.dumps(ledger), encoding="utf-8")
        notices = artifacts / "THIRD_PARTY_NOTICES.txt"
        notices.write_text("reviewed notices\n", encoding="utf-8")
        verification = artifacts / "verification.json"
        verification.write_text('{"platform":"android"}\n', encoding="utf-8")
        attestation = {
            "schema": 1,
            "platform": "android",
            "artifacts": [
                {"path": aar.name, "sha256": aar_sha},
            ],
            "source_ledger_sha256": hashlib.sha256(
                ledger_path.read_bytes()
            ).hexdigest(),
            "notices_sha256": hashlib.sha256(notices.read_bytes()).hexdigest(),
            "verification_sha256": hashlib.sha256(
                verification.read_bytes()
            ).hexdigest(),
        }
        (artifacts / "build-attestation.json").write_text(
            json.dumps(attestation), encoding="utf-8"
        )
        (engine / "source-revision").write_text(source_sha + "\n", encoding="utf-8")
        verifier = source / "tool/verify_mobile_engine.py"
        verifier.write_text("# reviewed verifier\n", encoding="utf-8")
        return engine, source, source_sha, aar_sha

    @mock.patch("stage_pinned_android_engine.subprocess.run")
    def test_accepts_exact_baked_engine_and_invokes_pinned_verifier(
        self, run: mock.Mock
    ) -> None:
        with tempfile.TemporaryDirectory(prefix="ii-os-baked-engine-") as owned:
            root = Path(owned)
            engine, source, source_sha, aar_sha = self._fixture(root)
            output = root / "binding.json"

            report = stage.stage_engine(
                engine,
                source,
                source_sha,
                aar_sha,
                output,
            )

            self.assertEqual(report["aar_sha256"], aar_sha)
            self.assertEqual(report["source_sha"], source_sha)
            self.assertEqual(Path(report["aar_path"]).read_bytes(), b"reviewed-aar")
            run.assert_called_once()
            command = run.call_args.args[0]
            self.assertEqual(command[0], "python3")
            self.assertIn("--release", command)
            self.assertEqual(command[-1], aar_sha)
            self.assertTrue(output.is_file())

    @mock.patch("stage_pinned_android_engine.subprocess.run")
    def test_rejects_symlinked_engine_evidence(self, run: mock.Mock) -> None:
        with tempfile.TemporaryDirectory(prefix="ii-os-baked-engine-") as owned:
            root = Path(owned)
            engine, source, source_sha, aar_sha = self._fixture(root)
            ledger = engine / "artifacts/source-ledger.json"
            replacement = root / "replacement-ledger.json"
            replacement.write_bytes(ledger.read_bytes())
            ledger.unlink()
            ledger.symlink_to(replacement)
            with self.assertRaisesRegex(RuntimeError, "regular file"):
                stage.stage_engine(engine, source, source_sha, aar_sha, root / "out.json")
            run.assert_not_called()

    @mock.patch("stage_pinned_android_engine.subprocess.run")
    def test_rejects_wrong_source_or_aar_before_verifier(self, run: mock.Mock) -> None:
        with tempfile.TemporaryDirectory(prefix="ii-os-baked-engine-") as owned:
            root = Path(owned)
            engine, source, source_sha, aar_sha = self._fixture(root)
            with self.assertRaisesRegex(RuntimeError, "source revision"):
                stage.stage_engine(engine, source, "b" * 40, aar_sha, root / "one.json")
            with self.assertRaisesRegex(RuntimeError, "AAR checksum"):
                stage.stage_engine(engine, source, source_sha, "c" * 64, root / "two.json")
            run.assert_not_called()

    @mock.patch("stage_pinned_android_engine.subprocess.run")
    def test_rejects_attestation_or_source_ledger_drift(self, run: mock.Mock) -> None:
        with tempfile.TemporaryDirectory(prefix="ii-os-baked-engine-") as owned:
            root = Path(owned)
            engine, source, source_sha, aar_sha = self._fixture(root)
            (engine / "artifacts/source-ledger.json").write_text(
                '{"schema":1,"lock_sha256":"changed"}', encoding="utf-8"
            )
            with self.assertRaisesRegex(RuntimeError, "source ledger"):
                stage.stage_engine(engine, source, source_sha, aar_sha, root / "out.json")
            run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
