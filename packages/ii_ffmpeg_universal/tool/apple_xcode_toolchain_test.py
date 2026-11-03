import os
from pathlib import Path
import tempfile
import unittest

from apple_xcode_toolchain import (
    _resolve_sdk_directory,
    XcodeToolchainError,
)


class ResolveSdkDirectoryTest(unittest.TestCase):
    def test_accepts_directory_inside_selected_xcode(self) -> None:
        with tempfile.TemporaryDirectory() as owned:
            developer = Path(owned).resolve() / "Xcode.app/Contents/Developer"
            sdk = developer / "Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
            sdk.mkdir(parents=True)

            self.assertEqual(_resolve_sdk_directory(sdk, developer), sdk)

    def test_accepts_relative_sdk_alias_inside_selected_xcode(self) -> None:
        with tempfile.TemporaryDirectory() as owned:
            developer = Path(owned).resolve() / "Xcode.app/Contents/Developer"
            sdk_root = developer / "Platforms/iPhoneOS.platform/Developer/SDKs"
            versioned = sdk_root / "iPhoneOS26.0.sdk"
            versioned.mkdir(parents=True)
            alias = sdk_root / "iPhoneOS.sdk"
            alias.symlink_to(versioned.name)

            self.assertEqual(_resolve_sdk_directory(alias, developer), versioned)

    def test_rejects_absolute_sdk_alias(self) -> None:
        with tempfile.TemporaryDirectory() as owned:
            developer = Path(owned).resolve() / "Xcode.app/Contents/Developer"
            sdk_root = developer / "Platforms/iPhoneOS.platform/Developer/SDKs"
            versioned = sdk_root / "iPhoneOS26.0.sdk"
            versioned.mkdir(parents=True)
            alias = sdk_root / "iPhoneOS.sdk"
            os.symlink(versioned, alias)

            with self.assertRaisesRegex(
                XcodeToolchainError, "SDK directory is unsafe"
            ):
                _resolve_sdk_directory(alias, developer)

    def test_rejects_relative_sdk_alias_outside_selected_xcode(self) -> None:
        with tempfile.TemporaryDirectory() as owned:
            root = Path(owned).resolve()
            developer = root / "Xcode.app/Contents/Developer"
            sdk_root = developer / "Platforms/iPhoneOS.platform/Developer/SDKs"
            sdk_root.mkdir(parents=True)
            outside = root / "outside.sdk"
            outside.mkdir()
            alias = sdk_root / "iPhoneOS.sdk"
            alias.symlink_to(os.path.relpath(outside, sdk_root))

            with self.assertRaisesRegex(
                XcodeToolchainError, "outside the selected Xcode"
            ):
                _resolve_sdk_directory(alias, developer)

    def test_rejects_sdk_alias_to_file(self) -> None:
        with tempfile.TemporaryDirectory() as owned:
            developer = Path(owned).resolve() / "Xcode.app/Contents/Developer"
            sdk_root = developer / "Platforms/iPhoneOS.platform/Developer/SDKs"
            sdk_root.mkdir(parents=True)
            target = sdk_root / "iPhoneOS26.0.sdk"
            target.write_bytes(b"not a directory")
            alias = sdk_root / "iPhoneOS.sdk"
            alias.symlink_to(target.name)

            with self.assertRaisesRegex(
                XcodeToolchainError, "SDK directory is unsafe"
            ):
                _resolve_sdk_directory(alias, developer)


if __name__ == "__main__":
    unittest.main()
