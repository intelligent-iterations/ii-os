import 'package:googleapis/storage/v1.dart' as storage;
import 'package:googleapis_auth/auth_io.dart';
import 'package:shelf/shelf.dart';

import 'api_error.dart';
import 'asset_url_signer.dart';
import 'auth_service.dart';
import 'data_plane_connection.dart';
import 'data_plane_connection_validator.dart';
import 'domain.dart';
import 'http_support.dart';
import 'job_run_store.dart';
import 'organization.dart';
import 'organization_store.dart';
import 'retention_policy.dart';
import 'workspace_store.dart';

final class ConnectedDataApi {
  const ConnectedDataApi({
    required this.store,
    required this.brokerServiceAccount,
    required this.controlProjectId,
    required this.controlDatabaseId,
    required this.webOrigin,
  });

  final WorkspaceStore store;
  final String brokerServiceAccount;
  final String controlProjectId;
  final String controlDatabaseId;
  final String webOrigin;

  Future<Map<String, Object?>> resolveVerifiedArtifactMetadata({
    required String workspaceId,
    required String jobId,
    required Map<String, Object?> artifact,
    bool ghostMode = false,
  }) async {
    final objectName = artifact['path'];
    final generation = artifact['generation'];
    final contentType = artifact['content_type'];
    if (objectName is! String ||
        !objectName.startsWith(
          'workspaces/$workspaceId/${ghostMode ? 'ghost' : 'runs'}/$jobId/',
        ) ||
        generation is! String ||
        !RegExp(r'^[1-9][0-9]{0,29}$').hasMatch(generation) ||
        contentType is! String ||
        contentType.isEmpty) {
      throw const ApiError(
        409,
        'asset_metadata_invalid',
        'The asset metadata is unavailable.',
      );
    }
    final recordedSize = _positiveArtifactSize(artifact['size_bytes']);
    final recordedSha = artifact['sha256'];
    if (recordedSize != null &&
        recordedSha is String &&
        RegExp(r'^[a-f0-9]{64}$').hasMatch(recordedSha)) {
      return {...artifact, 'size_bytes': recordedSize, 'sha256': recordedSha};
    }

    final connection = await store.requireConnection(
      workspaceId,
      permission: 'assets.read',
    );
    if (connection.emulated) {
      throw const ApiError(
        409,
        'asset_metadata_invalid',
        'The asset metadata is unavailable.',
      );
    }
    try {
      final client = await clientViaApplicationDefaultCredentials(
        scopes: const ['https://www.googleapis.com/auth/cloud-platform'],
      );
      try {
        final remote = await storage.StorageApi(
          client,
        ).objects.get(connection.bucket, objectName, generation: generation);
        final remoteSize = remote is storage.Object
            ? int.tryParse(remote.size ?? '')
            : null;
        final remoteMetadata = remote is storage.Object
            ? remote.metadata
            : null;
        final remoteSha = remoteMetadata?['ii-os-sha256'];
        return recoveredArtifactMetadata(
          artifact: artifact,
          remoteGeneration: remote is storage.Object ? remote.generation : null,
          remoteContentType: remote is storage.Object
              ? remote.contentType
              : null,
          remoteSizeBytes: remoteSize,
          remoteSha256: remoteSha,
        );
      } finally {
        client.close();
      }
    } on ApiError {
      rethrow;
    } catch (_) {
      throw const ApiError(
        409,
        'asset_metadata_invalid',
        'The asset metadata is unavailable.',
      );
    }
  }

