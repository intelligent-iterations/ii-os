import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/asset_url_signer.dart';
import 'package:ii_os_functions/src/data_plane_connection.dart';
import 'package:test/test.dart';

void main() {
  test(
    'creates a bounded signed-PUT contract with integrity metadata',
    () async {
      final grant = await AssetUrlSigner(_connection).signWriteUrl(
        objectName: 'workspaces/workspace-1/source-assets/asset-1/source.png',
        contentType: 'image/png',
        sha256Hex: List.filled(64, 'a').join(),
        crc32cBase64: '4waSgw==',
      );

      expect(
        Uri.parse(grant.url).host,
        'customer-media.storage.googleapis.com',
      );
      final uri = Uri.parse(grant.url);
      expect(uri.queryParameters.keys.toSet(), {
        'X-Goog-Algorithm',
        'X-Goog-Credential',
        'X-Goog-Date',
        'X-Goog-Expires',
        'X-Goog-SignedHeaders',
        'X-Goog-Signature',
      });
      expect(uri.queryParameters['X-Goog-Algorithm'], 'GOOG4-RSA-SHA256');
      expect(uri.queryParameters['X-Goog-Expires'], '300');
      expect(
        uri.queryParameters['X-Goog-SignedHeaders'],
        'content-type;host;x-goog-hash;x-goog-if-generation-match;'
        'x-goog-meta-ii-os-sha256',
      );
      expect(
        uri.queryParameters['X-Goog-Signature'],
        matches(RegExp(r'^[a-f0-9]{512}$')),
      );
      final signedAt = DateTime.parse(
        _isoTimestamp(uri.queryParameters['X-Goog-Date']!),
      );
      expect(signedAt.add(const Duration(minutes: 5)), grant.expiresAt);
      expect(grant.headers['content-type'], 'image/png');
      expect(grant.headers['x-goog-hash'], 'crc32c=4waSgw==');
      expect(grant.headers['x-goog-if-generation-match'], '0');
      expect(
        grant.headers['x-goog-meta-ii-os-sha256'],
        List.filled(64, 'a').join(),
      );
      expect(grant.expiresAt.isAfter(DateTime.now().toUtc()), isTrue);
    },
  );

  test('rejects grants longer than fifteen minutes', () async {
    await expectLater(
      AssetUrlSigner(_connection).signReadUrl(
        'workspaces/workspace-1/output.png',
        lifetime: const Duration(minutes: 16),
      ),
      throwsA(
        isA<ApiError>().having(
          (error) => error.code,
          'code',
          'invalid_asset_url_lifetime',
        ),
      ),
    );
  });

  test('binds a read grant to the verified object generation', () async {
    final grant = await AssetUrlSigner(_connection).signReadUrl(
      'workspaces/workspace-1/output.mp4',
      generation: '1730000000000000',
    );
    final uri = Uri.parse(grant.url);

    expect(uri.queryParameters['generation'], '1730000000000000');
    expect(uri.queryParameters['X-Goog-Algorithm'], 'GOOG4-RSA-SHA256');
    expect(uri.queryParameters['X-Goog-Expires'], '900');
    expect(uri.queryParameters['X-Goog-SignedHeaders'], 'host');
    expect(
      uri.queryParameters['X-Goog-Signature'],
      matches(RegExp(r'^[a-f0-9]{512}$')),
    );
    final signedAt = DateTime.parse(
      _isoTimestamp(uri.queryParameters['X-Goog-Date']!),
    );
    expect(signedAt.add(const Duration(minutes: 15)), grant.expiresAt);
  });

  test(
    'reuses a bounded read grant for immutable object generations',
    () async {
      final signer = AssetUrlSigner(_connection);
      final first = await signer.signReadUrl(
        'workspaces/workspace-1/output-cache.png',
        generation: '1730000000000001',
        cacheIdentity: _readCacheIdentity,
      );
      final second = await signer.signReadUrl(
        'workspaces/workspace-1/output-cache.png',
        generation: '1730000000000001',
        cacheIdentity: _readCacheIdentity,
      );

      expect(second.url, first.url);
      expect(second.expiresAt, first.expiresAt);
      expect(
        first.expiresAt.difference(DateTime.now().toUtc()),
        greaterThan(const Duration(minutes: 14)),
      );
    },
  );
}

const _connection = DataPlaneConnection(
  workspaceId: '123e4567-e89b-42d3-a456-426614174000',
  projectId: 'customer-media',
  projectNumber: '123456789012',
  databaseId: 'ii-os',
  region: 'us-central1',
  bucket: 'customer-media',
  dataServiceAccount: 'ii-os-data@customer-media.iam.gserviceaccount.com',
  uploadServiceAccount: 'ii-os-upload@customer-media.iam.gserviceaccount.com',
  workloadIdentityProvider:
      'projects/123456789012/locations/global/workloadIdentityPools/ii-os-github/providers/ii-os-workflows',
  authProjectId: 'platform-auth',
  webOrigin: 'https://ii-os.example.com',
  emulated: true,
);

const _readCacheIdentity = AssetReadGrantCacheIdentity(
  workspaceId: 'workspace-1',
  jobId: 'job-1',
  sizeBytes: 128,
  sha256:
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  contentType: 'image/png',
);

String _isoTimestamp(String value) =>
    '${value.substring(0, 4)}-${value.substring(4, 6)}-'
    '${value.substring(6, 8)}T${value.substring(9, 11)}:'
    '${value.substring(11, 13)}:${value.substring(13, 15)}Z';
