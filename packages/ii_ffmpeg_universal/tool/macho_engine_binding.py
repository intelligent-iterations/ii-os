"""Bind packaged Mach-O loadable code and data to reviewed source slices."""

from __future__ import annotations

import hashlib
import json
import struct

from mobile_binary_closure import BinaryClosureError, macho_dynamic_closure


class MachOBindingError(RuntimeError):
    """The packaged Mach-O is malformed or is not derived from the source."""


FAT_MAGICS = {0xCAFEBABE: 20, 0xCAFEBABF: 32}
THIN_MAGICS = {0xFEEDFACE: 28, 0xFEEDFACF: 32}
LC_SEGMENT_64 = 0x19
MAX_MACHO_BYTES = 512 * 1024 * 1024
MAX_SLICES = 64
MAX_COMMANDS = 65_536
MAX_SECTIONS = 65_536
ZEROFILL_SECTION_TYPES = {0x1, 0xC, 0x12}


def _unpack(format_string: str, value: bytes, offset: int, description: str):
    size = struct.calcsize(format_string)
    if offset < 0 or offset + size > len(value):
        raise MachOBindingError(f"truncated {description}")
    return struct.unpack_from(format_string, value, offset)


def _name(value: bytes, description: str) -> str:
    try:
        return value.split(b"\0", 1)[0].decode("ascii")
    except UnicodeDecodeError as error:
        raise MachOBindingError(f"invalid Mach-O name: {description}") from error


def _raw_slices(value: bytes, description: str) -> list[bytes]:
    if not 8 <= len(value) <= MAX_MACHO_BYTES:
        raise MachOBindingError(f"invalid Mach-O size: {description}")
    magic = struct.unpack_from(">I", value)[0]
    entry_size = FAT_MAGICS.get(magic)
    if entry_size is None:
        return [value]
    count = _unpack(">I", value, 4, "fat Mach-O count")[0]
    if count <= 0 or count > MAX_SLICES or 8 + count * entry_size > len(value):
        raise MachOBindingError(f"invalid fat Mach-O table: {description}")
    result: list[bytes] = []
    occupied: list[tuple[int, int]] = []
    for index in range(count):
        entry = 8 + index * entry_size
        format_string = ">II" if entry_size == 20 else ">QQ"
        offset, size = _unpack(format_string, value, entry + 8, "fat Mach-O slice")
        end = offset + size
        overlap = any(offset < stop and start < end for start, stop in occupied)
        if size <= 0 or end > len(value) or overlap:
            raise MachOBindingError(f"invalid fat Mach-O slice: {description}")
        occupied.append((offset, end))
        result.append(value[offset:end])
    return result


def _loadable_image(value: bytes, description: str) -> tuple[str, str]:
    if len(value) < 32 or struct.unpack_from("<I", value)[0] not in THIN_MAGICS:
        raise MachOBindingError(f"unsupported Mach-O slice: {description}")
    _, _, file_type, command_count, command_bytes, flags = _unpack(
        "<iiIIII", value, 4, "Mach-O header"
    )
    if command_count > MAX_COMMANDS or command_bytes > len(value) - 32:
        raise MachOBindingError(f"invalid Mach-O load commands: {description}")
    commands_end = 32 + command_bytes
    cursor = 32
    segments: list[dict[str, object]] = []
    section_count = 0
    for _ in range(command_count):
        command, size = _unpack("<II", value, cursor, "Mach-O load command")
        if size < 8 or size % 4 or cursor + size > commands_end:
            raise MachOBindingError(f"invalid Mach-O load command: {description}")
        if command & 0x7FFFFFFF == LC_SEGMENT_64:
            if size < 72:
                raise MachOBindingError(f"invalid Mach-O segment: {description}")
            values = _unpack(
                "<16sQQQQiiII", value, cursor + 8, "Mach-O segment"
            )
            (
                raw_name,
                vm_address,
                vm_size,
                _,
                _,
                maximum,
                initial,
                count,
                segment_flags,
            ) = values
            section_count += count
            if section_count > MAX_SECTIONS or size != 72 + count * 80:
                raise MachOBindingError(f"invalid Mach-O section table: {description}")
            segment_name = _name(raw_name, description)
            sections: list[dict[str, object]] = []
            for index in range(count):
                section = cursor + 72 + index * 80
                fields = _unpack(
                    "<16s16sQQIIIIIIII", value, section, "Mach-O section"
                )
                (
                    raw_section,
                    raw_segment,
                    address,
                    length,
                    offset,
                    align,
                    _,
                    _,
                    section_flags,
                    _,
                    _,
                    _,
                ) = fields
                if _name(raw_segment, description) != segment_name:
                    raise MachOBindingError(
                        f"Mach-O section segment mismatch: {description}"
                    )
                section_type = section_flags & 0xFF
                if section_type in ZEROFILL_SECTION_TYPES:
                    digest = None
                else:
                    if offset + length > len(value):
                        raise MachOBindingError(
                            f"Mach-O section escapes slice: {description}"
                        )
                    digest = hashlib.sha256(
                        value[offset : offset + length]
                    ).hexdigest()
                sections.append(
                    {
                        "name": _name(raw_section, description),
                        "address": address,
                        "size": length,
                        "align": align,
                        "flags": section_flags,
                        "sha256": digest,
                    }
                )
            if segment_name != "__LINKEDIT":
                segments.append(
                    {
                        "name": segment_name,
                        "vm_address": vm_address,
                        "vm_size": vm_size,
                        "maximum_protection": maximum,
                        "initial_protection": initial,
                        "flags": segment_flags,
                        "sections": sections,
                    }
                )
        cursor += size
    if cursor != commands_end or not segments:
        raise MachOBindingError(f"incomplete Mach-O loadable image: {description}")
    try:
        closure = macho_dynamic_closure(value, description)
    except BinaryClosureError as error:
        raise MachOBindingError(str(error)) from error
    if len(closure) != 1:
        raise MachOBindingError(f"ambiguous Mach-O architecture: {description}")
    architecture = next(iter(closure))
    image = {
        "file_type": file_type,
        "flags": flags,
        "closure": closure[architecture],
        "segments": segments,
    }
    encoded = json.dumps(image, separators=(",", ":"), sort_keys=True).encode()
    return architecture, hashlib.sha256(encoded).hexdigest()


def loadable_macho_slices(value: bytes, description: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for raw in _raw_slices(value, description):
        architecture, digest = _loadable_image(raw, description)
        if architecture in result:
            raise MachOBindingError(f"duplicate Mach-O architecture: {description}")
        result[architecture] = digest
    return result


def require_packaged_macho_matches(
    source: bytes, packaged: bytes, description: str
) -> None:
    expected = loadable_macho_slices(source, f"{description} source")
    actual = loadable_macho_slices(packaged, f"{description} packaged")
    if not actual or not set(actual).issubset(expected):
        raise MachOBindingError(f"packaged Mach-O architecture differs: {description}")
    differs = any(
        expected[architecture] != digest
        for architecture, digest in actual.items()
    )
    if differs:
        raise MachOBindingError(
            f"packaged Mach-O loadable image differs: {description}"
        )
