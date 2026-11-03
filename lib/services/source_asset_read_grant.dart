import '../models/models.dart';
import 'artifact_read_url_cache.dart';
import 'verified_artifact_media.dart';

/// A verified authorization to read one workspace source asset.
///
/// A job artifact's identity is known before the request, so the client can
/// pre-compute it. A source asset is addressed only by id, so the identity is
/// derived from the authenticated response and structurally gated here before
/// any byte is trusted. Verification itself is unchanged: the resulting
/// identity is handed to [downloadVerifiedArtifactMedia], which still proves
/// the size, digest and media signature of whatever arrives.
final class SourceAssetReadAuthorization {
  const SourceAssetReadAuthorization({
    required this.grant,
    required this.expected,
    required this.filename,
  });

  /// Parses the control plane's read-url payload for [assetId].
  ///
  /// Throws [FormatException] when the response does not describe exactly the
  /// asset that was asked for.
  factory SourceAssetReadAuthorization.parse(
    JsonMap data, {
    required String workspaceId,
    required String assetId,
    required String expectedBucket,
    DateTime? now,
  }) {
    final jobId = data['jobId']?.toString() ?? '';
    final objectName = data['object']?.toString() ?? '';
    final generation = data['generation']?.toString() ?? '';
    final sizeBytes = data['sizeBytes'];
    final sha256 = data['sha256']?.toString().toLowerCase() ?? '';
    final contentType = data['contentType']?.toString().toLowerCase() ?? '';
    final bucket = data['bucket']?.toString() ?? '';
    final url = data['url']?.toString() ?? '';
    final expiresAt = DateTime.tryParse(data['expiresAt']?.toString() ?? '');
    final normalPrefix = 'workspaces/$workspaceId/source-assets/$assetId/';
    final ghostPrefix =
        'workspaces/$workspaceId/ghost-source-assets/$assetId/';
    if (workspaceId.isEmpty ||
        assetId.isEmpty ||
        expectedBucket.isEmpty ||
        jobId != 'source-asset:$assetId' ||
        data['assetId']?.toString() != assetId ||
        data['workspaceId']?.toString() != workspaceId ||
        bucket != expectedBucket ||
        (!objectName.startsWith(normalPrefix) &&
            !objectName.startsWith(ghostPrefix)) ||
        !RegExp(r'^[1-9][0-9]{0,29}$').hasMatch(generation) ||
        sizeBytes is! int ||
        sizeBytes <= 0 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256) ||
        !supportedArtifactContentTypes.contains(contentType) ||
        expiresAt == null ||
        !expiresAt.isAfter((now ?? DateTime.now()).toUtc())) {
      throw const FormatException(
        'The workspace asset authorization is unavailable.',
      );
    }
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !signedArtifactUrlIdentityMatches(
          uri,
          bucket: bucket,
          objectName: objectName,
          generation: generation,
        ) ||
        !signedArtifactUrlExpiryMatches(uri, expiresAt)) {
      throw const FormatException(
        'The workspace asset authorization is unavailable.',
      );
    }
    final filename = data['filename']?.toString();
    return SourceAssetReadAuthorization(
      grant: ArtifactReadGrant(
        url: url,
        expiresAt: expiresAt,
        workspaceId: workspaceId,
        jobId: jobId,
        bucket: bucket,
        objectName: objectName,
        generation: generation,
        sizeBytes: sizeBytes,
        sha256: sha256,
        contentType: contentType,
      ),
      expected: ArtifactAuthorizationIdentity(
        workspaceId: workspaceId,
        jobId: jobId,
        bucket: bucket,
        objectName: objectName,
        generation: generation,
        sizeBytes: sizeBytes,
        sha256: sha256,
        contentType: contentType,
      ),
      filename: filename != null && filename.isNotEmpty
          ? filename
          : objectName.split('/').last,
    );
  }

  final ArtifactReadGrant grant;
  final ArtifactAuthorizationIdentity expected;
  final String filename;
}
