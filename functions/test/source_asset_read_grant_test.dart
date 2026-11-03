import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/source_asset_read_grant.dart';
import 'package:test/test.dart';

const _workspaceId = 'ws-1';
const _assetId = 'a1b2c3d4-0000-4000-8000-000000000000';
final _sha256 = List.filled(64, 'b').join();
final _now = DateTime.utc(2026, 8, 20, 12);

Map<String, Object?> _ready({
  Map<String, Object?> overrides = const {},
  List<String> removals = const [],
}) {
  final record = <String, Object?>{
    'workspaceId': _workspaceId,
    'status': 'ready',
    'path': 'workspaces/$_workspaceId/source-assets/$_assetId/reference.png',
    'generation': '1',
    'filename': 'reference.png',
    'contentType': 'image/png',
    'sizeBytes': 2048,
    'sha256': _sha256,
    'ghostMode': false,
    'expiresAt': _now.add(const Duration(days: 7)),
    ...overrides,
  };
  for (final key in removals) {
    record.remove(key);
  }
  return record;
}

SourceAssetReadIdentity _parse(Map<String, Object?>? record) =>
    SourceAssetReadIdentity.parse(
      record,
      workspaceId: _workspaceId,
      assetId: _assetId,
      now: _now,
    );

void main() {
  group('SourceAssetReadIdentity', () {
    test('resolves an uploaded asset record', () {
      final identity = _parse(_ready());
      expect(identity.assetId, _assetId);
      expect(identity.workspaceId, _workspaceId);
      expect(
        identity.objectName,
        'workspaces/$_workspaceId/source-assets/$_assetId/reference.png',
      );
      expect(identity.generation, '1');
      expect(identity.filename, 'reference.png');
      expect(identity.contentType, 'image/png');
      expect(identity.sizeBytes, 2048);
      expect(identity.sha256, _sha256);
      expect(identity.ghostMode, isFalse);
      expect(identity.grantScopeId, 'source-asset:$_assetId');
    });

    test('tolerates a registered object that carries no digest', () {
      // registerWorkspaceObject only stores sha256 when Cloud Storage held an
      // ii-os-sha256 value, so absence must parse rather than throw.
      final identity = _parse(_ready(removals: ['sha256']));
      expect(identity.sha256, isNull);
      expect(identity.sizeBytes, 2048);
      expect(identity.contentType, 'image/png');
    });

    test('resolves a ghost asset from its own prefix', () {
      final identity = _parse(
        _ready(
          overrides: {
            'ghostMode': true,
            'path':
                'workspaces/$_workspaceId/ghost-source-assets/$_assetId/clip.mp4',
            'filename': 'clip.mp4',
            'contentType': 'video/mp4',
          },
        ),
      );
      expect(identity.ghostMode, isTrue);
      expect(identity.contentType, 'video/mp4');
      expect(identity.objectName, contains('ghost-source-assets'));
    });

    test('falls back to the object name when no filename is stored', () {
      final identity = _parse(_ready(removals: ['filename']));
      expect(identity.filename, 'reference.png');
    });

    test('refuses a record with no generation', () {
      // Regression: this used to reach the signer as an empty generation and
      // surface a misleading 400 invalid_asset_generation.
      expect(
        () => _parse(_ready(removals: ['generation'])),
        throwsA(_apiError('source_asset_reference_invalid')),
      );
      expect(
        () => _parse(_ready(overrides: {'generation': ''})),
        throwsA(_apiError('source_asset_reference_invalid')),
      );
      expect(
        () => _parse(_ready(overrides: {'generation': 'latest'})),
        throwsA(_apiError('source_asset_reference_invalid')),
      );
    });

    test('refuses an object outside the selected workspace', () {
      expect(
        () => _parse(
          _ready(
            overrides: {
              'path': 'workspaces/other-ws/source-assets/$_assetId/a.png',
            },
          ),
        ),
        throwsA(_apiError('source_asset_reference_invalid')),
      );
      expect(
        () => _parse(
          _ready(
            overrides: {'path': 'workspaces/$_workspaceId/../secrets/a.png'},
          ),
        ),
        throwsA(_apiError('source_asset_reference_invalid')),
      );
    });

    test('refuses a record that cannot back a read', () {
      expect(() => _parse(null), throwsA(_apiError('source_asset_not_ready')));
      expect(
        () => _parse(_ready(overrides: {'status': 'pending'})),
        throwsA(_apiError('source_asset_not_ready')),
      );
      expect(
        () => _parse(_ready(overrides: {'workspaceId': 'other-ws'})),
        throwsA(_apiError('source_asset_not_ready')),
      );
      expect(
        () => _parse(
          _ready(
            overrides: {'expiresAt': _now.subtract(const Duration(days: 1))},
          ),
        ),
        throwsA(_apiError('source_asset_not_ready')),
      );
    });

    test('refuses metadata a client could not verify bytes against', () {
      expect(
        () => _parse(_ready(overrides: {'sizeBytes': 0})),
        throwsA(_apiError('asset_metadata_invalid')),
      );
      expect(
        () => _parse(_ready(overrides: {'contentType': ''})),
        throwsA(_apiError('asset_metadata_invalid')),
      );
      expect(
        () => _parse(_ready(overrides: {'sha256': 'not-a-digest'})),
        throwsA(_apiError('asset_metadata_invalid')),
      );
    });
  });

  group('SourceAssetReadGrant', () {
    SourceAssetReadGrant grant() => SourceAssetReadGrant(
      identity: _parse(_ready()),
      bucket: 'workspace-bucket',
      url: 'https://storage.googleapis.com/signed',
      expiresAt: _now.add(const Duration(minutes: 15)),
    );

    test('mirrors the job artifact read-url payload', () {
      final json = grant().toJson();
      expect(json['jobId'], 'source-asset:$_assetId');
      expect(json['assetId'], _assetId);
      expect(json['workspaceId'], _workspaceId);
      expect(json['bucket'], 'workspace-bucket');
      expect(json['object'], contains('source-assets/$_assetId/'));
      expect(json['generation'], '1');
      expect(json['sizeBytes'], 2048);
      expect(json['sha256'], _sha256);
      expect(json['contentType'], 'image/png');
      expect(json['filename'], 'reference.png');
      expect(json['ghostMode'], isFalse);
      expect(
        json['expiresAt'],
        _now.add(const Duration(minutes: 15)).toIso8601String(),
      );
    });

    test('freezes the keys job dispatch consumes', () {
      // workflow_run_broker materializes every source reference through this
      // map; adding or renaming a key breaks live dispatch.
      expect(grant().workflowContract().keys.toSet(), {
        'assetId',
        'url',
        'expiresAt',
        'contentType',
        'sizeBytes',
      });
    });
  });
}

Matcher _apiError(String code) =>
    isA<ApiError>().having((error) => error.code, 'code', code);
