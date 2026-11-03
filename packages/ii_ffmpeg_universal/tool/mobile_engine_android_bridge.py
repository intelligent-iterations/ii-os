"""Fail-closed Android bridge adaptation for FFmpegKitNext."""

from __future__ import annotations

import re
import xml.etree.ElementTree as ET
from pathlib import Path

from mobile_engine_common import BuildError


LEGACY_CONFIG_METHODS = (
    "enableNativeRedirection",
    "disableNativeRedirection",
    "setNativeLogLevel",
    "getNativeLogLevel",
    "getNativeFFmpegVersion",
    "getNativeVersion",
    "nativeFFmpegExecute",
    "nativeFFmpegCancel",
    "nativeFFprobeExecute",
    "registerNewNativeFFmpegPipe",
    "getNativeBuildDate",
    "setNativeEnvironmentVariable",
    "ignoreNativeSignal",
    "messagesInTransmit",
)
NEXT_CONFIG_METHODS = (
    *LEGACY_CONFIG_METHODS[:6],
    "getNativePackageName",
    *LEGACY_CONFIG_METHODS[6:],
    "registerNativeFFmpegKitInputBuffer",
    "registerNativeFFmpegKitInputDirectBuffer",
    "registerNativeFFmpegKitOutputBuffer",
    "getNativeFFmpegKitBufferSize",
    "getNativeFFmpegKitOutputBuffer",
    "getNativeFFmpegKitOutputBufferDirect",
    "unregisterNativeFFmpegKitBuffer",
    "registerNativeFFmpegKitStream",
    "nativeFFmpegKitStreamWrite",
    "nativeFFmpegKitStreamRead",
    "nativeFFmpegKitStreamCloseInput",
    "unregisterNativeFFmpegKitStream",
)
LEGACY_ABI_METHODS = (
    "getNativeAbi",
    "getNativeCpuAbi",
    "isNativeLTSBuild",
    "getNativeBuildConf",
)
NEXT_ABI_METHODS = (*LEGACY_ABI_METHODS, "getNativeMinSdk")

_UPSTREAM_CLASS_PATH = "com/arthenica/ffmpegkit"
_LEGACY_CLASS_PATH = "com/antonkarpenko/ffmpegkit"
_LEGACY_JAVA_PACKAGE = _LEGACY_CLASS_PATH.replace("/", ".")
_UPSTREAM_SYMBOL = "Java_com_arthenica_ffmpegkit_"
_LEGACY_SYMBOL = "Java_com_antonkarpenko_ffmpegkit_"
_JAVA_METHOD_MODIFIER = (
    r"(?:public|protected|private|static|final|synchronized|strictfp)"
)
_JAVA_NATIVE_METHOD = re.compile(
    rf"(?m)^[ \t]*(?:{_JAVA_METHOD_MODIFIER}[ \t]+)*"
    rf"native[ \t]+(?:{_JAVA_METHOD_MODIFIER}[ \t]+)*"
    r"[A-Za-z_$][A-Za-z0-9_$.]*"
    r"(?:[ \t]*<[^;\n{}()]*>)?(?:[ \t]*\[\])*[ \t]+"
    r"([A-Za-z_$][A-Za-z0-9_$]*)[ \t]*\("
)
_ANDROID_XML_NAMESPACE = "http://schemas.android.com/apk/res/android"
_JAVA_PACKAGE = re.compile(
    r"^[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)+$"
)


def _parse_build_manifest(path: Path) -> ET.ElementTree:
    """Parse a build-owned Android manifest with every DTD rejected up front.

    The file is generated inside the wrapper this tool controls, never fetched;
    refusing DOCTYPE and ENTITY declarations leaves nothing for an entity
    expansion or external-entity attack to use.
    """
    data = path.read_bytes()
    if b"<!DOCTYPE" in data or b"<!ENTITY" in data:
        raise BuildError(f"Android wrapper manifest must not declare a DTD: {path}")
    root = ET.fromstring(data)  # nosemgrep: python.lang.security.use-defused-xml-parse.use-defused-xml-parse -- build-owned file; DTDs rejected above
    return ET.ElementTree(root)


