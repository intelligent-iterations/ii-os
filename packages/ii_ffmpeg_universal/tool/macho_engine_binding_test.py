from __future__ import annotations

import struct
import unittest

from macho_engine_binding import MachOBindingError, loadable_macho_slices


def thin_macho(cpu_subtype: int, payload: bytes, linkedit: bytes) -> bytes:
    header_size = 32
    text_command_size = 72 + 80
    linkedit_command_size = 72
    build_command_size = 24
    command_bytes = text_command_size + linkedit_command_size + build_command_size
    payload_offset = header_size + command_bytes
    linkedit_offset = payload_offset + len(payload)
    header = struct.pack(
        "<IiiIIIII",
        0xFEEDFACF,
        0x0100000C,
        cpu_subtype,
        6,
        3,
        command_bytes,
        0x80,
        0,
    )
    text = struct.pack(
        "<II16sQQQQiiII",
        0x19,
        text_command_size,
        b"__TEXT",
        0,
        linkedit_offset,
        0,
        linkedit_offset,
        7,
        5,
        1,
        0,
    )
    section = struct.pack(
        "<16s16sQQIIIIIIII",
        b"__text",
        b"__TEXT",
        payload_offset,
        len(payload),
        payload_offset,
        2,
        0,
        0,
        0x80000400,
        0,
        0,
        0,
    )
    linkedit_command = struct.pack(
        "<II16sQQQQiiII",
        0x19,
        linkedit_command_size,
        b"__LINKEDIT",
        linkedit_offset,
        len(linkedit),
        linkedit_offset,
        len(linkedit),
        7,
        1,
        0,
        0,
    )
    build = struct.pack(
        "<IIIIII", 0x32, build_command_size, 7, 13 << 16, 18 << 16, 0
    )
    return header + text + section + linkedit_command + build + payload + linkedit


def fat_macho(slices: list[tuple[int, bytes]]) -> bytes:
    table_size = 8 + 20 * len(slices)
    offset = table_size
    entries = []
    payload = bytearray()
    for subtype, value in slices:
        entries.append(struct.pack(">iiIII", 0x0100000C, subtype, offset, len(value), 0))
        payload.extend(value)
        offset += len(value)
    return struct.pack(">II", 0xCAFEBABE, len(slices)) + b"".join(entries) + payload


class MachOEngineBindingTest(unittest.TestCase):
    def test_accepts_thinning_and_changed_linkedit_metadata(self) -> None:
        arm64 = thin_macho(0, b"reviewed-arm64-code", b"source-symbols")
        arm64e = thin_macho(2, b"reviewed-arm64e-code", b"source-symbols")
        source = fat_macho([(0, arm64), (2, arm64e)])
        packaged = thin_macho(0, b"reviewed-arm64-code", b"app-signature")
        expected = loadable_macho_slices(source, "source")
        actual = loadable_macho_slices(packaged, "packaged")
        self.assertEqual(actual, {key: expected[key] for key in actual})

    def test_rejects_changed_loadable_code(self) -> None:
        source = thin_macho(0, b"reviewed-code", b"source-symbols")
        packaged = thin_macho(0, b"tampered-code", b"app-signature")
        self.assertNotEqual(
            loadable_macho_slices(source, "source"),
            loadable_macho_slices(packaged, "packaged"),
        )

    def test_rejects_section_that_escapes_slice(self) -> None:
        packaged = bytearray(thin_macho(0, b"reviewed-code", b"signature"))
        struct.pack_into("<Q", packaged, 32 + 72 + 40, len(packaged) + 1)
        with self.assertRaisesRegex(MachOBindingError, "escapes slice"):
            loadable_macho_slices(bytes(packaged), "packaged")


if __name__ == "__main__":
    unittest.main()
