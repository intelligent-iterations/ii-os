import 'dart:convert';
import 'dart:typed_data';

/// Returns the canonical base64-encoded CRC32C value expected by GCS.
String gcsCrc32c(Uint8List bytes) {
  var checksum = 0xffffffff;
  for (final byte in bytes) {
    checksum = _crc32cTable[(checksum ^ byte) & 0xff] ^ (checksum >>> 8);
  }
  checksum = (checksum ^ 0xffffffff) & 0xffffffff;
  final encoded = ByteData(4)..setUint32(0, checksum, Endian.big);
  return base64Encode(encoded.buffer.asUint8List());
}

final List<int> _crc32cTable = List<int>.unmodifiable(
  List<int>.generate(256, (index) {
    var value = index;
    for (var bit = 0; bit < 8; bit++) {
      value = (value & 1) == 0 ? value >>> 1 : (value >>> 1) ^ 0x82f63b78;
    }
    return value & 0xffffffff;
  }),
);
