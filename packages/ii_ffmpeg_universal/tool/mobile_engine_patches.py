#!/usr/bin/env python3
"""Exact, fail-closed source transforms for the mobile engine build."""

import re
from pathlib import Path

from mobile_engine_common import BuildError, replace_once


ANDROID_HOST_TOOLCHAIN_UPSTREAM = """  if [ "$(is_darwin_arm64)" == "1" ]; then
    # NDK DOESNT HAVE AN ARM64 TOOLCHAIN ON DARWIN
    # WE USE x86-64 WITH ROSETTA INSTEAD
    HOST_ARCH=x86_64
  fi
"""
ANDROID_HOST_TOOLCHAIN_PATCHED = """  if [ "$(is_darwin_arm64)" == "1" ]; then
    # NDK DOESNT HAVE AN ARM64 TOOLCHAIN ON DARWIN
    # WE USE x86-64 WITH ROSETTA INSTEAD
    HOST_ARCH=x86_64
  fi

  if [ "${HOST_OS}" == "linux" ] && \
    { [ "${HOST_ARCH}" == "aarch64" ] || [ "${HOST_ARCH}" == "arm64" ]; }; then
    # Android's Linux NDK host tools are published under linux-x86_64 only.
    HOST_ARCH=x86_64
  fi
"""
LIBICONV_DEVELOPER_MANPAGES = """      man/iconv.1.html man/iconv.3.html man/iconv_close.3.html man/iconv_open.3.html man/iconvctl.3.html man/iconv_open_into.3.html \
"""
LIBICONV_HTML_INSTALL = """\tif [ ! -d $(DESTDIR)$(htmldir) ] ; then $(mkinstalldirs) $(DESTDIR)$(htmldir) ; fi
\tbuilddir="`pwd`"; cd $(srcdir) && for f in *.html ; do (cd "$$builddir"; echo $(INSTALL_DATA) $(srcdir)/$$f $(DESTDIR)$(htmldir)/$$f ; $(INSTALL_DATA) $(srcdir)/$$f $(DESTDIR)$(htmldir)/$$f) ; done
"""
LIBUUID_CONFIG_INCLUDE_UPSTREAM = """#define _SVID_SOURCE

#ifdef _WIN32
"""
LIBUUID_CONFIG_INCLUDE_PATCHED = """#define _SVID_SOURCE
#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#ifdef _WIN32
"""
OBSOLETE_POSTPROC_DISABLE = """  --disable-postproc \\
"""
OBSOLETE_EMMS_HEADER_INSTALL = """overwrite_file "${BASEDIR}"/src/ffmpeg/libavutil/x86/emms.h "${FFMPEG_LIBRARY_PATH}"/include/libavutil/x86/emms.h 1>>"${BASEDIR}"/build.log 2>&1
"""
OPTIONAL_EMMS_HEADER_INSTALL = """if [[ -f "${BASEDIR}"/src/ffmpeg/libavutil/x86/emms.h ]]; then
  overwrite_file \\
    "${BASEDIR}"/src/ffmpeg/libavutil/x86/emms.h \\
    "${FFMPEG_LIBRARY_PATH}"/include/libavutil/x86/emms.h \\
    1>>"${BASEDIR}"/build.log 2>&1
fi
"""
X86_64_FFMPEG_CPU_UPSTREAM = """x86-64)
  TARGET_CPU="x86_64"
  TARGET_ARCH="x86_64"
"""
X86_64_FFMPEG_CPU_PATCHED = """x86-64)
  TARGET_CPU="x86-64"
  TARGET_ARCH="x86_64"
"""
ANDROID_FFPROBE_HEADERS_UPSTREAM = """#include <pthread.h>
#include <sys/stat.h>
#include <sys/types.h>
"""
ANDROID_FFPROBE_HEADERS_PATCHED = """#include <pthread.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
"""
ANDROID_PROTOCOL_CALLBACK_GUARDS = (
    (
        "\nstatic int ffkit_memory_open(int64_t id, int flags, void **opaque) {\n",
        "\n#ifdef USES_FFMPEG_KIT_PROTOCOLS\n"
        "static int ffkit_memory_open(int64_t id, int flags, void **opaque) {\n",
    ),
    (
        "\nstatic int ffkit_stream_write_bytes(FFKitStreamResource *resource,\n",
        "\n#endif\n\n"
        "static int ffkit_stream_write_bytes(FFKitStreamResource *resource,\n",
    ),
    (
        "\nstatic int ffkit_stream_read(void *opaque, unsigned char *buf, int size) {\n",
        "\n#ifdef USES_FFMPEG_KIT_PROTOCOLS\n"
        "static int ffkit_stream_read(void *opaque, unsigned char *buf, int size) {\n",
    ),
    (
        "\n/**\n * Used by JNI methods to enable redirection.\n */\n",
        "\n#endif\n\n"
        "/**\n * Used by JNI methods to enable redirection.\n */\n",
    ),
)
ANDROID_NDK_BUILD_UPSTREAM = """    if [[ "$(is_darwin_arm64)" == "1" ]] && [[ $(compare_versions "$DETECTED_NDK_VERSION" "24.0") -lt 1 ]]; then
       arch -x86_64 "${ANDROID_NDK_ROOT}"/ndk-build -B 1>>"${BASEDIR}"/build.log 2>&1
    else
      "${ANDROID_NDK_ROOT}"/ndk-build -B 1>>"${BASEDIR}"/build.log 2>&1
    fi
"""
ANDROID_NDK_BUILD_PATCHED = """    if [[ "$(is_darwin_arm64)" == "1" ]] && [[ $(compare_versions "$DETECTED_NDK_VERSION" "24.0") -lt 1 ]]; then
       arch -x86_64 "${ANDROID_NDK_ROOT}"/ndk-build -B 1>>"${BASEDIR}"/build.log 2>&1
    elif [ "$(uname -s)" == "Linux" ] && \\
      { [ "$(uname -m)" == "aarch64" ] || [ "$(uname -m)" == "arm64" ]; }; then
      host_uname_directory="${BASEDIR}/.tmp/ndk-host-tools"
      real_uname="$(command -v uname)" || exit 1
      mkdir -p "${host_uname_directory}" || exit 1
      printf '%s\\n' \\
        '#!/bin/sh' \\
        'if [ "$#" -eq 1 ] && [ "$1" = "-m" ]; then' \\
        '  printf "%s\\n" x86_64' \\
        'else' \\
        "  exec \\"${real_uname}\\" \\"\\$@\\"" \\
        'fi' \\
        > "${host_uname_directory}/uname" || exit 1
      chmod 700 "${host_uname_directory}/uname" || exit 1
      PATH="${host_uname_directory}:${PATH}" \\
        "${ANDROID_NDK_ROOT}"/ndk-build -B 1>>"${BASEDIR}"/build.log 2>&1
    else
      "${ANDROID_NDK_ROOT}"/ndk-build -B 1>>"${BASEDIR}"/build.log 2>&1
    fi
"""
FREETYPE_BROTLI_ENVIRONMENT = """export BROTLI_CFLAGS="$(pkg-config --cflags libbrotlidec 2>>"${BASEDIR}"/build.log)" || return 1
export BROTLI_LIBS="$(pkg-config --libs --static libbrotlidec 2>>"${BASEDIR}"/build.log)" || return 1
"""
FREETYPE_BROTLI_CONFIGURE_UPSTREAM = """  --with-brotli=yes \\
"""
FREETYPE_BROTLI_CONFIGURE_PATCHED = """  --without-brotli \\
"""
FREETYPE_LIBJXL_DEPENDENCY_UPSTREAM = """    freetype)
      if [[ $OK_libpng -eq 1 ]] && [[ $OK_libjxl -eq 1 ]]; then
        run=1
      fi
      ;;
"""
FREETYPE_LIBJXL_DEPENDENCY_PATCHED = """    freetype)
      if [[ $OK_libpng -eq 1 ]]; then
        run=1
      fi
      ;;
"""
FREETYPE_LIBJXL_ENABLE_UPSTREAM = """  freetype)
    ENABLED_LIBRARIES[LIBRARY_FREETYPE]=$2
    set_virtual_library "zlib" $2
    set_library "libpng" $2
    set_library "libjxl" $2
    ;;
"""
FREETYPE_LIBJXL_ENABLE_PATCHED = """  freetype)
    ENABLED_LIBRARIES[LIBRARY_FREETYPE]=$2
    set_virtual_library "zlib" $2
    set_library "libpng" $2
    ;;
"""
FREETYPE_PACKAGE_CONFIG_UPSTREAM = """Requires: libpng
Requires.private: zlib, libbrotlidec
"""
FREETYPE_PACKAGE_CONFIG_PATCHED = """Requires: libpng
Requires.private: zlib
"""
MESON_PKG_CONFIG_UPSTREAM = """strip = '$STRIP'
pkg-config = 'pkg-config'
"""
MESON_PKG_CONFIG_PATCHED = """strip = '$STRIP'
pkgconfig = 'pkg-config'
pkg-config = 'pkg-config'
"""
FFMPEG_DEMUX_DECLARATIONS_UPSTREAM = """#include "libavformat/avformat.h"

typedef struct DemuxStream {
"""
FFMPEG_DEMUX_DECLARATIONS_CANCELLABLE = """#include "libavformat/avformat.h"

extern __thread long globalSessionId;
extern int cancelRequested(long sessionId);

typedef struct DemuxStream {
"""
FFMPEG_DEMUX_LOOP_UPSTREAM = """    while (1) {
        DemuxStream *ds;
        unsigned send_flags = 0;

        ret = av_read_frame(f->ctx, dt.pkt_demux);
"""
FFMPEG_DEMUX_LOOP_CANCELLABLE = """    while (1) {
        DemuxStream *ds;
        unsigned send_flags = 0;

        /*
         * Local generators such as lavfi do not necessarily enter an
         * interruptible AVIO read. Check FFmpegKit's session-scoped flag at
         * the demux boundary so cancellation can stop client-side renders.
         */
        if (cancelRequested(globalSessionId)) {
            ret = AVERROR_EXIT;
            break;
        }

        ret = av_read_frame(f->ctx, dt.pkt_demux);
"""


