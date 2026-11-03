import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_ffmpeg_universal/src/backends/io_backend.dart';

void main() {
  test('PE parser includes normal and delay-load imports', () {
    expect(portableExecutableImports(_peFixture()), {
      'normal.dll',
      'delayed.dll',
    });
  });

  test('PE parser rejects legacy VA delay-load imports', () {
    final fixture = _peFixture();
    ByteData.sublistView(fixture).setUint32(0x240, 0, Endian.little);
    expect(() => portableExecutableImports(fixture), throwsException);
  });
}

Uint8List _peFixture() {
  final bytes = Uint8List(0x400);
  final data = ByteData.sublistView(bytes);
  void u16(int offset, int value) =>
      data.setUint16(offset, value, Endian.little);
  void u32(int offset, int value) =>
      data.setUint32(offset, value, Endian.little);

  u16(0, 0x5a4d);
  u32(0x3c, 0x80);
  u32(0x80, 0x00004550);
  u16(0x86, 1);
  u16(0x94, 240);
  const optional = 0x98;
  u16(optional, 0x20b);
  u32(optional + 112 + 8, 0x1000);
  u32(optional + 112 + 12, 40);
  u32(optional + 112 + 13 * 8, 0x1040);
  u32(optional + 112 + 13 * 8 + 4, 64);

  const section = optional + 240;
  u32(section + 8, 0x200);
  u32(section + 12, 0x1000);
  u32(section + 16, 0x200);
  u32(section + 20, 0x200);

  u32(0x20c, 0x1100);
  u32(0x240, 1);
  u32(0x244, 0x1120);
  bytes.setRange(0x300, 0x30b, 'normal.dll\u0000'.codeUnits);
  bytes.setRange(0x320, 0x32c, 'delayed.dll\u0000'.codeUnits);
  return bytes;
}
