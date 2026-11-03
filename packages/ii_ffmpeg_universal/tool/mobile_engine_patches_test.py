import tempfile
import unittest
from pathlib import Path

import mobile_engine_patches as patches


class MobileEnginePatchesTest(unittest.TestCase):
    def test_local_mobile_generators_check_session_cancellation(self):
        for platform, relative in (
            (
                "android",
                "android/ffmpeg-kit-next-android-lib/src/main/cpp/"
                "fftools/ffmpeg_demux.c",
            ),
            ("ios", "apple/src/fftools/ffmpeg_demux.c"),
        ):
            with self.subTest(platform=platform), tempfile.TemporaryDirectory(
                prefix=f"ii-mobile-cancel-{platform}-patch-test-"
            ) as owned:
                recipe = Path(owned)
                implementation = recipe / relative
                implementation.parent.mkdir(parents=True)
                implementation.write_text(
                    patches.FFMPEG_DEMUX_DECLARATIONS_UPSTREAM
                    + patches.FFMPEG_DEMUX_LOOP_UPSTREAM
                    + "    }\n",
                    encoding="utf-8",
                )

                self.assertEqual(
                    patches.make_mobile_cancellation_cooperative(
                        recipe, platform
                    ),
                    implementation,
                )
                transformed = implementation.read_text(encoding="utf-8")
                self.assertIn(
                    "if (cancelRequested(globalSessionId))", transformed
                )
                self.assertEqual(
                    transformed.count(
                        "extern __thread long globalSessionId;"
                    ),
                    1,
                )
                self.assertEqual(
                    transformed.count(
                        "extern int cancelRequested(long sessionId);"
                    ),
                    1,
                )
                self.assertLess(
                    transformed.index(
                        "extern int cancelRequested(long sessionId);"
                    ),
                    transformed.index(
                        "if (cancelRequested(globalSessionId))"
                    ),
                )
                self.assertLess(
                    transformed.index(
                        "if (cancelRequested(globalSessionId))"
                    ),
                    transformed.index(
                        "ret = av_read_frame(f->ctx, dt.pkt_demux);"
                    ),
                )

                with self.assertRaisesRegex(
                    patches.BuildError, "expected one patch location"
                ):
                    patches.make_mobile_cancellation_cooperative(
                        recipe, platform
                    )

    def test_mobile_cancellation_patch_rejects_changed_include_anchor(self):
        with tempfile.TemporaryDirectory(
            prefix="ii-mobile-cancel-declaration-test-"
        ) as owned:
            recipe = Path(owned)
            implementation = (
                recipe
                / "android/ffmpeg-kit-next-android-lib/src/main/cpp/"
                "fftools/ffmpeg_demux.c"
            )
            implementation.parent.mkdir(parents=True)
            implementation.write_text(
                '#include "libavformat/renamed.h"\n\n'
                + patches.FFMPEG_DEMUX_LOOP_UPSTREAM,
                encoding="utf-8",
            )

            with self.assertRaisesRegex(
                patches.BuildError,
                "expected one patch location",
            ):
                patches.make_mobile_cancellation_cooperative(
                    recipe, "android"
                )

    def test_android_protocol_callbacks_follow_the_protocol_build_flag(self):
        with tempfile.TemporaryDirectory(
            prefix="ii-android-protocol-guard-test-"
        ) as owned:
            native_source = Path(owned)
            (native_source / ".ii-disposable-owner").write_text(
                "ii-ffmpeg-universal:android-protocol-guard-test\n",
                encoding="utf-8",
            )
            implementation = native_source / "ffmpegkit.c"
            implementation.write_text(
                "static void before(void) {}\n"
                + patches.ANDROID_PROTOCOL_CALLBACK_GUARDS[0][0]
                + "    return 0;\n}\n"
                + patches.ANDROID_PROTOCOL_CALLBACK_GUARDS[1][0]
                + "    return 0;\n}\n"
                + patches.ANDROID_PROTOCOL_CALLBACK_GUARDS[2][0]
                + "    return 0;\n}\n"
                + patches.ANDROID_PROTOCOL_CALLBACK_GUARDS[3][0]
                + "static void after(void) {}\n",
                encoding="utf-8",
            )

            self.assertEqual(
                patches.guard_disabled_android_protocol_callbacks(native_source),
                implementation,
            )
            transformed = implementation.read_text(encoding="utf-8")
            self.assertEqual(
                transformed.count("#ifdef USES_FFMPEG_KIT_PROTOCOLS"),
                2,
            )
            self.assertEqual(transformed.count("#endif"), 2)
            self.assertLess(
                transformed.index("#endif"),
                transformed.index("ffkit_stream_write_bytes"),
            )

            with self.assertRaisesRegex(
                patches.BuildError,
                "expected one Android protocol callback guard",
            ):
                patches.guard_disabled_android_protocol_callbacks(native_source)

    def test_meson_cross_files_support_both_pkg_config_keys(self):
        for platform, function_name in (
            ("android", "function-android.sh"),
            ("ios", "function-apple.sh"),
        ):
            with self.subTest(platform=platform), tempfile.TemporaryDirectory(
                prefix=f"ii-meson-{platform}-patch-test-"
            ) as owned:
                recipe = Path(owned)
                function_script = recipe / f"scripts/{function_name}"
                function_script.parent.mkdir(parents=True)
                function_script.write_text(
                    "[binaries]\n"
                    + patches.MESON_PKG_CONFIG_UPSTREAM
                    + "\n[properties]\n",
                    encoding="utf-8",
                )

                self.assertEqual(
                    patches.enable_meson_cross_pkg_config(recipe, platform),
                    function_script,
                )
                transformed = function_script.read_text()
                self.assertIn("pkgconfig = 'pkg-config'", transformed)
                self.assertIn("pkg-config = 'pkg-config'", transformed)

                with self.assertRaisesRegex(
                    patches.BuildError, "expected one patch location"
                ):
                    patches.enable_meson_cross_pkg_config(recipe, platform)

    def test_optional_freetype_brotli_is_removed_for_android_and_ios(self):
        for platform, directory, function_name in (
            ("android", "android", "function-android.sh"),
            ("ios", "apple", "function-apple.sh"),
        ):
            with self.subTest(platform=platform), tempfile.TemporaryDirectory(
                prefix=f"ii-freetype-{platform}-patch-test-"
            ) as owned:
                recipe = Path(owned)
                freetype = recipe / f"scripts/{directory}/freetype.sh"
                main = recipe / f"scripts/main-{platform}.sh"
                shared_function = recipe / "scripts/function.sh"
                platform_function = recipe / f"scripts/{function_name}"
                freetype.parent.mkdir(parents=True)
                main.parent.mkdir(parents=True, exist_ok=True)
                freetype.write_text(
                    "flags\n"
                    + patches.FREETYPE_BROTLI_ENVIRONMENT
                    + "configure\n"
                    + patches.FREETYPE_BROTLI_CONFIGURE_UPSTREAM
                    + "finish\n",
                    encoding="utf-8",
                )
                main.write_text(
                    "case\n"
                    + patches.FREETYPE_LIBJXL_DEPENDENCY_UPSTREAM
                    + "esac\n",
                    encoding="utf-8",
                )
                shared_function.write_text(
                    "case\n"
                    + patches.FREETYPE_LIBJXL_ENABLE_UPSTREAM
                    + "esac\n",
                    encoding="utf-8",
                )
                platform_function.write_text(
                    "Name: FreeType 2\n"
                    + patches.FREETYPE_PACKAGE_CONFIG_UPSTREAM
                    + "Libs: -lfreetype\n",
                    encoding="utf-8",
                )

                transformed = patches.disable_optional_freetype_brotli(
                    recipe, platform
                )

                self.assertEqual(
                    transformed,
                    (freetype, main, shared_function, platform_function),
                )
                freetype_text = freetype.read_text()
                self.assertNotIn("BROTLI_", freetype_text)
                self.assertNotIn("--with-brotli", freetype_text)
                self.assertIn("--without-brotli", freetype_text)
                self.assertNotIn("OK_libjxl", main.read_text())
                self.assertNotIn('set_library "libjxl"', shared_function.read_text())
                package_config = platform_function.read_text()
                self.assertIn("Requires: libpng\n", package_config)
                self.assertNotIn("libpng16", package_config)
                self.assertIn("Requires.private: zlib\n", package_config)
                self.assertNotIn("libbrotlidec", package_config)

                with self.assertRaisesRegex(
                    patches.BuildError, "expected one patch location"
                ):
                    patches.disable_optional_freetype_brotli(recipe, platform)


if __name__ == "__main__":
    unittest.main()
