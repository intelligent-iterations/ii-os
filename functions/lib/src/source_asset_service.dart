import 'package:google_cloud_firestore/google_cloud_firestore.dart';
import 'package:googleapis/storage/v1.dart' as storage;
import 'package:googleapis_auth/auth_io.dart';
import 'package:uuid/uuid.dart';

import 'api_error.dart';
import 'asset_url_signer.dart';
import 'data_plane_connection.dart';
import 'gcs_crc32c.dart';
import 'retention.dart';
import 'retention_policy.dart';
import 'source_asset_read_grant.dart';
import 'workspace_store.dart';

export 'source_asset_read_grant.dart'
    show
        SourceAssetReadGrant,
        SourceAssetReadIdentity,
        sourceAssetWorkspaceObjectReferenceIsValid;

final class SourceAssetService {
  SourceAssetService({required this.store});

  final WorkspaceStore store;
  final Uuid _uuid = const Uuid();

  Future<Map<String, Object?>> createUpload({
    required String workspaceId,
    required String actorUid,
    required Map<String, Object?> request,
    int retentionDays = defaultArtifactRetentionDays,
    bool ghostMode = false,
  }) async {
    final signer = AssetUrlSigner(
      await store.requireConnection(workspaceId, permission: 'assets.write'),
    );
    final spec = SourceAssetSpec.parse(request);
    final assetId = _uuid.v4();
    final objectName =
        'workspaces/$workspaceId/'
        '${ghostMode ? 'ghost-source-assets' : 'source-assets'}/'
        '$assetId/${spec.safeFilename}';
    final grant = await signer.signWriteUrl(
      objectName: objectName,
      contentType: spec.contentType,
      sha256Hex: spec.sha256,
      crc32cBase64: spec.crc32c,
    );
    final now = DateTime.now().toUtc();
    final data = <String, Object?>{
      'assetId': assetId,
      'workspaceId': workspaceId,
      'path': objectName,
      'filename': spec.safeFilename,
      'contentType': spec.contentType,
      'sizeBytes': spec.sizeBytes,
      'sha256': spec.sha256,
      'crc32c': spec.crc32c,
      'status': 'pending',
      'ghostMode': ghostMode,
      'createdBy': actorUid,
      'createdAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
      'expiresAt': Timestamp.fromDate(
        now.add(
          Duration(
            days: ghostMode
                ? 1
                : retentionDays.clamp(
                    minArtifactRetentionDays,
                    maxArtifactRetentionDays,
                  ),
          ),
        ),
      ),
    };
    await store.firestore.collection('sourceAssets').doc(assetId).create(data);
    return {
      ..._public(data),
      'uploadUrl': grant.url,
      'uploadHeaders': grant.headers,
      'uploadExpiresAt': grant.expiresAt.toIso8601String(),
      'uploadBucket': signer.connection.bucket,
      'uploadObject': objectName,
    };
  }

  /// Registers an existing immutable workspace object as a workflow source.
  ///
  /// This creates metadata only. The control plane verifies GCS metadata but
  /// never downloads, copies, transforms, or proxies the asset bytes.
  Future<Map<String, Object?>> registerWorkspaceObject({
    required String workspaceId,
    required String actorUid,
    required String objectName,
    required String generation,
    required String filename,
    required String contentType,
    int retentionDays = defaultArtifactRetentionDays,
  }) async {
    final connection = await store.requireConnection(
      workspaceId,
      permission: 'assets.write',
    );
    if (!sourceAssetWorkspaceObjectReferenceIsValid(
      workspaceId: workspaceId,
      objectName: objectName,
      generation: generation,
    )) {
      throw const ApiError(
        409,
        'source_asset_reference_invalid',
        'The workspace asset reference is invalid.',
      );
    }
    final spec = SourceAssetSpec.parse({
      'filename': filename,
      'contentType': contentType,
      'sizeBytes': 1,
      'sha256': List.filled(64, '0').join(),
      'crc32c': 'AAAAAA==',
    });
    final verified = connection.emulated
        ? (sizeBytes: 1, crc32c: 'emulated', sha256: null)
        : await _verifyExistingObject(
            connection,
            objectName: objectName,
            generation: generation,
            contentType: contentType,
            maxBytes: _contentTypes[contentType]!.maxBytes,
          );
    final assetId = _uuid.v4();
    final now = DateTime.now().toUtc();
    final data = <String, Object?>{
      'assetId': assetId,
      'workspaceId': workspaceId,
      'path': objectName,
      'filename': spec.safeFilename,
      'contentType': contentType,
      'sizeBytes': verified.sizeBytes,
      if (verified.sha256 != null) 'sha256': verified.sha256,
      'status': 'ready',
      'generation': generation,
      'crc32c': verified.crc32c,
      'createdBy': actorUid,
      'createdAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
      'verifiedAt': Timestamp.fromDate(now),
      'expiresAt': Timestamp.fromDate(
        now.add(
          Duration(
            days: retentionDays.clamp(
              minArtifactRetentionDays,
              maxArtifactRetentionDays,
            ),
          ),
        ),
      ),
    };
    await store.firestore.collection('sourceAssets').doc(assetId).create(data);
    return _public(data);
  }

