import importlib.util
import tempfile
import unittest
from pathlib import Path

from mobile_engine_android_bridge import (
    LEGACY_ABI_METHODS,
    LEGACY_CONFIG_METHODS,
    NEXT_ABI_METHODS,
    NEXT_CONFIG_METHODS,
    _restrict_registration_table,
)


SCRIPT = Path(__file__).with_name("build_mobile_engine.py")
SPEC = importlib.util.spec_from_file_location("build_mobile_engine", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class MobileEngineWrapperTest(unittest.TestCase):
    def test_android_wrapper_manifest_is_bound_to_a_unique_binary_package(self):
        with tempfile.TemporaryDirectory(
            prefix="ii-mobile-wrapper-manifest-test-"
        ) as owned:
            wrapper = Path(owned)
            manifest = wrapper / "android/src/main/AndroidManifest.xml"
            manifest.parent.mkdir(parents=True)
            manifest.write_text(
                '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
                "<application />"
                "</manifest>\n",
                encoding="utf-8",
            )
            package = "com.antonkarpenko.ffmpegkit.binary"
            self.assertEqual(
                MODULE.adapt_android_wrapper_manifest(wrapper, package),
                manifest,
            )
            transformed = manifest.read_text(encoding="utf-8")
            self.assertIn(f'package="{package}"', transformed)
            self.assertEqual(
                MODULE.adapt_android_wrapper_manifest(wrapper, package),
                manifest,
            )
            manifest.write_text(
                '<manifest package="com.example.changed"/>\n',
                encoding="utf-8",
            )
            with self.assertRaisesRegex(
                MODULE.BuildError,
                "manifest namespace changed",
            ):
                MODULE.adapt_android_wrapper_manifest(wrapper, package)

    def test_android_wrapper_manifest_rejects_the_plugin_namespace(self):
        with tempfile.TemporaryDirectory(
            prefix="ii-mobile-wrapper-manifest-collision-test-"
        ) as owned:
            wrapper = Path(owned)
            manifest = wrapper / "android/src/main/AndroidManifest.xml"
            manifest.parent.mkdir(parents=True)
            manifest.write_text("<manifest />\n", encoding="utf-8")
            with self.assertRaisesRegex(
                MODULE.BuildError,
                "collides with the Flutter plugin namespace",
            ):
                MODULE.adapt_android_wrapper_manifest(
                    wrapper,
                    "com.antonkarpenko.ffmpegkit",
                )

    def test_android_wrapper_manifest_rejects_a_dtd(self):
        with tempfile.TemporaryDirectory(
            prefix="ii-mobile-wrapper-manifest-dtd-test-"
        ) as owned:
            wrapper = Path(owned)
            manifest = wrapper / "android/src/main/AndroidManifest.xml"
            manifest.parent.mkdir(parents=True)
            manifest.write_text(
                '<?xml version="1.0"?>\n'
                '<!DOCTYPE manifest [<!ENTITY x "x">]>\n'
                "<manifest>&x;</manifest>\n",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(
                MODULE.BuildError,
                "must not declare a DTD",
            ):
                MODULE.adapt_android_wrapper_manifest(
                    wrapper,
                    "com.antonkarpenko.ffmpegkit.binary",
                )

    def test_android_ffprobe_declares_c_string_functions_exactly_once(self):
        with tempfile.TemporaryDirectory(
            prefix="ii-mobile-wrapper-string-test-"
        ) as owned:
            native_source = Path(owned)
            implementation = native_source / "ffprobekit.c"
            implementation.write_text(
                MODULE.ANDROID_FFPROBE_HEADERS_UPSTREAM
                + "void run(void) { strlen(\"ffprobe\"); }\n",
                encoding="utf-8",
            )
            self.assertEqual(
                MODULE._include_android_wrapper_string_header(native_source),
                implementation,
            )
            self.assertIn(
                MODULE.ANDROID_FFPROBE_HEADERS_PATCHED,
                implementation.read_text(encoding="utf-8"),
            )
            with self.assertRaisesRegex(
                MODULE.BuildError,
                "expected one patch location",
            ):
                MODULE._include_android_wrapper_string_header(native_source)

    def test_ffmpegkit_next_bridge_is_repackaged_and_restricted(self):
        with tempfile.TemporaryDirectory(
            prefix="ii-mobile-wrapper-next-test-"
        ) as owned:
            root = Path(owned)
            native_source = root / "native"
            wrapper = root / "wrapper"
            native_source.mkdir()
            java_root = (
                wrapper
                / "android/src/main/java/com/antonkarpenko/ffmpegkit"
            )
            java_root.mkdir(parents=True)
            (java_root / "FFmpegKitConfig.java").write_text(
                "/** Native library callback example: fakeNativeCallback(). */\n"
                + 'private static final String LABEL = "native fakeString(";\n'
                + "\n".join(
                    (
                        f"private static native void {name}();"
                        if index % 2 == 0
                        else f"private native static void {name}();"
                    )
                    for index, name in enumerate(LEGACY_CONFIG_METHODS)
                ),
                encoding="utf-8",
            )
            (java_root / "AbiDetect.java").write_text(
                "// Native docs mention fakeAbiCall().\n"
                + "\n".join(
                    f"static native void {name}();" for name in LEGACY_ABI_METHODS
                ),
                encoding="utf-8",
            )

            def table(name, methods, class_name, *, sized=False):
                entries = []
                for method in methods:
                    entries.append(
                        f'    {{"{method}", "()V",\n'
                        f"     (void *)Java_com_arthenica_ffmpegkit_"
                        f"{class_name}_{method}}},\n"
                    )
                entries[-1] = entries[-1].rstrip()[:-2] + "}};\n"
                count = (
                    f"sizeof({name}) / sizeof({name}[0])"
                    if sized
                    else str(len(methods))
                )
                return (
                    f"JNINativeMethod {name}[] = {{\n"
                    + "".join(entries)
                    + "void load(JNIEnv *env, jclass owner) {\n"
                    + f"  (*env)->RegisterNatives(env, owner, {name}, "
                    + f"{count});\n"
                    + "}\n"
                )

            config = native_source / "ffmpegkit.c"
            config.write_text(
                'const char *name = "com/arthenica/ffmpegkit/FFmpegKitConfig";\n'
                + table(
                    "configMethods",
                    NEXT_CONFIG_METHODS,
                    "FFmpegKitConfig",
                    sized=True,
                ),
                encoding="utf-8",
            )
            abi = native_source / "ffmpegkit_abidetect.c"
            abi.write_text(
                'const char *name = "com/arthenica/ffmpegkit/AbiDetect";\n'
                + table("abiDetectMethods", NEXT_ABI_METHODS, "AbiDetect"),
                encoding="utf-8",
            )
            (native_source / "ffmpegkit.h").write_text(
                "\n".join(
                    "void Java_com_arthenica_ffmpegkit_FFmpegKitConfig_"
                    f"declaration{index}(void);"
                    for index in range(48)
                ),
                encoding="utf-8",
            )

            changed = MODULE.adapt_android_native_bridge(native_source, wrapper)
            self.assertIn(config, changed)
            transformed = config.read_text(encoding="utf-8")
            self.assertIn("com/antonkarpenko/ffmpegkit", transformed)
            self.assertNotIn("com/arthenica/ffmpegkit", transformed)
            for method in LEGACY_CONFIG_METHODS:
                self.assertIn(f'{{"{method}"', transformed)
            for method in set(NEXT_CONFIG_METHODS) - set(LEGACY_CONFIG_METHODS):
                self.assertNotIn(f'{{"{method}"', transformed)
            self.assertIn(
                "RegisterNatives(env, owner, configMethods, "
                "sizeof(configMethods) / sizeof(configMethods[0]))",
                transformed,
            )
            abi_text = abi.read_text(encoding="utf-8")
            self.assertIn('{"getNativeBuildConf"', abi_text)
            self.assertNotIn('{"getNativeMinSdk"', abi_text)
            self.assertIn(
                f"RegisterNatives(env, owner, abiDetectMethods, "
                f"{len(LEGACY_ABI_METHODS)})",
                abi_text,
            )

            with self.assertRaisesRegex(
                MODULE.BuildError,
                "JNI package surface changed",
            ):
                MODULE.adapt_android_native_bridge(native_source, wrapper)

    def test_android_jni_registration_count_must_match_upstream_table(self):
        with tempfile.TemporaryDirectory(
            prefix="ii-mobile-wrapper-registration-count-test-"
        ) as owned:
            implementation = Path(owned) / "ffmpegkit_abidetect.c"
            implementation.write_text(
                "JNINativeMethod abiDetectMethods[] = {\n"
                + "\n".join(
                    f'  {{"{name}", "()V", (void *)method_{index}}},'
                    for index, name in enumerate(NEXT_ABI_METHODS)
                )[:-1]
                + "};\n"
                + "void load(JNIEnv *env, jclass owner) {\n"
                + "  (*env)->RegisterNatives(env, owner, "
                + "abiDetectMethods, 4);\n"
                + "}\n",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(
                MODULE.BuildError,
                "registration count changed unexpectedly",
            ):
                _restrict_registration_table(
                    implementation,
                    "abiDetectMethods",
                    LEGACY_ABI_METHODS,
                    NEXT_ABI_METHODS,
                )

    def test_android_wrapper_jni_declarations_fail_fast(self):
        with tempfile.TemporaryDirectory(
            prefix="ii-mobile-wrapper-jni-test-"
        ) as owned:
            native_source = Path(owned)
            implementation = native_source / "ffmpegkit.c"
            header = native_source / "ffmpegkit.h"
            implementation.write_text(
                "JNINativeMethod methods[] = {\n"
                '  {"run", "()V",\n'
                "   (void *)\n"
                "       Java_example_Config_run}\n"
                "};\n",
                encoding="utf-8",
            )
            header.write_text(
                "JNIEXPORT void JNICALL "
                "Java_example_Config_run(JNIEnv *, jclass);\n",
                encoding="utf-8",
            )
            MODULE._verify_android_wrapper_jni_declarations(native_source)

            header.write_text(
                "JNIEXPORT void JNICALL "
                "Java_other_Config_run(JNIEnv *, jclass);\n",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(
                MODULE.BuildError,
                "lack matching declarations.*Java_example_Config_run",
            ):
                MODULE._verify_android_wrapper_jni_declarations(native_source)


if __name__ == "__main__":
    unittest.main()
