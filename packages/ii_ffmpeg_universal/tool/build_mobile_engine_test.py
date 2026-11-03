import contextlib
import hashlib
import importlib.util
import io
import json
import os
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock

import mobile_engine_host_tools as HOST_TOOLS


SCRIPT = Path(__file__).with_name("build_mobile_engine.py")
SPEC = importlib.util.spec_from_file_location("build_mobile_engine", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class MobileEngineBuildRecipeTest(unittest.TestCase):
    def setUp(self):
        self.lock = json.loads(
            Path(__file__).with_name("mobile_engine_lock.json").read_text()
        )

    def test_every_remote_input_is_an_exact_commit(self):
        specs = [
            self.lock["build_recipe"],
            self.lock["android_wrapper"],
            *self.lock["sources"],
        ]
        for spec in specs:
            self.assertRegex(spec["revision"], r"^[0-9a-f]{40}$")
            self.assertTrue(spec["repository"].startswith("https://github.com/"))

        host_tools = self.lock["host_build_tools"]
        self.assertEqual([tool["name"] for tool in host_tools], ["gperf", "meson"])
        gperf, meson = host_tools
        self.assertEqual(gperf["revision"], "gperf-3.1")
        self.assertEqual(
            gperf["url"], "https://ftp.gnu.org/gnu/gperf/gperf-3.1.tar.gz"
        )
        self.assertRegex(gperf["sha256"], r"^[0-9a-f]{64}$")
        self.assertEqual(gperf["root"], "gperf-3.1")
        self.assertEqual(gperf["license_paths"], ["COPYING"])
        self.assertEqual(set(gperf["platforms"]), {"android", "ios"})
        self.assertEqual(meson["revision"], "1.11.2")
        self.assertEqual(meson["version"], "1.11.2")
        self.assertEqual(
            meson["url"],
            "https://github.com/mesonbuild/meson/releases/download/1.11.2/meson-1.11.2.tar.gz",
        )
        self.assertRegex(meson["sha256"], r"^[0-9a-f]{64}$")
        self.assertEqual(meson["root"], "meson-1.11.2")
        self.assertEqual(meson["license_paths"], ["COPYING"])
        self.assertEqual(meson["platforms"], ["ios"])
        self.assertEqual(meson["build_kind"], "python-script")
        self.assertEqual(meson["entry_point"], "meson.py")
        self.assertEqual(meson["interpreter"], "/usr/bin/python3")

        self.assertEqual(
            self.lock["build_recipe"],
            {
                "repository": "https://github.com/arthenica/ffmpeg-kit-next.git",
                "revision": "3e223118e6e8fb6208693ecf3952e77cd096f587",
            },
        )

    def test_locked_host_tool_is_built_and_prepended_to_path(self):
        with tempfile.TemporaryDirectory(prefix="ii-mobile-host-tool-test-") as owned:
            workspace = Path(owned)
            source = workspace / "host-tools/gperf-unpacked/gperf-3.1"
            prefix = workspace / "host-tools/gperf-prefix/bin"
            commands = []

            def download_fixture(url, sha256, destination):
                self.assertEqual(
                    url, "https://ftp.gnu.org/gnu/gperf/gperf-3.1.tar.gz"
                )
                self.assertEqual(
                    sha256,
                    "588546b945bba4b70b6a3a616e80b4ab466e3f33024a352fc2198112cdbb3ae2",
                )
                destination.write_bytes(b"locked-gperf-archive")

            def extract_fixture(archive, destination):
                self.assertTrue(archive.is_file())
                source.mkdir(parents=True)
                (source / "COPYING").write_text("GPL\n", encoding="utf-8")
                configure = source / "configure"
                configure.write_text("#!/bin/sh\n", encoding="utf-8")
                configure.chmod(0o700)

            def source_record_fixture(
                name, repository, revision, path, declared_license_paths
            ):
                self.assertEqual(path, source)
                self.assertEqual(declared_license_paths, ["COPYING"])
                return {"name": name, "repository": repository, "revision": revision}

            def run_fixture(command, cwd=None):
                commands.append(command)
                if command == ["make", "-C", "src", "install"]:
                    prefix.mkdir(parents=True)
                    executable = prefix / "gperf"
                    executable.write_text(
                        "#!/bin/sh\nprintf 'GNU gperf 3.1\\n'\n", encoding="utf-8"
                    )
                    executable.chmod(0o700)

            previous_path = os.environ.get("PATH")
            try:
                with mock.patch.object(HOST_TOOLS, "run", run_fixture):
                    identities, sources = MODULE._prepare_host_build_tools(
                        workspace,
                        self.lock,
                        "android",
                        download=download_fixture,
                        extract=extract_fixture,
                        record_source=source_record_fixture,
                    )
            finally:
                if previous_path is None:
                    os.environ.pop("PATH", None)
                else:
                    os.environ["PATH"] = previous_path

            self.assertEqual(identities[0]["name"], "gperf")
            self.assertEqual(identities[0]["version"], "3.1")
            self.assertEqual(sources[0]["name"], "gperf")
            self.assertEqual(
                commands,
                [
                    ["./configure", f"--prefix={workspace / 'host-tools/gperf-prefix'}"],
                    ["make", "-C", "lib", "-j2"],
                    ["make", "-C", "src", "-j2"],
                    ["make", "-C", "src", "install"],
                ],
            )

    def test_release_profile_is_local_only_and_excludes_gpl(self):
        profile = self.lock["release_profile"]
        self.assertIn("--disable-network", profile["required_flags"])
        self.assertIn("--enable-gpl", profile["forbidden_flags"])
        self.assertIn("--enable-nonfree", profile["forbidden_flags"])
        source_names = {source["name"] for source in self.lock["sources"]}
        self.assertTrue(
            source_names.isdisjoint(
                {"x264", "x265", "xvidcore", "libvidstab", "rubberband"}
            )
        )
        self.assertRegex(
            self.lock["toolchains"]["android_ndk_revision"],
            r"^[0-9]+\.[0-9]+\.[0-9]+$",
        )
        for libraries in profile["android_libraries"].values():
            self.assertIn("libavdevice.so", libraries)
            self.assertNotIn("libc++_shared.so", libraries)

    def test_source_names_are_unique_and_platforms_are_explicit(self):
        sources = self.lock["sources"]
        self.assertEqual(len(sources), len({source["name"] for source in sources}))
        for source in sources:
            self.assertTrue(source["recipe_source_id"])
            self.assertTrue(source["platforms"])
            self.assertLessEqual(set(source["platforms"]), {"android", "ios"})

    def test_ffmpegkitnext_source_staging_creates_missing_parent_roots(self):
        with tempfile.TemporaryDirectory(
            prefix="ii-mobile-source-root-test-"
        ) as owned:
            recipe = Path(owned) / "ffmpeg-kit"
            recipe.mkdir()
            self.assertFalse((recipe / "src").exists())
            self.assertFalse((recipe / ".tmp").exists())

            ffmpeg = MODULE._prepare_source_destination(recipe, "ffmpeg")
            config = MODULE._prepare_source_destination(recipe, "config")

            self.assertEqual(ffmpeg, recipe / "src/ffmpeg")
            self.assertEqual(config, recipe / ".tmp/source/config")
            self.assertTrue(ffmpeg.parent.is_dir())
            self.assertTrue(config.parent.is_dir())
            self.assertFalse(ffmpeg.exists())
            self.assertFalse(config.exists())

    def test_ios_build_fails_closed_without_attested_apple_tools(self):
        with tempfile.TemporaryDirectory(prefix="ii-mobile-ios-input-test-") as owned:
            result = subprocess.run(
                [
                    "python3",
                    str(SCRIPT),
                    "ios",
                    "--prepare-only",
                    "--workspace",
                    str(Path(owned) / "workspace"),
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 1)
            self.assertIn("require an attested Apple build toolchain", result.stderr)
            self.assertFalse((Path(owned) / "workspace").exists())

    def test_ios_xcframework_build_excludes_unlocked_catalyst_slices(self):
        with tempfile.TemporaryDirectory(prefix="ii-mobile-ios-slice-test-") as owned:
            root = Path(owned)
            recipe = root / "ffmpeg-kit"
            framework = recipe / "prebuilt/apple/ffmpegkit.xcframework"
            binary = framework / "ios-arm64/ffmpegkit.framework/ffmpegkit"
            binary.parent.mkdir(parents=True)
            binary.write_bytes(b"engine")
            artifacts = root / "artifacts"
            artifacts.mkdir()
            commands = []

            with (
                mock.patch.object(MODULE.sys, "platform", "darwin"),
                mock.patch.object(MODULE.shutil, "which", return_value="/usr/bin/xcrun"),
                mock.patch.object(
                    MODULE,
                    "_run",
                    side_effect=lambda command, cwd=None: commands.append((command, cwd)),
                ),
            ):
                outputs = MODULE._build_ios(
                    recipe,
                    artifacts,
                    ["ffmpegkit"],
                    "14.0",
                )

            command, cwd = commands[0]
            self.assertEqual(cwd, recipe)
            self.assertIn("--xcframework", command)
            self.assertIn("--disable-arm64-mac-catalyst", command)
            self.assertIn("--disable-x86-64-mac-catalyst", command)
            self.assertEqual(outputs, [artifacts / "ffmpegkit.xcframework.zip"])

    def test_android_linux_arm_hosts_use_the_published_ndk_host_tag(self):
        source = f"get_toolchain() {{\n{MODULE.ANDROID_HOST_TOOLCHAIN_UPSTREAM}}}\n"
        expected = f"get_toolchain() {{\n{MODULE.ANDROID_HOST_TOOLCHAIN_PATCHED}}}\n"
        with tempfile.TemporaryDirectory(prefix="ii-mobile-host-tag-test-") as owned:
            script = Path(owned) / "function-android.sh"
            script.write_text(source)
            MODULE._replace_once(
                script,
                MODULE.ANDROID_HOST_TOOLCHAIN_UPSTREAM,
                MODULE.ANDROID_HOST_TOOLCHAIN_PATCHED,
            )
            self.assertEqual(script.read_text(), expected)

        executable_fixture = f"""#!/usr/bin/env bash
set -euo pipefail
uname() {{
  if [ "$1" = "-s" ]; then
    printf '%s\\n' "${{MOCK_HOST_OS}}"
  else
    printf '%s\\n' "${{MOCK_HOST_ARCH}}"
  fi
}}
is_darwin_arm64() {{
  if [ "$(uname -s)" = "Darwin" ] && [ "$(uname -m)" = "arm64" ]; then
    echo 1
  else
    echo 0
  fi
}}
get_toolchain() {{
  HOST_OS=$(uname -s)
  case ${{HOST_OS}} in
  Darwin) HOST_OS=darwin ;;
  Linux) HOST_OS=linux ;;
  esac
  HOST_ARCH=$(uname -m)
  case ${{HOST_ARCH}} in
  i?86) HOST_ARCH=x86 ;;
  x86_64 | amd64) HOST_ARCH=x86_64 ;;
  esac
{MODULE.ANDROID_HOST_TOOLCHAIN_PATCHED}
  echo "${{HOST_OS}}-${{HOST_ARCH}}"
}}
get_toolchain
"""
        cases = {
            ("Linux", "aarch64"): "linux-x86_64",
            ("Linux", "arm64"): "linux-x86_64",
            ("Linux", "x86_64"): "linux-x86_64",
            ("Darwin", "arm64"): "darwin-x86_64",
        }
        for (host_os, host_arch), toolchain in cases.items():
            with self.subTest(host_os=host_os, host_arch=host_arch):
                result = subprocess.run(
                    ["bash", "-c", executable_fixture],
                    check=True,
                    capture_output=True,
                    text=True,
                    env={
                        **os.environ,
                        "MOCK_HOST_OS": host_os,
                        "MOCK_HOST_ARCH": host_arch,
                    },
                )
                self.assertEqual(result.stdout.strip(), toolchain)

    def test_libiconv_developer_docs_are_removed_from_build_inputs(self):
        with tempfile.TemporaryDirectory(
            prefix="ii-mobile-libiconv-doc-test-"
        ) as owned:
            root = Path(owned)
            developer_makefile = root / "Makefile.devel"
            install_makefile = root / "man/Makefile.in"
            install_makefile.parent.mkdir()
            developer_makefile.write_text(
                "all : generated \\\n"
                + MODULE.LIBICONV_DEVELOPER_MANPAGES
                + "      force\n",
                encoding="utf-8",
            )
            install_makefile.write_text(
                "install : force\n"
                + MODULE.LIBICONV_HTML_INSTALL
                + "install-strip : install\n",
                encoding="utf-8",
            )
            self.assertEqual(
                MODULE._strip_libiconv_developer_manpages(root),
                (developer_makefile, install_makefile),
            )
            transformed = developer_makefile.read_text(encoding="utf-8")
            installed = install_makefile.read_text(encoding="utf-8")
            self.assertEqual(transformed, "all : generated \\\n      force\n")
            self.assertNotIn("groff", transformed)
            self.assertNotIn(".html", transformed)
            self.assertEqual(installed, "install : force\ninstall-strip : install\n")
            self.assertNotIn("*.html", installed)

    def test_libuuid_consumes_the_generated_feature_checks(self):
        with tempfile.TemporaryDirectory(
            prefix="ii-mobile-libuuid-config-test-"
        ) as owned:
            root = Path(owned)
            implementation = root / "gen_uuid.c"
            implementation.write_text(
                "/* source header */\n"
                + MODULE.LIBUUID_CONFIG_INCLUDE_UPSTREAM
                + "#include <windows.h>\n",
                encoding="utf-8",
            )

            self.assertEqual(
                MODULE._include_libuuid_config_header(root),
                implementation,
            )
            self.assertEqual(
                implementation.read_text(encoding="utf-8"),
                "/* source header */\n"
                + MODULE.LIBUUID_CONFIG_INCLUDE_PATCHED
                + "#include <windows.h>\n",
            )

            with self.assertRaisesRegex(
                MODULE.BuildError,
                "expected one patch location",
            ):
                MODULE._include_libuuid_config_header(root)

    def test_obsolete_postproc_switch_is_removed_exactly_once(self):
        with tempfile.TemporaryDirectory(
            prefix="ii-mobile-postproc-option-test-"
        ) as owned:
            script = Path(owned) / "ffmpeg.sh"
            script.write_text(
                "  --disable-programs \\\n"
                + MODULE.OBSOLETE_POSTPROC_DISABLE
                + "  --disable-doc \\\n",
                encoding="utf-8",
            )

            self.assertEqual(
                MODULE._strip_obsolete_postproc_disable(script),
                script,
            )
            self.assertEqual(
                script.read_text(encoding="utf-8"),
                "  --disable-programs \\\n  --disable-doc \\\n",
            )

            with self.assertRaisesRegex(
                MODULE.BuildError,
                "expected one patch location",
            ):
                MODULE._strip_obsolete_postproc_disable(script)

    def test_removed_emms_header_install_is_guarded_exactly_once(self):
        with tempfile.TemporaryDirectory(
            prefix="ii-mobile-emms-header-test-"
        ) as owned:
            script = Path(owned) / "ffmpeg.sh"
            script.write_text(
                "prepare_ffmpeg\n"
                + MODULE.OBSOLETE_EMMS_HEADER_INSTALL
                + "finish_ffmpeg\n",
                encoding="utf-8",
            )

            self.assertEqual(
                MODULE._make_removed_emms_header_optional(script),
                script,
            )
            self.assertEqual(
                script.read_text(encoding="utf-8"),
                "prepare_ffmpeg\n"
                + MODULE.OPTIONAL_EMMS_HEADER_INSTALL
                + "finish_ffmpeg\n",
            )

            with self.assertRaisesRegex(
                MODULE.BuildError,
                "expected one patch location",
            ):
                MODULE._make_removed_emms_header_optional(script)

    def test_x86_64_ffmpeg_cpu_uses_clang_spelling_exactly_once(self):
        with tempfile.TemporaryDirectory(
            prefix="ii-mobile-x86-64-cpu-test-"
        ) as owned:
            script = Path(owned) / "ffmpeg.sh"
            script.write_text(
                "case ${ARCH} in\n"
                + MODULE.X86_64_FFMPEG_CPU_UPSTREAM
                + '  ASM_OPTIONS=" --enable-asm"\n'
                + "  ;;\nesac\n",
                encoding="utf-8",
            )

            self.assertEqual(MODULE._repair_x86_64_ffmpeg_cpu(script), script)
            self.assertIn(
                MODULE.X86_64_FFMPEG_CPU_PATCHED,
                script.read_text(encoding="utf-8"),
            )

            with self.assertRaisesRegex(
                MODULE.BuildError,
                "expected one patch location",
            ):
                MODULE._repair_x86_64_ffmpeg_cpu(script)

    def test_linux_arm_ndk_build_uses_scoped_host_uname_exactly_once(self):
        with tempfile.TemporaryDirectory(
            prefix="ii-mobile-ndk-host-uname-test-"
        ) as owned:
            script = Path(owned) / "android.sh"
            script.write_text(
                "prepare_native_wrapper\n"
                + MODULE.ANDROID_NDK_BUILD_UPSTREAM
                + "finish_native_wrapper\n",
                encoding="utf-8",
            )

            self.assertEqual(MODULE._support_linux_arm_ndk_build(script), script)
            patched = script.read_text(encoding="utf-8")
            self.assertIn(MODULE.ANDROID_NDK_BUILD_PATCHED, patched)
            self.assertIn('PATH="${host_uname_directory}:${PATH}"', patched)
            self.assertIn("'  printf \"%s\\n\" x86_64'", patched)

            with self.assertRaisesRegex(
                MODULE.BuildError,
                "expected one patch location",
            ):
                MODULE._support_linux_arm_ndk_build(script)

    def testFrameworkZipIsByteDeterministic(self):
        with tempfile.TemporaryDirectory(prefix="ii-mobile-zip-test-") as owned:
            root = Path(owned)
            framework = root / "libavutil.xcframework"
            binary = framework / "ios-arm64/libavutil.framework/libavutil"
            binary.parent.mkdir(parents=True)
            binary.write_bytes(b"engine")
            first = root / "first.zip"
            second = root / "second.zip"
            MODULE._deterministic_zip(framework, first)
            MODULE._deterministic_zip(framework, second)
            self.assertEqual(
                hashlib.sha256(first.read_bytes()).digest(),
                hashlib.sha256(second.read_bytes()).digest(),
            )

    def test_android_aar_is_created_without_a_gradle_invocation(self):
        with tempfile.TemporaryDirectory(prefix="ii-mobile-aar-test-") as owned:
            root = Path(owned)
            project = root / "android"
            source = project / "src/main/java/example/Plugin.java"
            source.parent.mkdir(parents=True)
            source.write_text("package example; final class Plugin {}\n")
            manifest = project / "src/main/AndroidManifest.xml"
            manifest.parent.mkdir(parents=True, exist_ok=True)
            manifest.write_text('<manifest package="example"/>\n')
            native = project / "src/main/jniLibs/x86_64/libffmpeg.so"
            native.parent.mkdir(parents=True)
            native.write_bytes(b"native")
            android_jar = root / "android.jar"
            android_jar.write_bytes(b"sdk")

            def compile_fixture(command, cwd=None):
                self.assertEqual(command[0], "javac")
                self.assertNotIn("gradle", " ".join(command).lower())
                classes = project / "ii-offline-build/classes/example"
                classes.mkdir(parents=True)
                (classes / "Plugin.class").write_bytes(b"class")

            first = root / "first.aar"
            with mock.patch.object(MODULE, "_run", side_effect=compile_fixture):
                MODULE._build_android_aar(project, first, android_jar, 17)
            with zipfile.ZipFile(first) as archive:
                self.assertEqual(
                    archive.namelist(),
                    ["AndroidManifest.xml", "classes.jar", "jni/x86_64/libffmpeg.so"],
                )
                with zipfile.ZipFile(archive.open("classes.jar")) as classes:
                    self.assertEqual(classes.namelist(), ["example/Plugin.class"])

    def test_failure_log_tail_has_a_fixed_read_bound(self):
        with tempfile.TemporaryDirectory(prefix="ii-mobile-log-test-") as owned:
            workspace = Path(owned)
            log = workspace / "ffmpeg-kit/build.log"
            log.parent.mkdir(parents=True)
            log.write_bytes(
                b"discarded-early-diagnostic\n"
                + b"x" * (MODULE.BUILD_LOG_TAIL_BYTES + 4096)
                + b"\nretained-final-diagnostic\n"
            )
            stderr = io.StringIO()
            with contextlib.redirect_stderr(stderr):
                MODULE._print_bounded_build_log(workspace)
            output = stderr.getvalue()
            self.assertNotIn("discarded-early-diagnostic", output)
            self.assertIn("retained-final-diagnostic", output)
            self.assertLessEqual(len(output), 240 * 4001 + 100)

    def test_config_log_diagnostics_are_bounded_and_skip_links(self):
        with tempfile.TemporaryDirectory(prefix="ii-mobile-config-log-test-") as owned:
            workspace = Path(owned)
            source = workspace / "ffmpeg-kit/src/fribidi"
            source.mkdir(parents=True)
            config_log = source / "config.log"
            config_log.write_bytes(
                b"discarded-config-diagnostic\n"
                + b"x" * (MODULE.CONFIG_LOG_TAIL_BYTES + 4096)
                + b"\nretained-config-diagnostic\n"
            )
            linked_source = workspace / "ffmpeg-kit/src/linked"
            linked_source.mkdir()
            (workspace / "outside.log").write_text(
                "must-not-be-read\n", encoding="utf-8"
            )
            (linked_source / "config.log").symlink_to(workspace / "outside.log")

            stderr = io.StringIO()
            with contextlib.redirect_stderr(stderr):
                MODULE._print_bounded_config_logs(workspace)

            output = stderr.getvalue()
            self.assertNotIn("discarded-config-diagnostic", output)
            self.assertNotIn("must-not-be-read", output)
            self.assertIn("retained-config-diagnostic", output)
            self.assertLessEqual(len(output), 160 * 4001 + 200)


if __name__ == "__main__":
    unittest.main()