  Future<Map<String, Object?>> completeUpload({
    required String workspaceId,
    required String actorUid,
    required String assetId,
  }) async {
    final connection = await store.requireConnection(
      workspaceId,
      permission: 'assets.write',
    );
    final ref = store.firestore.collection('sourceAssets').doc(assetId);
    final snapshot = await ref.get();
    final data = snapshot.data();
    _requireOwned(data, workspaceId, actorUid);
    if (data!['status'] == 'ready') return _public(data);

    final verified = connection.emulated
        ? <String, Object?>{'generation': '1', 'crc32c': data['crc32c']}
        : await _verifyRemote(connection, data);
    final now = Timestamp.now();
    await ref.update({
      'status': 'ready',
      ...verified,
      'verifiedAt': now,
      'updatedAt': now,
    });
    return _public({...data, 'status': 'ready', ...verified, 'updatedAt': now});
  }

  /// Signs a short-lived read for one stored source asset.
  Future<SourceAssetReadGrant> readGrant({
    required String workspaceId,
    required String assetId,
  }) async {
    final signer = AssetUrlSigner(
      await store.requireConnection(workspaceId, permission: 'assets.read'),
    );
    final snapshot = await store.firestore
        .collection('sourceAssets')
        .doc(assetId)
        .get();
    final identity = SourceAssetReadIdentity.parse(
      snapshot.exists ? snapshot.data() : null,
      workspaceId: workspaceId,
      assetId: assetId,
    );
    final digest = identity.sha256;
    final grant = await signer.signReadUrl(
      identity.objectName,
      generation: identity.generation,
      // Objects registered from an existing bucket file may carry no digest,
      // and an invalid cache identity is refused by the signer outright.
      cacheIdentity: digest == null
          ? null
          : AssetReadGrantCacheIdentity(
              workspaceId: workspaceId,
              jobId: identity.grantScopeId,
              sizeBytes: identity.sizeBytes,
              sha256: digest,
              contentType: identity.contentType,
            ),
    );
    return SourceAssetReadGrant(
      identity: identity,
      bucket: signer.connection.bucket,
      url: grant.url,
      expiresAt: grant.expiresAt,
    );
  }

  Future<Map<String, Object?>> workflowReadContract({
    required String workspaceId,
    required String assetId,
  }) async => (await readGrant(
    workspaceId: workspaceId,
    assetId: assetId,
  )).workflowContract();

  Future<Map<String, Object?>> _verifyRemote(
    DataPlaneConnection connection,
    Map<String, Object?> data,
  ) async {
    final client = await clientViaApplicationDefaultCredentials(
      scopes: const ['https://www.googleapis.com/auth/cloud-platform'],
    );
    try {
      final remote = await storage.StorageApi(
        client,
      ).objects.get(connection.bucket, data['path']! as String);
      if (remote is! storage.Object ||
          remote.contentType != data['contentType'] ||
          remote.size != data['sizeBytes'].toString() ||
          remote.metadata?['ii-os-sha256'] != data['sha256'] ||
          remote.crc32c != data['crc32c'] ||
          remote.generation == null) {
        throw const ApiError(
          409,
          'source_asset_verification_failed',
          'The uploaded source asset does not match its upload request.',
        );
      }
      return {'generation': remote.generation, 'crc32c': remote.crc32c};
    } on ApiError {
      rethrow;
    } catch (_) {
      throw const ApiError(
        409,
        'source_asset_verification_failed',
        'The uploaded source asset could not be verified.',
      );
    } finally {
      client.close();
    }
  }

