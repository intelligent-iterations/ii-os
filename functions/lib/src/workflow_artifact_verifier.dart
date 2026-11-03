import 'api_error.dart';
import 'provider_contracts/artifact_storage_gateway.dart';

final class WorkflowArtifactVerifier {
  const WorkflowArtifactVerifier(this.storage);

  final ArtifactStorageGatewayResolver storage;

  Future<Map<String, Object?>> uploadContract(String workspaceId) async {
    final gateway = await storage.resolve(
      workspaceId,
      permission: 'workflows.upload',
    );
    return (await gateway.createUploadContract()).toJson();
  }

  Future<List<Map<String, Object?>>> verify({
    required String workspaceId,
    required String requestId,
    required Object? value,
    bool ghostMode = false,
  }) async {
    final gateway = await storage.resolve(
      workspaceId,
      permission: 'assets.read',
    );
    final artifacts = normalizeWorkflowArtifacts(
      value,
      workspaceId: workspaceId,
      requestId: requestId,
      ghostMode: ghostMode,
    );
    if (artifacts.isEmpty || !gateway.verifiesRemoteObjects) return artifacts;
    try {
      final metadata = await gateway.readMetadata([
        for (final artifact in artifacts)
          ArtifactObjectLocator(
            path: artifact['path']! as String,
            version: artifact['generation']! as String,
          ),
      ]);
      if (metadata.length != artifacts.length) {
        throw const ApiError(
          409,
          'artifact_verification_failed',
          'Object metadata does not match the workflow report.',
        );
      }
      for (var index = 0; index < artifacts.length; index++) {
        final artifact = artifacts[index];
        final remote = metadata[index];
        if (remote.version != artifact['generation'] ||
            remote.sizeBytes != artifact['size_bytes'] ||
            remote.contentType != artifact['content_type'] ||
            remote.sha256 != artifact['sha256']) {
          throw const ApiError(
            409,
            'artifact_verification_failed',
            'Object metadata does not match the workflow report.',
          );
        }
        artifact['crc32c'] = remote.crc32c;
        artifact['verifiedAt'] = DateTime.now().toUtc().toIso8601String();
      }
      return artifacts;
    } on ApiError {
      rethrow;
    } catch (_) {
      throw const ApiError(
        409,
        'artifact_verification_failed',
        'The reported object could not be verified.',
      );
    }
  }
}

List<Map<String, Object?>> normalizeWorkflowArtifacts(
  Object? value, {
  required String workspaceId,
  required String requestId,
  bool ghostMode = false,
}) {
  if (value == null) return [];
  if (value is! List || value.length > 20) {
    throw const ApiError(
      400,
      'invalid_artifacts',
      'Artifacts must be a list containing at most 20 items.',
    );
  }
  final prefix =
      'workspaces/$workspaceId/${ghostMode ? 'ghost' : 'runs'}/$requestId/';
  final artifacts = value.map((item) {
    if (item is! Map) {
      throw const ApiError(400, 'invalid_artifact', 'Artifact is invalid.');
    }
    final json = item.cast<String, Object?>();
    final path = _string(json, 'path', 900);
    final contentType = _string(json, 'contentType', 100);
    final sha = _string(json, 'sha256', 64).toLowerCase();
    final generation = _string(json, 'generation', 30);
    final size = json['sizeBytes'];
    final segments = path.split('/');
    if (!path.startsWith(prefix) ||
        segments.any(
          (segment) => segment.isEmpty || segment == '.' || segment == '..',
        ) ||
        !_contentTypes.contains(contentType) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha) ||
        !RegExp(r'^[1-9][0-9]{0,29}$').hasMatch(generation) ||
        size is! num ||
        size.toInt() != size ||
        size <= 0 ||
        size > _maxArtifactBytes(contentType)) {
      throw const ApiError(
        400,
        'invalid_artifact',
        'Artifact metadata is invalid or outside the request prefix.',
      );
    }
    // A poster is an ordinary artifact that happens to depict another one, so
    // it carries the same verification as the video it stands for rather than
    // a parallel trust path. Only the relationship is new.
    final role = json['role'];
    final posterFor = json['posterFor'];
    if (role != null && role != 'poster') {
      throw const ApiError(
        400,
        'invalid_artifact_role',
        'The only supported artifact role is poster.',
      );
    }
    if ((role == 'poster') != (posterFor is String)) {
      throw const ApiError(
        400,
        'invalid_artifact_poster',
        'A poster artifact must name the artifact it depicts, and only a '
            'poster may name one.',
      );
    }
    if (role == 'poster' && !contentType.startsWith('image/')) {
      throw const ApiError(
        400,
        'invalid_artifact_poster',
        'A poster must be an image.',
      );
    }

    return <String, Object?>{
      'path': path,
      'content_type': contentType,
      'size_bytes': size.toInt(),
      'sha256': sha,
      'generation': generation,
      if (role == 'poster') 'role': 'poster',
      if (posterFor is String) 'poster_for': posterFor,
    };
  }).toList();

  // Resolved after the whole batch is known: a poster that points outside its
  // own run, at itself, or at another poster would otherwise be storable, and
  // the browser would then ask for a read URL on a path this request never
  // proved.
  final paths = <String, Map<String, Object?>>{
    for (final artifact in artifacts) artifact['path']! as String: artifact,
  };
  for (final artifact in artifacts) {
    final target = artifact['poster_for'];
    if (target is! String) continue;
    final depicted = paths[target];
    if (depicted == null ||
        identical(depicted, artifact) ||
        depicted['role'] == 'poster') {
      throw const ApiError(
        400,
        'invalid_artifact_poster',
        'A poster must depict another artifact reported by the same run.',
      );
    }
  }
  return artifacts;
}

String _string(Map<String, Object?> json, String name, int maxLength) {
  final value = json[name];
  if (value is! String || value.isEmpty || value.length > maxLength) {
    throw ApiError(400, 'invalid_artifact_$name', '$name is invalid.');
  }
  return value;
}

/// A structured result (for example classification decisions) is a small
/// document, not media: it is read whole by the browser after integrity
/// checks, so it carries a hard ceiling far below the media limit.
const workflowJsonArtifactMaxBytes = 1024 * 1024;
const _mediaArtifactMaxBytes = 100 * 1024 * 1024 * 1024;

int _maxArtifactBytes(String contentType) => contentType == 'application/json'
    ? workflowJsonArtifactMaxBytes
    : _mediaArtifactMaxBytes;

const _contentTypes = {
  'application/json',
  'image/jpeg',
  'image/png',
  'image/webp',
  'video/mp4',
  'video/webm',
  'audio/mpeg',
  'audio/wav',
  'audio/flac',
};
