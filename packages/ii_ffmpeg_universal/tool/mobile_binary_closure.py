"""Bounded ELF and Mach-O dynamic-link closure inspection."""

from __future__ import annotations

import struct
from typing import Any


class BinaryClosureError(ValueError):
    pass


def _unpack(fmt: str, data: bytes, offset: int, description: str) -> tuple[Any, ...]:
    size = struct.calcsize(fmt)
    if offset < 0 or offset + size > len(data):
        raise BinaryClosureError(f"truncated {description}")
    return struct.unpack_from(fmt, data, offset)


def _cstring(data: bytes, offset: int, limit: int, description: str) -> str:
    if offset < 0 or offset >= limit or limit > len(data):
        raise BinaryClosureError(f"invalid {description} offset")
    end = data.find(b"\0", offset, limit)
    if end < 0 or end - offset > 1024:
        raise BinaryClosureError(f"unterminated {description}")
    try:
        value = data[offset:end].decode("utf-8")
    except UnicodeDecodeError as error:
        raise BinaryClosureError(f"non-UTF-8 {description}") from error
    if not value or any(ord(character) < 32 for character in value):
        raise BinaryClosureError(f"unsafe {description}")
    return value


def elf_dynamic_closure(data: bytes, member: str) -> dict[str, Any]:
    if len(data) < 52 or data[:4] != b"\x7fELF" or data[5] != 1:
        raise BinaryClosureError(f"invalid little-endian ELF: {member}")
    elf_class = data[4]
    if elf_class == 1:
        phoff = _unpack("<I", data, 28, "ELF program offset")[0]
        phentsize, phnum = _unpack("<HH", data, 42, "ELF program count")
        expected_size = 32
    elif elf_class == 2:
        phoff = _unpack("<Q", data, 32, "ELF program offset")[0]
        phentsize, phnum = _unpack("<HH", data, 54, "ELF program count")
        expected_size = 56
    else:
        raise BinaryClosureError(f"unsupported ELF class: {member}")
    if phnum <= 0 or phnum > 4096 or phentsize < expected_size:
        raise BinaryClosureError(f"invalid ELF program table: {member}")

    loads: list[tuple[int, int, int]] = []
    dynamic: tuple[int, int] | None = None
    for index in range(phnum):
        offset = phoff + index * phentsize
        if elf_class == 1:
            kind, file_offset, address = _unpack(
                "<III", data, offset, "ELF32 program header"
            )
            file_size = _unpack("<I", data, offset + 16, "ELF32 program size")[0]
        else:
            kind = _unpack("<I", data, offset, "ELF64 program type")[0]
            file_offset, address = _unpack(
                "<QQ", data, offset + 8, "ELF64 program address"
            )
            file_size = _unpack("<Q", data, offset + 32, "ELF64 program size")[0]
        if file_offset + file_size > len(data):
            raise BinaryClosureError(f"ELF segment escapes file: {member}")
        if kind == 1:
            loads.append((address, file_offset, file_size))
        elif kind == 2:
            if dynamic is not None:
                raise BinaryClosureError(f"multiple ELF dynamic tables: {member}")
            dynamic = (file_offset, file_size)
    if dynamic is None or not loads:
        raise BinaryClosureError(f"ELF dynamic closure is missing: {member}")

    tags: dict[int, list[int]] = {}
    entry_size = 8 if elf_class == 1 else 16
    tag_format = "<iI" if elf_class == 1 else "<qQ"
    dynamic_offset, dynamic_size = dynamic
    if dynamic_size % entry_size != 0 or dynamic_size // entry_size > 65536:
        raise BinaryClosureError(f"invalid ELF dynamic table size: {member}")
    for offset in range(dynamic_offset, dynamic_offset + dynamic_size, entry_size):
        tag, value = _unpack(tag_format, data, offset, "ELF dynamic entry")
        if tag == 0:
            break
        tags.setdefault(tag, []).append(value)
    if len(tags.get(5, [])) != 1 or len(tags.get(10, [])) != 1:
        raise BinaryClosureError(f"ELF string table is ambiguous: {member}")
    string_address = tags[5][0]
    string_size = tags[10][0]
    string_offset = None
    for address, file_offset, file_size in loads:
        if address <= string_address and string_address + string_size <= address + file_size:
            string_offset = file_offset + string_address - address
            break
    if string_offset is None or string_offset + string_size > len(data):
        raise BinaryClosureError(f"ELF string table escapes a load segment: {member}")

    def values(tag: int, name: str) -> list[str]:
        return [
            _cstring(data, string_offset + value, string_offset + string_size, name)
            for value in tags.get(tag, [])
        ]

    rpaths = values(15, "ELF rpath") + values(29, "ELF runpath")
    if rpaths:
        raise BinaryClosureError(f"ELF runtime search paths are forbidden: {member}")
    needed = values(1, "ELF dependency")
    filters = values(0x7FFFFFFF, "ELF filter dependency")
    auxiliary = values(0x7FFFFFFD, "ELF auxiliary dependency")
    loader_edges = needed + filters + auxiliary
    if len(loader_edges) != len(set(loader_edges)):
        raise BinaryClosureError(f"duplicate ELF loader dependency: {member}")
    sonames = values(14, "ELF soname")
    if len(sonames) > 1:
        raise BinaryClosureError(f"ambiguous ELF soname: {member}")
    return {
        "auxiliary": sorted(auxiliary),
        "filters": sorted(filters),
        "needed": sorted(needed),
        "soname": sonames[0] if sonames else "",
    }