  Future<Response?> handleAuthenticated(
    Request request,
    String requestId,
    List<String> path,
    AuthenticatedUser actor,
  ) async {
    if (_isOrganizationConnectionPath(path)) {
      final organizationId = path[2];
      final organizations = OrganizationStore(
        store.firestore,
        emulated: store.emulated,
      );
      final membership = await organizations.getMembership(
        organizationId,
        actor.uid,
      );
      if (request.method == 'GET' && path.length == 4) {
        if (membership?.allows(OrganizationCapability.read) != true) {
          throw const ApiError(
            403,
            'forbidden',
            'Your organization role does not allow this action.',
          );
        }
        final connection = await organizations.getConnection(organizationId);
        if (connection == null) {
          throw const ApiError(
            409,
            'organization_not_connected',
            'Connect this organization to its customer-owned data plane first.',
          );
        }
        return jsonResponse(200, {
          'data': connection.toJson(),
        }, requestId: requestId);
      }
      if (request.method == 'POST' &&
          path.length == 5 &&
          path[4] == 'validate') {
        if (membership?.allows(OrganizationCapability.credentialsManage) !=
            true) {
          throw const ApiError(
            403,
            'forbidden',
            'Your organization role does not allow this action.',
          );
        }
        final candidate = DataPlaneConnection.fromJson(
          await readJsonObject(request),
          emulated: store.emulated,
        );
        if (!candidate.isOrganizationBound ||
            candidate.organizationId != organizationId) {
          throw const ApiError(
            400,
            'organization_connection_mismatch',
            'The connection is bound to a different ii-os organization.',
          );
        }
        _requireFixedBoundary(candidate);
        final validation = await DataPlaneConnectionValidator(
          connection: candidate,
          firestore: store.firestore,
        ).validate();
        if (validation['status'] == 'ready') {
          await organizations.saveConnection(organizationId, candidate);
        }
        return jsonResponse(200, {'data': validation}, requestId: requestId);
      }
    }
    if (_isWorkspaceConnectionPath(path)) {
      final workspaceId = path[2];
      if (request.method == 'GET' && path.length == 4) {
        await store.requireAccess(actor, workspaceId, Capability.workspaceRead);
        final connection = await store.requireConnection(
          workspaceId,
          permission: 'assets.read',
        );
        return jsonResponse(200, {
          'data': connection.toJson(),
        }, requestId: requestId);
      }
      if (request.method == 'POST' &&
          path.length == 5 &&
          path[4] == 'validate') {
        await store.requireAccess(
          actor,
          workspaceId,
          Capability.workspaceManage,
        );
        final workspace = await store.getWorkspace(workspaceId);
        if (workspace.organizationId.isNotEmpty &&
            workspace.connection == null) {
          throw const ApiError(
            409,
            'organization_connection_required',
            'Connect the organization that owns this workspace. Only an '
                'existing legacy workspace connection can be rotated during '
                'migration.',
          );
        }
        final candidate = DataPlaneConnection.fromJson(
          await readJsonObject(request),
          emulated: store.emulated,
        );
        if (candidate.workspaceId != workspaceId) {
          throw const ApiError(
            400,
            'workspace_connection_mismatch',
            'The connection is bound to a different ii-os workspace.',
          );
        }
        _requireFixedBoundary(candidate);
        final validation = await DataPlaneConnectionValidator(
          connection: candidate,
          firestore: store.firestore,
        ).validate();
        if (validation['status'] == 'ready') {
          await store.saveConnection(workspaceId, candidate);
        }
        return jsonResponse(200, {'data': validation}, requestId: requestId);
      }
    }
    if (request.method != 'GET' || !_isReadUrlPath(path)) return null;

    final workspaceId = path[2];
    final jobId = path[4];
    await store.requireAccess(actor, workspaceId, Capability.jobsRead);
    final recorded = await store.readRecordedJob(workspaceId, jobId);
    final job = recorded.job;
    final ghostMode = job['ghostMode'] == true;
    final objectName = request.url.queryParameters['object']?.trim() ?? '';
    final artifacts = (job['artifacts'] as List<Object?>? ?? const [])
        .map(_jsonMap)
        .whereType<Map<String, Object?>>();
    final expectedPrefix =
        'workspaces/$workspaceId/${ghostMode ? 'ghost' : 'runs'}/$jobId/';
    if (!objectName.startsWith(expectedPrefix) ||
        !artifacts.any((artifact) => artifact['path'] == objectName)) {
      throw const ApiError(404, 'asset_not_found', 'Asset not found.');
    }
    final recordedArtifact = artifacts.firstWhere(
      (artifact) => artifact['path'] == objectName,
    );
    final artifact = await resolveVerifiedArtifactMetadata(
      workspaceId: workspaceId,
      jobId: jobId,
      artifact: recordedArtifact,
      ghostMode: ghostMode,
    );
    final generation = artifact['generation'];
    final sizeBytes = artifact['size_bytes'];
    final sha256 = artifact['sha256'];
    final contentType = artifact['content_type'];
    if (generation is! String ||
        !RegExp(r'^[1-9][0-9]{0,29}$').hasMatch(generation) ||
        sizeBytes is! int ||
        sizeBytes <= 0 ||
        sha256 is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256) ||
        contentType is! String ||
        contentType.isEmpty) {
      throw const ApiError(
        409,
        'asset_metadata_invalid',
        'The asset metadata is unavailable.',
      );
    }
    final signer = await signerForWorkspace(workspaceId);
    final signed = await signer.signReadUrl(
      objectName,
      generation: generation,
      cacheIdentity: AssetReadGrantCacheIdentity(
        workspaceId: workspaceId,
        jobId: jobId,
        sizeBytes: sizeBytes,
        sha256: sha256,
        contentType: contentType,
      ),
    );
    // Opening media is what keeps it: an organization's window counts from the
    // last time someone looked, not from when the media was made.
    final workspace = await store.getWorkspace(workspaceId);
    await store.recordArtifactPlay(
      jobId: jobId,
      record: recorded.record,
      retentionDays: artifactRetentionDays(
        workspace.artifactStorage?.retentionDays,
      ),
    );
    return jsonResponse(200, {
      'data': {
        'url': signed.url,
        'expiresAt': signed.expiresAt.toIso8601String(),
        'workspaceId': workspaceId,
        'jobId': jobId,
        'bucket': signer.connection.bucket,
        'object': objectName,
        'generation': generation,
        'sizeBytes': sizeBytes,
        'sha256': sha256,
        'contentType': contentType,
      },
    }, requestId: requestId);
  }

  Future<AssetUrlSigner> signerForWorkspace(String workspaceId) async =>
      AssetUrlSigner(
        await store.requireConnection(workspaceId, permission: 'assets.read'),
      );

  void _requireFixedBoundary(DataPlaneConnection candidate) {
    if (!store.emulated &&
        candidate.dataServiceAccount != brokerServiceAccount) {
      throw const ApiError(
        400,
        'invalid_broker_identity',
        'The tenant must grant the configured ii-os broker identity.',
      );
    }
    if (candidate.authProjectId != controlProjectId ||
        candidate.databaseId != controlDatabaseId ||
        candidate.webOrigin != webOrigin) {
      throw const ApiError(
        400,
        'invalid_control_plane_boundary',
        'Auth, database, and web origin are fixed by ii-os.',
      );
    }
  }
}