def strip_libiconv_developer_manpages(source: Path) -> tuple[Path, Path]:
    """Remove undeclared developer-doc generation and installation inputs."""
    developer_makefile = source / "Makefile.devel"
    install_makefile = source / "man/Makefile.in"
    replace_once(developer_makefile, LIBICONV_DEVELOPER_MANPAGES, "")
    replace_once(install_makefile, LIBICONV_HTML_INSTALL, "")
    return developer_makefile, install_makefile


def include_libuuid_config_header(source: Path) -> Path:
    """Make libuuid consume the feature checks generated by configure."""
    implementation = source / "gen_uuid.c"
    replace_once(
        implementation,
        LIBUUID_CONFIG_INCLUDE_UPSTREAM,
        LIBUUID_CONFIG_INCLUDE_PATCHED,
    )
    return implementation


def strip_obsolete_postproc_disable(engine_script: Path) -> Path:
    """Remove the libpostproc switch deleted by the locked FFmpeg release."""
    replace_once(engine_script, OBSOLETE_POSTPROC_DISABLE, "")
    return engine_script


def make_removed_emms_header_optional(engine_script: Path) -> Path:
    """Do not install the x86 emms.h header removed by locked FFmpeg 8."""
    replace_once(
        engine_script,
        OBSOLETE_EMMS_HEADER_INSTALL,
        OPTIONAL_EMMS_HEADER_INSTALL,
    )
    return engine_script


