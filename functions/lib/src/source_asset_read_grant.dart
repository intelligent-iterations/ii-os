import 'api_error.dart';
import 'retention.dart';

/// Guards a stored workspace object reference before it is ever signed.
///
/// Lives here rather than beside the upload path so that read authorization can
/// be validated without pulling in Firestore or Cloud Storage clients.
bool sourceAssetWorkspaceObjectReferenceIsValid({
  required String workspaceId,
  required String objectName,
  required String generation,
}) {
  final pathParts = objectName.split('/');
  return objectName.startsWith('workspaces/$workspaceId/') &&
      objectName.length <= 1024 &&
      !pathParts.any((part) => part.isEmpty || part == '.' || part == '..') &&
      !objectName.contains(RegExp(r'[\\\x00-\x1f]')) &&
      RegExp(r'^[1-9][0-9]{0,29}$').hasMatch(generation);
}

/// The verified identity of a stored source asset, resolved from its record.
///
/// Parsing is deliberately separate from signing so the rules can be unit
/// tested without a workspace connection.
final class SourceAssetReadIdentity {
  const SourceAssetReadIdentity({
    required this.assetId,
    required this.workspaceId,
    required this.objectName,
    required this.generation,
    required this.filename,
    required this.contentType,
    required this.sizeBytes,
    required this.ghostMode,
    required this.sha256,
  });

  /// Resolves [data] from the `sourceAssets` collection into a read identity.
  ///
  /// Throws [ApiError] when the record cannot back a read grant.
  factory SourceAssetReadIdentity.parse(
    Map<String, Object?>? data, {
    required String workspaceId,
    required String assetId,
    DateTime? now,
  }) {
    if (data == null ||
        data['workspaceId'] != workspaceId ||
        data['status'] != 'ready' ||
        recordRetentionExpired(data, now: now)) {
      throw const ApiError(
        409,
        'source_asset_not_ready',
        'The source asset is not ready for this workflow.',
      );
    }
    final objectName = data['path'];
    final generation = data['generation'];
    if (objectName is! String ||
        generation is! String ||
        !sourceAssetWorkspaceObjectReferenceIsValid(
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
    final contentType = data['contentType'];
    final sizeBytes = data['sizeBytes'];
    // Objects registered from an existing bucket file only carry a digest when
    // Cloud Storage held one, so absence is tolerated here and refused by the
    // route, which cannot let a client verify bytes without it.
    final sha256 = data['sha256'];
    if (contentType is! String ||
        contentType.isEmpty ||
        sizeBytes is! int ||
        sizeBytes <= 0 ||
        (sha256 != null &&
            (sha256 is! String ||
                !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256)))) {
      throw const ApiError(
        409,
        'asset_metadata_invalid',
        'The asset metadata is unavailable.',
      );
    }
    final filename = data['filename'];
    return SourceAssetReadIdentity(
      assetId: assetId,
      workspaceId: workspaceId,
      objectName: objectName,
      generation: generation,
      filename: filename is String && filename.isNotEmpty
          ? filename
          : objectName.split('/').last,
      contentType: contentType,
      sizeBytes: sizeBytes,
      ghostMode: data['ghostMode'] == true,
      sha256: sha256 as String?,
    );
  }

  final String assetId;
  final String workspaceId;
  final String objectName;
  final String generation;
  final String filename;
  final String contentType;
  final int sizeBytes;
  final bool ghostMode;

  /// Null when the stored object carried no `ii-os-sha256` metadata.
  final String? sha256;

  /// Scopes cached grants and read authorization the same way the job artifact
  /// route scopes them by job id.
  String get grantScopeId => 'source-asset:$assetId';
}

/// A signed, time-boxed authorization to read one source asset.
final class SourceAssetReadGrant {
  const SourceAssetReadGrant({
    required this.identity,
    required this.bucket,
    required this.url,
    required this.expiresAt,
  });

  final SourceAssetReadIdentity identity;
  final String bucket;
  final String url;
  final DateTime expiresAt;

  /// Mirrors the job artifact read-url payload so the client reuses its
  /// existing grant parsing and byte verification unchanged.
  Map<String, Object?> toJson() => {
    'url': url,
    'expiresAt': expiresAt.toIso8601String(),
    'workspaceId': identity.workspaceId,
    'jobId': identity.grantScopeId,
    'assetId': identity.assetId,
    'bucket': bucket,
    'object': identity.objectName,
    'generation': identity.generation,
    'sizeBytes': identity.sizeBytes,
    'sha256': identity.sha256,
    'contentType': identity.contentType,
    'filename': identity.filename,
    'ghostMode': identity.ghostMode,
  };

  /// The exact keys job dispatch has always consumed. Changing this shape
  /// breaks every workflow that materializes source references.
  Map<String, Object?> workflowContract() => {
    'assetId': identity.assetId,
    'url': url,
    'expiresAt': expiresAt.toIso8601String(),
    'contentType': identity.contentType,
    'sizeBytes': identity.sizeBytes,
  };
}