bool _isWorkspaceConnectionPath(List<String> path) =>
    (path.length == 4 || (path.length == 5 && path[4] == 'validate')) &&
    path[0] == 'v1' &&
    path[1] == 'workspaces' &&
    path[3] == 'connection';

bool _isOrganizationConnectionPath(List<String> path) =>
    (path.length == 4 || (path.length == 5 && path[4] == 'validate')) &&
    path[0] == 'v1' &&
    path[1] == 'organizations' &&
    path[3] == 'connection';

bool _isReadUrlPath(List<String> path) =>
    path.length == 7 &&
    path[0] == 'v1' &&
    path[1] == 'workspaces' &&
    path[3] == 'jobs' &&
    path[5] == 'artifacts' &&
    path[6] == 'read-url';

Map<String, Object?>? _jsonMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map<Object?, Object?>) return value.cast<String, Object?>();
  return null;
}

int? _positiveArtifactSize(Object? value) {
  if (value is! num ||
      !value.isFinite ||
      value <= 0 ||
      value != value.truncateToDouble()) {
    return null;
  }
  return value.toInt();
}

Map<String, Object?> recoveredArtifactMetadata({
  required Map<String, Object?> artifact,
  required String? remoteGeneration,
  required String? remoteContentType,
  required int? remoteSizeBytes,
  required String? remoteSha256,
}) {
  if (remoteGeneration != artifact['generation'] ||
      remoteContentType != artifact['content_type'] ||
      remoteSizeBytes == null ||
      remoteSizeBytes <= 0 ||
      remoteSizeBytes > 100 * 1024 * 1024 * 1024 ||
      remoteSha256 == null ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(remoteSha256)) {
    throw const ApiError(
      409,
      'asset_metadata_invalid',
      'The asset metadata is unavailable.',
    );
  }
  return {...artifact, 'size_bytes': remoteSizeBytes, 'sha256': remoteSha256};
}
