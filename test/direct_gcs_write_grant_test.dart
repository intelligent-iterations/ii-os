import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/services/direct_gcs_write_grant.dart';

const _bucket = 'workspace-bucket';
const _object = 'workspaces/workspace-1/source-assets/asset-1/source.png';
const _sha256 =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _crc32c = '4waSgw==';

void main() {
  test('accepts one exact bounded signed GCS write contract', () {
    final signedAt = _wholeSecondNow();
    final data = _grant(signedAt);

    final grant = validateDirectGcsWriteGrant(
      data: data,
      expectedBucket: _bucket,
      expectedObject: _object,
      expectedContentType: 'image/png',
      expectedSha256: _sha256,
      expectedCrc32c: _crc32c,
    );

    expect(grant.uri.host, '$_bucket.storage.googleapis.com');
    expect(grant.headers['x-goog-if-generation-match'], '0');
    expect(grant.headers['x-goog-hash'], 'crc32c=$_crc32c');
  });

  test('rejects changed identity, signature structure, and headers', () {
    final signedAt = _wholeSecondNow();
    final valid = _grant(signedAt);
    final validHeaders = Map<String, String>.from(
      valid['uploadHeaders']! as Map,
    );

    for (final changed in <JsonMap>[
      {...valid, 'uploadBucket': 'other-bucket'},
      {...valid, 'uploadObject': 'workspaces/workspace-1/other.png'},
      {...valid, 'uploadUrl': '${valid['uploadUrl']}&unknown=value'},
      {
        ...valid,
        'uploadHeaders': {...validHeaders, 'x-extra': 'value'},
      },
      {
        ...valid,
        'uploadHeaders': {
          ...validHeaders,
          'x-goog-meta-ii-os-sha256': List.filled(64, 'b').join(),
        },
      },
      {
        ...valid,
        'uploadHeaders': {...validHeaders, 'x-goog-hash': 'crc32c=AAAAAA=='},
      },
      {
        ...valid,
        'uploadExpiresAt': signedAt
            .add(const Duration(hours: 1))
            .toIso8601String(),
      },
    ]) {
      expect(
        () => validateDirectGcsWriteGrant(
          data: changed,
          expectedBucket: _bucket,
          expectedObject: _object,
          expectedContentType: 'image/png',
          expectedSha256: _sha256,
          expectedCrc32c: _crc32c,
        ),
        throwsFormatException,
      );
    }
  });
}

JsonMap _grant(DateTime signedAt) {
  final expiresAt = signedAt.add(const Duration(minutes: 5));
  final date = _timestamp(signedAt);
  return {
    'uploadUrl': Uri.https('$_bucket.storage.googleapis.com', '/$_object', {
      'X-Goog-Algorithm': 'GOOG4-RSA-SHA256',
      'X-Goog-Credential':
          'ii-os-upload@example.com/${date.substring(0, 8)}/'
          'auto/storage/goog4_request',
      'X-Goog-Date': date,
      'X-Goog-Expires': '300',
      'X-Goog-SignedHeaders':
          'content-type;host;x-goog-hash;x-goog-if-generation-match;'
          'x-goog-meta-ii-os-sha256',
      'X-Goog-Signature': List.filled(512, '0').join(),
    }).toString(),
    'uploadExpiresAt': expiresAt.toIso8601String(),
    'uploadBucket': _bucket,
    'uploadObject': _object,
    'uploadHeaders': {
      'content-type': 'image/png',
      'x-goog-hash': 'crc32c=$_crc32c',
      'x-goog-if-generation-match': '0',
      'x-goog-meta-ii-os-sha256': _sha256,
    },
  };
}

DateTime _wholeSecondNow() => DateTime.fromMillisecondsSinceEpoch(
  (DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000) * 1000,
  isUtc: true,
);

String _timestamp(DateTime value) {
  String two(int part) => part.toString().padLeft(2, '0');
  return '${value.year.toString().padLeft(4, '0')}'
      '${two(value.month)}${two(value.day)}T'
      '${two(value.hour)}${two(value.minute)}${two(value.second)}Z';
}
