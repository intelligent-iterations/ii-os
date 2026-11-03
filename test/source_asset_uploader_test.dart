import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/services/source_asset_uploader.dart';

void main() {
  test('detects accepted source image signatures', () {
    expect(
      sourceImageContentType(Uint8List.fromList([0xff, 0xd8, 0xff, 0x00])),
      'image/jpeg',
    );
    expect(
      sourceImageContentType(
        Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
      ),
      'image/png',
    );
    expect(
      sourceImageContentType(Uint8List.fromList('RIFF0000WEBP'.codeUnits)),
      'image/webp',
    );
  });

  test('rejects content without an accepted image signature', () {
    expect(
      sourceImageContentType(Uint8List.fromList('GIF89a'.codeUnits)),
      null,
    );
    expect(sourceImageContentType(Uint8List(0)), null);
  });

  test('detects accepted source audio signatures and extensions', () {
    expect(
      sourceAudioContentType(
        Uint8List.fromList('RIFF0000WAVE'.codeUnits),
        filename: 'voice.wav',
      ),
      'audio/wav',
    );
    expect(
      sourceAudioContentType(Uint8List.fromList('ID3 demo'.codeUnits)),
      'audio/mpeg',
    );
    expect(
      sourceAudioContentType(Uint8List.fromList([0xff, 0xfb, 0x90, 0x64])),
      'audio/mpeg',
    );
    expect(
      sourceAudioContentType(
        Uint8List.fromList([0, 0, 0, 0, 0x66, 0x74, 0x79, 0x70, 0, 0, 0, 0]),
      ),
      'audio/mp4',
    );
    expect(
      sourceAudioContentType(Uint8List.fromList([0]), filename: 'voice.m4a'),
      'audio/mp4',
    );
  });

  test('rejects content without an accepted audio signature or extension', () {
    expect(
      sourceAudioContentType(Uint8List.fromList('GIF89a'.codeUnits)),
      null,
    );
    expect(sourceAudioContentType(Uint8List(0)), null);
  });

  test('detects MP4 and WebM video references', () {
    expect(
      sourceVideoContentType(
        Uint8List.fromList('0000ftyp0000'.codeUnits),
        filename: 'source.mp4',
      ),
      'video/mp4',
    );
    expect(
      sourceVideoContentType(
        Uint8List.fromList(const [0x1a, 0x45, 0xdf, 0xa3]),
        filename: 'source.webm',
      ),
      'video/webm',
    );
    expect(
      sourceVideoContentType(
        Uint8List.fromList('0000ftyp0000'.codeUnits),
        filename: 'source.m4a',
      ),
      isNull,
    );
  });
}