  Future<({int sizeBytes, String? crc32c, String? sha256})>
  _verifyExistingObject(
    DataPlaneConnection connection, {
    required String objectName,
    required String generation,
    required String contentType,
    required int maxBytes,
  }) async {
    final client = await clientViaApplicationDefaultCredentials(
      scopes: const ['https://www.googleapis.com/auth/cloud-platform'],
    );
    try {
      final remote = await storage.StorageApi(
        client,
      ).objects.get(connection.bucket, objectName, generation: generation);
      final sizeBytes = remote is storage.Object
          ? int.tryParse(remote.size ?? '') ?? 0
          : 0;
      final metadata = remote is storage.Object ? remote.metadata : null;
      final objectSha256 = metadata == null ? null : metadata['ii-os-sha256'];
      if (remote is! storage.Object ||
          remote.generation != generation ||
          remote.contentType != contentType ||
          sizeBytes <= 0 ||
          sizeBytes > maxBytes ||
          (objectSha256 != null &&
              !RegExp(r'^[0-9a-f]{64}$').hasMatch(objectSha256))) {
        throw const ApiError(
          409,
          'source_asset_reference_invalid',
          'The workspace asset metadata does not match its reference.',
        );
      }
      return (
        sizeBytes: sizeBytes,
        crc32c: remote.crc32c,
        sha256: objectSha256,
      );
    } on ApiError {
      rethrow;
    } catch (_) {
      throw const ApiError(
        409,
        'source_asset_reference_invalid',
        'The workspace asset reference could not be verified.',
      );
    } finally {
      client.close();
    }
  }
}

final class SourceAssetSpec {
  const SourceAssetSpec({
    required this.safeFilename,
    required this.contentType,
    required this.sizeBytes,
    required this.sha256,
    required this.crc32c,
  });

  factory SourceAssetSpec.parse(Map<String, Object?> value) {
    final filename = value['filename'];
    final contentType = value['contentType'];
    final size = value['sizeBytes'];
    final sha = value['sha256'];
    final crc32c = canonicalGcsCrc32c(value['crc32c']);
    if (filename is! String ||
        filename.trim().isEmpty ||
        filename.length > 255 ||
        contentType is! String ||
        !_contentTypes.containsKey(contentType) ||
        size is! num ||
        size.toInt() != size ||
        size <= 0 ||
        size > _contentTypes[contentType]!.maxBytes ||
        sha is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha.toLowerCase()) ||
        crc32c == null) {
      throw const ApiError(
        400,
        'invalid_source_asset',
        'Source asset metadata is invalid.',
      );
    }
    final basename = filename.trim().split(RegExp(r'[/\\]')).last;
    final stem = basename
        .replaceFirst(RegExp(r'\.[A-Za-z0-9]{1,8}$'), '')
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^[.-]+|[.-]+$'), '');
    final safeStem = (stem.isEmpty ? 'source-asset' : stem);
    final boundedStem = safeStem.length > 100
        ? safeStem.substring(0, 100)
        : safeStem;
    return SourceAssetSpec(
      safeFilename: '$boundedStem.${_contentTypes[contentType]!.extension}',
      contentType: contentType,
      sizeBytes: size.toInt(),
      sha256: sha.toLowerCase(),
      crc32c: crc32c,
    );
  }

  final String safeFilename;
  final String contentType;
  final int sizeBytes;
  final String sha256;
  final String crc32c;
}

void _requireOwned(
  Map<String, Object?>? data,
  String workspaceId,
  String actorUid,
) {
  if (data == null ||
      data['workspaceId'] != workspaceId ||
      data['createdBy'] != actorUid ||
      recordRetentionExpired(data)) {
    throw const ApiError(
      404,
      'source_asset_not_found',
      'Source asset not found.',
    );
  }
}

Map<String, Object?> _public(Map<String, Object?> data) => data.map(
  (key, value) => MapEntry(
    key,
    value is Timestamp ? value.toDate().toUtc().toIso8601String() : value,
  ),
)..remove('createdBy');

const _contentTypes = <String, ({String extension, int maxBytes})>{
  'image/jpeg': (extension: 'jpg', maxBytes: 50 * 1024 * 1024),
  'image/png': (extension: 'png', maxBytes: 50 * 1024 * 1024),
  'image/webp': (extension: 'webp', maxBytes: 50 * 1024 * 1024),
  'audio/wav': (extension: 'wav', maxBytes: 50 * 1024 * 1024),
  'audio/mpeg': (extension: 'mp3', maxBytes: 50 * 1024 * 1024),
  'audio/mp4': (extension: 'm4a', maxBytes: 50 * 1024 * 1024),
  'video/mp4': (extension: 'mp4', maxBytes: 512 * 1024 * 1024),
  'video/webm': (extension: 'webm', maxBytes: 512 * 1024 * 1024),
};
