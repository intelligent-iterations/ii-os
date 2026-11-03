import '../models/classification_decisions.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../services/artifact_read_url_cache.dart';
import '../services/verified_artifact_document.dart';

/// Reads classification results, which live in the workspace's own bucket.
///
/// ii-os only authorizes the read: the browser fetches the bytes directly from
/// storage with a short-lived grant and verifies them before parsing.
abstract interface class ClassificationResultRepository {
  Future<ClassificationDecisions> readDecisions({
    required String workspaceId,
    required String jobId,
    required String expectedBucket,
    required JsonMap artifact,
  });

  /// Releases a Ghost-mode result once this browser holds verified bytes.
  Future<void> consumeGhostJob({
    required String workspaceId,
    required String jobId,
  });
}

final class ClassificationResultApiRepository
    implements ClassificationResultRepository {
  const ClassificationResultApiRepository(this.api);

  final ApiClient api;

  @override
  Future<ClassificationDecisions> readDecisions({
    required String workspaceId,
    required String jobId,
    required String expectedBucket,
    required JsonMap artifact,
  }) async {
    final expected = decisionsArtifactIdentity(
      workspaceId: workspaceId,
      jobId: jobId,
      expectedBucket: expectedBucket,
      artifact: artifact,
    );
    // A fresh grant every time: results are small, and a cached grant would
    // outlive a Ghost-mode object the control plane is about to remove.
    final grant = await ArtifactReadUrlCache(refreshBefore: Duration.zero)
        .resolve(
          expected: expected,
          load: () => api.get(
            'v1/workspaces/$workspaceId/jobs/'
            '${Uri.encodeComponent(jobId)}/artifacts/read-url',
            query: {'object': expected.objectName},
          ),
        );
    final document = await downloadVerifiedJsonDocument(
      fetch: api.getBytes,
      grant: grant,
      expected: expected,
    );
    return ClassificationDecisions.fromDocument(document);
  }

  @override
  Future<void> consumeGhostJob({
    required String workspaceId,
    required String jobId,
  }) => api.post(
    'v1/workspaces/$workspaceId/jobs/'
    '${Uri.encodeComponent(jobId)}/artifacts/consume',
  );
}

/// The decisions document reported by a completed classification job.
JsonMap? decisionsArtifact(JsonMap job) {
  final artifacts = job['artifacts'];
  if (artifacts is! List) return null;
  for (final item in artifacts) {
    if (item is! Map) continue;
    final artifact = item.cast<String, Object?>();
    if (artifact['content_type'] == artifactDocumentContentType &&
        '${artifact['path']}'.endsWith('/open-jev/decisions.json')) {
      return artifact;
    }
  }
  return null;
}

/// The exact object a read grant must name, or a [FormatException].
ArtifactAuthorizationIdentity decisionsArtifactIdentity({
  required String workspaceId,
  required String jobId,
  required String expectedBucket,
  required JsonMap artifact,
}) {
  final objectName = artifact['path']?.toString() ?? '';
  final generation = artifact['generation']?.toString() ?? '';
  final size = artifact['size_bytes'];
  final sha256 = artifact['sha256']?.toString().toLowerCase() ?? '';
  final prefixes = [
    'workspaces/$workspaceId/runs/$jobId/',
    'workspaces/$workspaceId/ghost/$jobId/',
  ];
  if (workspaceId.isEmpty ||
      jobId.isEmpty ||
      expectedBucket.isEmpty ||
      !prefixes.any(objectName.startsWith) ||
      objectName.split('/').any((part) => part.isEmpty || part == '..') ||
      !RegExp(r'^[1-9][0-9]{0,29}$').hasMatch(generation) ||
      size is! int ||
      size <= 0 ||
      size > maxArtifactDocumentBytes ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256) ||
      artifact['content_type'] != artifactDocumentContentType) {
    throw const FormatException('The classification result is unavailable.');
  }
  return ArtifactAuthorizationIdentity(
    workspaceId: workspaceId,
    jobId: jobId,
    bucket: expectedBucket,
    objectName: objectName,
    generation: generation,
    sizeBytes: size,
    sha256: sha256,
    contentType: artifactDocumentContentType,
  );
}