def adapt_android_wrapper_manifest(wrapper: Path, package: str) -> Path:
    """Bind the offline AAR manifest to its locked binary-only namespace."""
    if _JAVA_PACKAGE.fullmatch(package) is None:
        raise BuildError(f"invalid Android wrapper package: {package!r}")
    if package == _LEGACY_JAVA_PACKAGE:
        raise BuildError(
            "Android binary package collides with the Flutter plugin namespace"
        )
    manifest = wrapper / "android/src/main/AndroidManifest.xml"
    if not manifest.is_file() or manifest.is_symlink():
        raise BuildError(f"unsafe Android wrapper manifest: {manifest}")
    try:
        tree = _parse_build_manifest(manifest)
    except ET.ParseError as error:
        raise BuildError("Android wrapper manifest is malformed") from error
    root = tree.getroot()
    current = root.attrib.get("package")
    if root.tag != "manifest" or current not in (None, "", package):
        raise BuildError(
            f"Android wrapper manifest namespace changed: {current!r}"
        )
    root.set("package", package)
    ET.register_namespace("android", _ANDROID_XML_NAMESPACE)
    manifest.write_text(
        ET.tostring(root, encoding="unicode", short_empty_elements=True) + "\n",
        encoding="utf-8",
    )
    try:
        written = _parse_build_manifest(manifest).getroot()
    except ET.ParseError as error:
        raise BuildError("adapted Android wrapper manifest is malformed") from error
    if written.tag != "manifest" or written.attrib.get("package") != package:
        raise BuildError("Android wrapper manifest adaptation failed")
    return manifest


def _restrict_registration_table(
    implementation: Path,
    table_name: str,
    allowed: tuple[str, ...],
    expected: tuple[str, ...],
) -> None:
    text = implementation.read_text(encoding="utf-8")
    marker = f"JNINativeMethod {table_name}[] = {{"
    start = text.find(marker)
    if start < 0 or text.find(marker, start + 1) >= 0:
        raise BuildError(f"expected one Android JNI table: {table_name}")
    line_start = text.rfind("\n", 0, start) + 1
    lines = text[line_start:].splitlines(keepends=True)
    entries: list[tuple[str, list[str]]] = []
    table_end = None
    current: list[str] = []
    current_name = ""
    for index, line in enumerate(lines[1:], start=1):
        stripped = line.lstrip()
        if not current and stripped.startswith('{"'):
            match = re.match(r'\{"([^"]+)"', stripped)
            if match is None:
                raise BuildError(f"invalid Android JNI entry in {table_name}")
            current_name = match.group(1)
            current = [line]
        elif current:
            current.append(line)
        if current and line.rstrip().endswith(("},", "}};")):
            entries.append((current_name, current))
            if line.rstrip().endswith("}};"):
                table_end = index + 1
                break
            current = []
            current_name = ""
    if table_end is None or tuple(name for name, _ in entries) != expected:
        raise BuildError(f"Android JNI table changed unexpectedly: {table_name}")
    retained = [lines[0]]
    for name, entry in entries:
        if name in allowed:
            retained.extend(entry)
    final = retained[-1]
    if not final.rstrip().endswith("},"):
        raise BuildError(f"Android JNI retained table is malformed: {table_name}")
    retained[-1] = final.rstrip()[:-2] + "}};\n"
    replacement = "".join(retained)
    prefix = text[:line_start]
    suffix = "".join(lines[table_end:])
    updated = prefix + replacement + suffix
    fixed_registration = re.compile(
        rf"((?:\(\*env\)->)?RegisterNatives\s*\(\s*env\s*,\s*"
        rf"[A-Za-z_][A-Za-z0-9_]*\s*,\s*{re.escape(table_name)}\s*,\s*)"
        r"([0-9]+)(\s*\))"
    )
    sized_registration = re.compile(
        rf"(?:\(\*env\)->)?RegisterNatives\s*\(\s*env\s*,\s*"
        rf"[A-Za-z_][A-Za-z0-9_]*\s*,\s*{re.escape(table_name)}\s*,\s*"
        rf"sizeof\(\s*{re.escape(table_name)}\s*\)\s*/\s*"
        rf"sizeof\(\s*{re.escape(table_name)}\s*\[\s*0\s*\]\s*\)\s*\)"
    )
    fixed_matches = tuple(fixed_registration.finditer(updated))
    sized_matches = tuple(sized_registration.finditer(updated))
    if len(fixed_matches) + len(sized_matches) != 1:
        raise BuildError(
            f"Android JNI registration count changed unexpectedly: {table_name}"
        )
    if fixed_matches:
        if int(fixed_matches[0].group(2)) != len(expected):
            raise BuildError(
                "Android JNI registration count changed unexpectedly: "
                f"{table_name}"
            )
        updated = fixed_registration.sub(
            rf"\g<1>{len(allowed)}\g<3>",
            updated,
            count=1,
        )
    implementation.write_text(updated, encoding="utf-8")