def repair_x86_64_ffmpeg_cpu(engine_script: Path) -> Path:
    """Use Clang's valid x86-64 CPU spelling while retaining FFmpeg's arch."""
    replace_once(
        engine_script,
        X86_64_FFMPEG_CPU_UPSTREAM,
        X86_64_FFMPEG_CPU_PATCHED,
    )
    return engine_script


def verify_android_wrapper_jni_declarations(native_source: Path) -> None:
    """Fail before compilation when JNI registration and headers disagree."""
    implementation = (native_source / "ffmpegkit.c").read_text(encoding="utf-8")
    registered = set(
        re.findall(
            r"\(void\s*\*\)\s*(Java_[A-Za-z0-9_]+)",
            implementation,
        )
    )
    declarations = "\n".join(
        header.read_text(encoding="utf-8")
        for header in sorted(native_source.glob("*.h"))
    )
    missing = sorted(
        symbol
        for symbol in registered
        if re.search(rf"\b{re.escape(symbol)}\s*\(", declarations) is None
    )
    if not registered:
        raise BuildError("Android wrapper registered no JNI methods")
    if missing:
        raise BuildError(
            "Android wrapper JNI methods lack matching declarations: "
            + ", ".join(missing)
        )


def include_android_wrapper_string_header(native_source: Path) -> Path:
    """Declare the C string functions used by the locked FFprobe wrapper."""
    implementation = native_source / "ffprobekit.c"
    replace_once(
        implementation,
        ANDROID_FFPROBE_HEADERS_UPSTREAM,
        ANDROID_FFPROBE_HEADERS_PATCHED,
    )
    return implementation


