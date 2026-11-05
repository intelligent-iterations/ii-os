from __future__ import annotations

import tempfile
import unittest
import zipfile
from pathlib import Path

from verify_android_aab_engine import verify_android_aab_engine


class AndroidAabEngineBindingTest(unittest.TestCase):
    @staticmethod
    def _write_engine_archives(
        aar: Path,
        aab: Path,
        *,
        aab_overrides: dict[str, bytes | None] | None = None,
    ) -> None:
        engine_by_abi = {
            "armeabi-v7a": b"armv7-engine",
            "arm64-v8a": b"arm64-engine",
            "x86_64": b"x64-engine",
            "x86": b"legacy-x86-engine",
        }
        with zipfile.ZipFile(aar, "w") as archive:
            for abi, contents in engine_by_abi.items():
                archive.writestr(f"jni/{abi}/libengine.so", contents)
        overrides = aab_overrides or {}
        with zipfile.ZipFile(aab, "w") as archive:
            for abi, contents in engine_by_abi.items():
                if abi == "x86":
                    continue
                packaged_name = f"base/lib/{abi}/libengine.so"
                packaged_contents = overrides.get(packaged_name, contents)
                if packaged_contents is not None:
                    archive.writestr(packaged_name, packaged_contents)
            for packaged_name, contents in overrides.items():
                abi = Path(packaged_name).parts[2]
                if abi in engine_by_abi and abi != "x86":
                    continue
                if contents is not None:
                    archive.writestr(packaged_name, contents)

    def test_flutter_release_abis_are_bound_and_legacy_x86_is_excluded(self) -> None:
        with tempfile.TemporaryDirectory(prefix="ii-os-aab-binding-") as owned:
            root = Path(owned)
            aar = root / "engine.aar"
            aab = root / "app.aab"
            self._write_engine_archives(aar, aab)

            report = verify_android_aab_engine(aab, aar)

            self.assertEqual(report["classification"], "release-aab-package-only")
            self.assertEqual(
                report["verified_abis"],
                ["arm64-v8a", "armeabi-v7a", "x86_64"],
            )
            self.assertEqual(report["excluded_engine_only_abis"], ["x86"])
            self.assertEqual(len(report["engine_files"]), 3)

    def test_different_engine_library_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="ii-os-aab-mismatch-") as owned:
            root = Path(owned)
            aar = root / "engine.aar"
            aab = root / "app.aab"
            self._write_engine_archives(
                aar,
                aab,
                aab_overrides={
                    "base/lib/arm64-v8a/libengine.so": b"different",
                },
            )

            with self.assertRaisesRegex(RuntimeError, "differs"):
                verify_android_aab_engine(aab, aar)

    def test_missing_flutter_release_engine_library_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="ii-os-aab-missing-") as owned:
            root = Path(owned)
            aar = root / "engine.aar"
            aab = root / "app.aab"
            self._write_engine_archives(
                aar,
                aab,
                aab_overrides={"base/lib/x86_64/libengine.so": None},
            )

            with self.assertRaisesRegex(RuntimeError, "missing an attested"):
                verify_android_aab_engine(aab, aar)

    def test_packaged_legacy_x86_engine_library_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="ii-os-aab-x86-") as owned:
            root = Path(owned)
            aar = root / "engine.aar"
            aab = root / "app.aab"
            self._write_engine_archives(
                aar,
                aab,
                aab_overrides={
                    "base/lib/x86/libengine.so": b"legacy-x86-engine",
                },
            )

            with self.assertRaisesRegex(RuntimeError, "unsupported by Flutter"):
                verify_android_aab_engine(aab, aar)


if __name__ == "__main__":
    unittest.main()