def _verify_legacy_java_methods(
    wrapper: Path, relative: str, expected: tuple[str, ...]
) -> None:
    source = wrapper / relative
    text = source.read_text(encoding="utf-8")
    methods = tuple(match.group(1) for match in _JAVA_NATIVE_METHOD.finditer(text))
    if set(methods) != set(expected) or len(methods) != len(expected):
        raise BuildError(f"legacy Android Java native methods changed: {relative}")


def adapt_android_native_bridge(
    native_source: Path, wrapper: Path
) -> list[Path]:
    """Repackage FFmpegKitNext JNI for the locked legacy Flutter bridge."""
    _verify_legacy_java_methods(
        wrapper,
        "android/src/main/java/com/antonkarpenko/ffmpegkit/FFmpegKitConfig.java",
        LEGACY_CONFIG_METHODS,
    )
    _verify_legacy_java_methods(
        wrapper,
        "android/src/main/java/com/antonkarpenko/ffmpegkit/AbiDetect.java",
        LEGACY_ABI_METHODS,
    )
    changed: list[Path] = []
    class_paths = 0
    symbols = 0
    for source in sorted((*native_source.rglob("*.c"), *native_source.rglob("*.h"))):
        if not source.is_file() or source.is_symlink():
            raise BuildError(f"unsafe Android native bridge input: {source}")
        text = source.read_text(encoding="utf-8")
        class_paths += text.count(_UPSTREAM_CLASS_PATH)
        symbols += text.count(_UPSTREAM_SYMBOL)
        updated = text.replace(_UPSTREAM_CLASS_PATH, _LEGACY_CLASS_PATH).replace(
            _UPSTREAM_SYMBOL, _LEGACY_SYMBOL
        )
        if updated != text:
            source.write_text(updated, encoding="utf-8")
            changed.append(source)
    if class_paths != 2 or symbols < 40:
        raise BuildError("FFmpegKitNext Android JNI package surface changed")
    config = native_source / "ffmpegkit.c"
    abi = native_source / "ffmpegkit_abidetect.c"
    _restrict_registration_table(
        config, "configMethods", LEGACY_CONFIG_METHODS, NEXT_CONFIG_METHODS
    )
    _restrict_registration_table(
        abi, "abiDetectMethods", LEGACY_ABI_METHODS, NEXT_ABI_METHODS
    )
    changed.extend((config, abi))
    for source in changed:
        text = source.read_text(encoding="utf-8")
        if _UPSTREAM_CLASS_PATH in text or _UPSTREAM_SYMBOL in text:
            raise BuildError(f"Android JNI package adaptation incomplete: {source}")
    return sorted(set(changed))