def guard_disabled_android_protocol_callbacks(native_source: Path) -> Path:
    """Do not compile protocol-only callbacks when their FFmpeg hooks are off."""
    implementation = native_source / "ffmpegkit.c"
    text = implementation.read_text(encoding="utf-8")
    for upstream, guarded in ANDROID_PROTOCOL_CALLBACK_GUARDS:
        if guarded in text or text.count(upstream) != 1:
            raise BuildError(
                f"expected one Android protocol callback guard in "
                f"{implementation}: {upstream!r}"
            )
    for upstream, guarded in ANDROID_PROTOCOL_CALLBACK_GUARDS:
        text = text.replace(upstream, guarded)
    implementation.write_text(text, encoding="utf-8")
    return implementation


def support_linux_arm_ndk_build(android_script: Path) -> Path:
    """Select the published Linux x86_64 NDK host tools on Linux ARM."""
    replace_once(
        android_script,
        ANDROID_NDK_BUILD_UPSTREAM,
        ANDROID_NDK_BUILD_PATCHED,
    )
    return android_script


def disable_optional_freetype_brotli(
    recipe: Path, platform: str
) -> tuple[Path, Path, Path, Path]:
    """Keep FreeType's optional Brotli/libjxl tree out of the locked build."""
    platform_directory = "android" if platform == "android" else "apple"
    freetype_script = recipe / "scripts" / platform_directory / "freetype.sh"
    main_script = recipe / "scripts" / f"main-{platform}.sh"
    shared_function_script = recipe / "scripts/function.sh"
    platform_function = (
        recipe / "scripts/function-android.sh"
        if platform == "android"
        else recipe / "scripts/function-apple.sh"
    )
    replace_once(freetype_script, FREETYPE_BROTLI_ENVIRONMENT, "")
    replace_once(
        freetype_script,
        FREETYPE_BROTLI_CONFIGURE_UPSTREAM,
        FREETYPE_BROTLI_CONFIGURE_PATCHED,
    )
    replace_once(
        main_script,
        FREETYPE_LIBJXL_DEPENDENCY_UPSTREAM,
        FREETYPE_LIBJXL_DEPENDENCY_PATCHED,
    )
    replace_once(
        shared_function_script,
        FREETYPE_LIBJXL_ENABLE_UPSTREAM,
        FREETYPE_LIBJXL_ENABLE_PATCHED,
    )
    replace_once(
        platform_function,
        FREETYPE_PACKAGE_CONFIG_UPSTREAM,
        FREETYPE_PACKAGE_CONFIG_PATCHED,
    )
    return (
        freetype_script,
        main_script,
        shared_function_script,
        platform_function,
    )


def enable_meson_cross_pkg_config(recipe: Path, platform: str) -> Path:
    """Support dependency lookup on both old and new locked Meson versions."""
    function_script = (
        recipe / "scripts/function-android.sh"
        if platform == "android"
        else recipe / "scripts/function-apple.sh"
    )
    replace_once(
        function_script,
        MESON_PKG_CONFIG_UPSTREAM,
        MESON_PKG_CONFIG_PATCHED,
    )
    return function_script


def make_mobile_cancellation_cooperative(recipe: Path, platform: str) -> Path:
    """Check FFmpegKit cancellation for local generators without AVIO reads."""
    implementation = (
        recipe
        / (
            "android/ffmpeg-kit-next-android-lib/src/main/cpp/"
            "fftools/ffmpeg_demux.c"
            if platform == "android"
            else "apple/src/fftools/ffmpeg_demux.c"
        )
    )
    replace_once(
        implementation,
        FFMPEG_DEMUX_DECLARATIONS_UPSTREAM,
        FFMPEG_DEMUX_DECLARATIONS_CANCELLABLE,
    )
    replace_once(
        implementation,
        FFMPEG_DEMUX_LOOP_UPSTREAM,
        FFMPEG_DEMUX_LOOP_CANCELLABLE,
    )
    return implementation
