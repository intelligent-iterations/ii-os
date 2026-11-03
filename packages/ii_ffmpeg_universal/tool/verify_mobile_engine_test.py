import importlib.util
import json
import os
import plistlib
import struct
import tempfile
import unittest
import zipfile
from pathlib import Path


SCRIPT = Path(__file__).with_name("verify_mobile_engine.py")
SPEC = importlib.util.spec_from_file_location("verify_mobile_engine", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class MobileEngineVerifierTest(unittest.TestCase):
    def setUp(self):
        self.owned = tempfile.TemporaryDirectory(prefix="ii-mobile-engine-test-")
        self.root = Path(self.owned.name)
        self.owner = f"ii-mobile-engine-test-{os.getpid()}-{id(self)}"
        (self.root / ".ii-disposable-owner").write_text(self.owner)
        self.lock = json.loads(
            Path(__file__).with_name("mobile_engine_lock.json").read_text()
        )

    def tearDown(self):
        self.assertEqual(
            (self.root / ".ii-disposable-owner").read_text(), self.owner
        )
        self.owned.cleanup()

    def _config(self, platform="android", forbidden=None):
        tokens = [
            "--cross-prefix=test-",
            f"--target-os={'android' if platform == 'android' else 'darwin'}",
            *self.lock["release_profile"]["required_flags"],
        ]
        if platform == "android":
            tokens.append("--enable-jni")
        if forbidden:
            tokens.append(forbidden)
        return " ".join(tokens).encode() + b"\0"

    def _elf(
        self,
        abi,
        library,
        payload,
        *,
        wrong_machine=False,
        dependency="libc.so",
        dependency_tag=1,
    ):
        elf_class, machine = MODULE.ANDROID_ELF[abi]
        header_size = 64 if elf_class == 2 else 52
        program_size = 56 if elf_class == 2 else 32
        header = bytearray(header_size + 2 * program_size)
        header[:6] = b"\x7fELF" + bytes([elf_class, 1])
        struct.pack_into("<HH", header, 16, 3, machine + int(wrong_machine))
        dynamic_offset = len(header)
        strings = b"\0" + dependency.encode() + b"\0" + library.encode() + b"\0"
        dynamic_size = (16 if elf_class == 2 else 8) * 5
        string_offset = dynamic_offset + dynamic_size
        body = bytearray(header + bytes(dynamic_size) + strings + payload)
        if elf_class == 2:
            struct.pack_into("<Q", body, 32, header_size)
            struct.pack_into("<HH", body, 54, program_size, 2)
            struct.pack_into(
                "<IIQQQQQQ", body, header_size, 1, 0, 0, 0x1000, 0, len(body), len(body), 4
            )
            struct.pack_into(
                "<IIQQQQQQ", body, header_size + program_size, 2, 0,
                dynamic_offset, 0x1000 + dynamic_offset, 0, dynamic_size, dynamic_size, 4
            )
            entries = [
                (5, 0x1000 + string_offset),
                (10, len(strings)),
                (dependency_tag, 1),
                (14, 2 + len(dependency)),
                (0, 0),
            ]
            for index, entry in enumerate(entries):
                struct.pack_into("<qQ", body, dynamic_offset + index * 16, *entry)
        else:
            struct.pack_into("<I", body, 28, header_size)
            struct.pack_into("<HH", body, 42, program_size, 2)
            struct.pack_into(
                "<IIIIIIII", body, header_size, 1, 0, 0x1000, 0,
                len(body), len(body), 4, 4
            )
            struct.pack_into(
                "<IIIIIIII", body, header_size + program_size, 2, dynamic_offset,
                0x1000 + dynamic_offset, 0, dynamic_size, dynamic_size, 4, 4
            )
            entries = [
                (5, 0x1000 + string_offset),
                (10, len(strings)),
                (dependency_tag, 1),
                (14, 2 + len(dependency)),
                (0, 0),
            ]
            for index, entry in enumerate(entries):
                struct.pack_into("<iI", body, dynamic_offset + index * 8, *entry)
        return bytes(body)

    def _android(
        self,
        *,
        licenses=True,
        forbidden=None,
        unsafe=False,
        wrong_machine=False,
        bad_dependency=False,
        bad_dependency_tag=1,
        manifest_package=None,
    ):
        path = self.root / "engine.aar"
        with zipfile.ZipFile(path, "w") as archive:
            package = (
                self.lock["release_profile"]["android_package"]
                if manifest_package is None
                else manifest_package
            )
            archive.writestr(
                "AndroidManifest.xml",
                f'<manifest package="{package}"/>\n',
            )
            for abi in self.lock["release_profile"]["android_abis"]:
                for library in self.lock["release_profile"]["android_libraries"][abi]:
                    payload = b"binary\0"
                    if library.startswith("libavutil"):
                        payload += self._config(forbidden=forbidden) + b"n8.1.2\0"
                    archive.writestr(
                        f"jni/{abi}/{library}",
                        self._elf(
                            abi,
                            library,
                            payload,
                            wrong_machine=wrong_machine
                            and abi == "arm64-v8a"
                            and library == "libavcodec.so",
                            dependency=(
                                "libescape.so"
                                if bad_dependency
                                and abi == "arm64-v8a"
                                and library == "libavcodec.so"
                                else "libc.so"
                            ),
                            dependency_tag=(
                                bad_dependency_tag
                                if bad_dependency
                                and abi == "arm64-v8a"
                                and library == "libavcodec.so"
                                else 1
                            ),
                        ),
                    )
            if licenses:
                archive.writestr("res/raw/license.txt", "LGPL")
            archive.writestr(
                "res/raw/ii_ffmpeg_source_ledger.json", '{"schema":1}\n'
            )
            if unsafe:
                archive.writestr("../escape", "bad")
        return path

    def _macho(
        self,
        architectures,
        payload=b"",
        *,
        simulator=False,
        dependency_command=0xC,
        dependency=b"/usr/lib/libSystem.B.dylib\0",
    ):
        identities = {
            "arm64": (0x0100000C, 0),
            "arm64e": (0x0100000C, 2),
            "x86_64": (0x01000007, 3),
        }
        slices = [
            self._thin_macho(
                architecture,
                payload,
                simulator=simulator,
                dependency_command_value=dependency_command,
                dependency=dependency,
            )
            for architecture in architectures
        ]
        offset = 8 + 20 * len(architectures)
        header = bytearray(struct.pack(">II", 0xCAFEBABE, len(architectures)))
        bodies = bytearray()
        for architecture, body in zip(architectures, slices):
            cpu_type, cpu_subtype = identities[architecture]
            header.extend(
                struct.pack(">IIIII", cpu_type, cpu_subtype, offset, len(body), 0)
            )
            bodies.extend(body)
            offset += len(body)
        return bytes(header + bodies)

    def _thin_macho(
        self,
        architecture,
        payload,
        *,
        simulator,
        dependency_command_value=0xC,
        dependency=b"/usr/lib/libSystem.B.dylib\0",
    ):
        identities = {
            "arm64": (0x0100000C, 0),
            "arm64e": (0x0100000C, 2),
            "x86_64": (0x01000007, 3),
        }
        command_size = (24 + len(dependency) + 7) & ~7
        dependency_command = bytearray(command_size)
        struct.pack_into(
            "<IIIIII",
            dependency_command,
            0,
            dependency_command_value,
            command_size,
            24,
            0,
            0,
            0,
        )
        dependency_command[24 : 24 + len(dependency)] = dependency
        build_command = struct.pack(
            "<IIIIII", 0x32, 24, 7 if simulator else 2, 0x000E0000, 0x00120000, 0
        )
        commands = bytes(dependency_command) + build_command
        cpu_type, cpu_subtype = identities[architecture]
        header = struct.pack(
            "<IiiIIIII", 0xFEEDFACF, cpu_type, cpu_subtype, 6, 2, len(commands), 0, 0
        )
        return header + commands + payload

    def _ios(
        self,
        *,
        bad_architecture=False,
        bad_metadata=False,
        bad_lazy_dependency=False,
    ):
        result = {}
        for library in self.lock["release_profile"]["ios_libraries"]:
            path = self.root / f"{library}.zip"
            with zipfile.ZipFile(path, "w") as archive:
                available = []
                for slice_spec in self.lock["release_profile"]["ios_slices"]:
                    identifier = slice_spec["identifier"]
                    architectures = list(slice_spec["architectures"])
                    available.append(
                        {
                            "LibraryIdentifier": identifier,
                            "LibraryPath": (
                                "wrong.framework"
                                if bad_metadata and library == "ffmpegkit"
                                else f"{library}.framework"
                            ),
                            "SupportedArchitectures": architectures,
                            "SupportedPlatform": slice_spec["platform"],
                            **(
                                {
                                    "SupportedPlatformVariant": slice_spec["variant"]
                                }
                                if "variant" in slice_spec
                                else {}
                            ),
                        }
                    )
                    payload = b"binary\0"
                    if library == "libavutil":
                        payload += self._config("ios") + b"n8.1.2\0"
                    elif library == "ffmpegkit":
                        payload += b"n8.1.2\0"
                    if (
                        bad_architecture
                        and library == "libavcodec"
                        and identifier == "ios-arm64_arm64e"
                    ):
                        architectures = ["arm64"]
                    archive.writestr(
                        f"{library}.xcframework/{identifier}/"
                        f"{library}.framework/{library}",
                        self._macho(
                            architectures,
                            payload,
                            simulator=slice_spec.get("variant") == "simulator",
                            dependency_command=(
                                0x20
                                if bad_lazy_dependency and library == "libavcodec"
                                else 0xC
                            ),
                            dependency=(
                                b"@rpath/unreviewed.framework/unreviewed\0"
                                if bad_lazy_dependency and library == "libavcodec"
                                else b"/usr/lib/libSystem.B.dylib\0"
                            ),
                        ),
                    )
                archive.writestr(
                    f"{library}.xcframework/Info.plist",
                    plistlib.dumps({"AvailableLibraries": available}),
                )
                archive.writestr(
                    f"{library}.xcframework/LICENSE",
                    "LGPL",
                )
            result[library] = path
        return result

    def test_release_android_accepts_exact_local_profile(self):
        result = MODULE.verify_android(self._android(), self.lock, True, None)
        self.assertEqual(result["engine_version"], "n8.1.2")
        self.assertTrue(result["release_profile"])

    def test_release_android_rejects_missing_license(self):
        with self.assertRaisesRegex(MODULE.VerificationError, "license payload"):
            MODULE.verify_android(self._android(licenses=False), self.lock, True, None)

    def test_android_rejects_a_manifest_for_another_package(self):
        with self.assertRaisesRegex(
            MODULE.VerificationError,
            "manifest package mismatch",
        ):
            MODULE.verify_android(
                self._android(manifest_package="com.example.changed"),
                self.lock,
                True,
                None,
            )

    def test_forbidden_flag_is_rejected_even_in_audit_mode(self):
        with self.assertRaisesRegex(MODULE.VerificationError, "forbidden"):
            MODULE.verify_android(
                self._android(forbidden="--enable-gpl"), self.lock, False, None
            )

    def test_unsafe_zip_member_is_rejected(self):
        with self.assertRaisesRegex(MODULE.VerificationError, "unsafe zip member"):
            MODULE.verify_android(self._android(unsafe=True), self.lock, True, None)

    def test_android_rejects_a_wrong_elf_target(self):
        with self.assertRaisesRegex(MODULE.VerificationError, "ELF target mismatch"):
            MODULE.verify_android(
                self._android(wrong_machine=True), self.lock, True, None
            )

    def test_android_rejects_an_unreviewed_dynamic_dependency(self):
        with self.assertRaisesRegex(MODULE.VerificationError, "dynamic closure"):
            MODULE.verify_android(
                self._android(bad_dependency=True), self.lock, True, None
            )

    def test_android_rejects_unreviewed_filter_and_auxiliary_edges(self):
        for tag in (0x7FFFFFFF, 0x7FFFFFFD):
            with self.subTest(tag=tag), self.assertRaisesRegex(
                MODULE.VerificationError, "dynamic closure"
            ):
                MODULE.verify_android(
                    self._android(bad_dependency=True, bad_dependency_tag=tag),
                    self.lock,
                    True,
                    None,
                )

    def test_release_ios_accepts_complete_archive_set(self):
        result = MODULE.verify_ios(self._ios(), self.lock, True)
        self.assertEqual(result["engine_version"], "n8.1.2")
        self.assertEqual(
            set(result["archives"]),
            set(self.lock["release_profile"]["ios_libraries"]),
        )

    def test_ios_rejects_macho_slices_that_disagree_with_metadata(self):
        with self.assertRaisesRegex(MODULE.VerificationError, "Mach-O slice mismatch"):
            MODULE.verify_ios(
                self._ios(bad_architecture=True), self.lock, True
            )

    def test_ios_rejects_wrong_xcframework_metadata(self):
        with self.assertRaisesRegex(MODULE.VerificationError, "metadata mismatch"):
            MODULE.verify_ios(self._ios(bad_metadata=True), self.lock, True)

    def test_ios_rejects_an_unreviewed_lazy_load_dependency(self):
        with self.assertRaisesRegex(MODULE.VerificationError, "dynamic closure"):
            MODULE.verify_ios(
                self._ios(bad_lazy_dependency=True), self.lock, True
            )


if __name__ == "__main__":
    unittest.main()
