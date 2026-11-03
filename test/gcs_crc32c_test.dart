import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/services/gcs_crc32c.dart';

void main() {
  test('encodes canonical GCS CRC32C checksums', () {
    expect(gcsCrc32c(Uint8List(0)), 'AAAAAA==');
    expect(gcsCrc32c(Uint8List.fromList('123456789'.codeUnits)), '4waSgw==');
  });
}
