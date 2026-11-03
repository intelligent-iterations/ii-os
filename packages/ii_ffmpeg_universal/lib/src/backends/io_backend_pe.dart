part of 'io_backend.dart';

Set<String> portableExecutableImports(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  int u16(int offset) => data.getUint16(offset, Endian.little);
  int u32(int offset) => data.getUint32(offset, Endian.little);
  if (bytes.length < 0x40 || u16(0) != 0x5a4d) {
    throw const FfmpegException(
      FfmpegErrorCode.engineUnavailable,
      'A Windows desktop engine file is not a PE image.',
    );
  }
  final pe = u32(0x3c);
  if (pe + 24 > bytes.length || u32(pe) != 0x00004550) {
    throw const FfmpegException(
      FfmpegErrorCode.engineUnavailable,
      'A Windows desktop engine file has an invalid PE header.',
    );
  }
  final sectionCount = u16(pe + 6);
  final optionalSize = u16(pe + 20);
  final optional = pe + 24;
  final magic = u16(optional);
  final directory = switch (magic) {
    0x10b => 96,
    0x20b => 112,
    _ => -1,
  };
  if (directory < 0 ||
      optional + directory + 14 * 8 > bytes.length ||
      directory + 14 * 8 > optionalSize) {
    throw const FfmpegException(
      FfmpegErrorCode.engineUnavailable,
      'A Windows desktop engine has an unsupported PE optional header.',
    );
  }
  final sections = <(int, int, int, int)>[];
  final sectionTable = optional + optionalSize;
  for (var index = 0; index < sectionCount; index += 1) {
    final offset = sectionTable + index * 40;
    if (offset + 40 > bytes.length) {
      throw const FfmpegException(
        FfmpegErrorCode.engineUnavailable,
        'A Windows desktop engine has a truncated PE section table.',
      );
    }
    sections.add((
      u32(offset + 12),
      u32(offset + 8),
      u32(offset + 20),
      u32(offset + 16),
    ));
  }
  int rvaOffset(int rva) {
    for (final section in sections) {
      final relative = rva - section.$1;
      if (relative >= 0 && relative < section.$4) {
        return section.$3 + rva - section.$1;
      }
    }
    return -1;
  }

  String readName(int rva) {
    var nameOffset = rvaOffset(rva);
    final values = <int>[];
    while (nameOffset >= 0 &&
        nameOffset < bytes.length &&
        values.length <= 260) {
      final value = bytes[nameOffset++];
      if (value == 0) break;
      values.add(value);
    }
    if (values.isEmpty ||
        values.length > 260 ||
        values.any((value) => value > 0x7f)) {
      throw const FfmpegException(
        FfmpegErrorCode.engineUnavailable,
        'A Windows desktop engine has an invalid import name.',
      );
    }
    return String.fromCharCodes(values);
  }

  final imports = <String>{};
  void readDirectory(int rva, int descriptorSize, int nameField) {
    if (rva == 0) return;
    var descriptor = rvaOffset(rva);
    if (descriptor < 0) {
      throw const FfmpegException(
        FfmpegErrorCode.engineUnavailable,
        'A Windows desktop engine has an unmapped import table.',
      );
    }
    for (var count = 0; count < 4096; count += 1) {
      if (descriptor + descriptorSize > bytes.length) break;
      final fields = List.generate(
        descriptorSize ~/ 4,
        (index) => u32(descriptor + index * 4),
      );
      if (fields.every((value) => value == 0)) return;
      if (descriptorSize == 32 && fields[0] & 1 == 0) {
        throw const FfmpegException(
          FfmpegErrorCode.engineUnavailable,
          'A Windows desktop engine uses unsupported VA delay imports.',
        );
      }
      imports.add(readName(fields[nameField]));
      descriptor += descriptorSize;
    }
    throw const FfmpegException(
      FfmpegErrorCode.engineUnavailable,
      'A Windows desktop engine has an unterminated import table.',
    );
  }

  readDirectory(u32(optional + directory + 8), 20, 3);
  readDirectory(u32(optional + directory + 13 * 8), 32, 1);
  return imports;
}