def _macho_slices(data: bytes, member: str) -> list[tuple[int, int]]:
    if len(data) < 8:
        raise BinaryClosureError(f"truncated Mach-O: {member}")
    magic = struct.unpack_from(">I", data, 0)[0]
    if magic not in {0xCAFEBABE, 0xCAFEBABF}:
        return [(0, len(data))]
    count = _unpack(">I", data, 4, "fat Mach-O count")[0]
    entry_size = 20 if magic == 0xCAFEBABE else 32
    if count <= 0 or count > 64 or 8 + count * entry_size > len(data):
        raise BinaryClosureError(f"invalid fat Mach-O table: {member}")
    result = []
    for index in range(count):
        entry = 8 + index * entry_size
        if entry_size == 20:
            offset, size = _unpack(">II", data, entry + 8, "fat Mach-O slice")
        else:
            offset, size = _unpack(">QQ", data, entry + 8, "fat64 Mach-O slice")
        if size <= 0 or offset + size > len(data):
            raise BinaryClosureError(f"Mach-O slice escapes file: {member}")
        result.append((offset, size))
    return result


def _packed_version(value: int) -> str:
    return f"{value >> 16}.{(value >> 8) & 0xFF}.{value & 0xFF}"


def macho_dynamic_closure(data: bytes, member: str) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for slice_offset, slice_size in _macho_slices(data, member):
        limit = slice_offset + slice_size
        magic = _unpack("<I", data, slice_offset, "Mach-O magic")[0]
        if magic not in {0xFEEDFACE, 0xFEEDFACF}:
            raise BinaryClosureError(f"unsupported Mach-O slice: {member}")
        is_64 = magic == 0xFEEDFACF
        cpu_type, cpu_subtype, _, command_count, command_bytes = _unpack(
            "<iiIII", data, slice_offset + 4, "Mach-O header"
        )
        header_size = 32 if is_64 else 28
        commands = slice_offset + header_size
        if (
            command_count > 65536
            or command_bytes > slice_size - header_size
            or commands + command_bytes > limit
        ):
            raise BinaryClosureError(f"invalid Mach-O load commands: {member}")
        architecture = _macho_architecture(cpu_type, cpu_subtype)
        dependencies: list[str] = []
        rpaths: list[str] = []
        platform = None
        minimum = None
        cursor = commands
        for _ in range(command_count):
            command, size = _unpack("<II", data, cursor, "Mach-O load command")
            if size < 8 or size % 4 or cursor + size > commands + command_bytes:
                raise BinaryClosureError(f"invalid Mach-O command size: {member}")
            base_command = command & 0x7FFFFFFF
            if base_command in {0xC, 0x18, 0x1F, 0x20, 0x23}:
                name_offset = _unpack(
                    "<I", data, cursor + 8, "Mach-O dependency offset"
                )[0]
                dependencies.append(
                    _cstring(data, cursor + name_offset, cursor + size, "Mach-O dependency")
                )
            elif base_command == 0x1C:
                name_offset = _unpack("<I", data, cursor + 8, "Mach-O rpath offset")[0]
                rpaths.append(
                    _cstring(data, cursor + name_offset, cursor + size, "Mach-O rpath")
                )
            elif base_command == 0x32:
                platform_value, minimum_value = _unpack(
                    "<II", data, cursor + 8, "Mach-O build version"
                )
                if platform is not None:
                    raise BinaryClosureError(f"duplicate Mach-O build version: {member}")
                platform = {2: "ios", 7: "ios-simulator"}.get(platform_value)
                minimum = _packed_version(minimum_value)
            elif base_command == 0x25:
                minimum_value = _unpack(
                    "<I", data, cursor + 8, "Mach-O minimum iOS version"
                )[0]
                if platform is not None:
                    raise BinaryClosureError(f"duplicate Mach-O minimum version: {member}")
                platform = "ios"
                minimum = _packed_version(minimum_value)
            cursor += size
        if cursor != commands + command_bytes or platform is None or minimum is None:
            raise BinaryClosureError(f"Mach-O deployment target is missing: {member}")
        if rpaths:
            raise BinaryClosureError(f"Mach-O runtime search paths are forbidden: {member}")
        if len(dependencies) != len(set(dependencies)):
            raise BinaryClosureError(f"duplicate Mach-O dependency: {member}")
        if architecture in result:
            raise BinaryClosureError(f"duplicate Mach-O architecture closure: {member}")
        result[architecture] = {
            "dependencies": sorted(dependencies),
            "minimum_version": minimum,
            "platform": platform,
        }
    return result


def _macho_architecture(cpu_type: int, cpu_subtype: int) -> str:
    identity = (cpu_type, cpu_subtype & 0x00FFFFFF)
    names = {
        (0x0100000C, 0): "arm64",
        (0x0100000C, 2): "arm64e",
        (0x01000007, 3): "x86_64",
    }
    try:
        return names[identity]
    except KeyError as error:
        raise BinaryClosureError(f"unsupported Mach-O architecture: {identity}") from error
