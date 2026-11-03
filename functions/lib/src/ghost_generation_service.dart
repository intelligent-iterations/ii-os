import 'package:_discoveryapis_commons/_discoveryapis_commons.dart';
import 'package:google_cloud_firestore/google_cloud_firestore.dart';
import 'package:googleapis/storage/v1.dart' as storage;
import 'package:googleapis_auth/auth_io.dart';

import 'api_error.dart';
import 'connected_data_api.dart';

extension GhostGenerationConsumption on ConnectedDataApi {
  /// Deletes a Ghost-mode generation after its bytes are safely in-browser.
  ///
  /// A minimal one-day tombstone remains so repeated acknowledgements are
  /// idempotent. Prompts, inputs, workflow identity, and media metadata are
  /// scrubbed, and the record is never returned by history endpoints.
  Future<Map<String, Object?>> consumeGhostJob({
    required String workspaceId,
    required String jobId,
  }) async {
    final ref = store.firestore.collection('jobRuns').doc(jobId);
    final snapshot = await ref.get();
    final job = snapshot.data();
    if (!snapshot.exists || job == null || job['workspaceId'] != workspaceId) {
      throw const ApiError(404, 'job_not_found', 'Job not found.');
    }
    if (job['ghostMode'] != true) {
      throw const ApiError(
        409,
        'job_not_ghost',
        'Only a Ghost-mode generation can be consumed.',
      );
    }
    if (job['status'] == 'consumed') {
      return {'jobId': jobId, 'status': 'consumed', 'consumed': true};
    }
    if (!const {'completed', 'failed', 'cancelled'}.contains(job['status'])) {
      throw const ApiError(
        409,
        'ghost_job_not_terminal',
        'The Ghost-mode generation is still running.',
      );
    }

    final artifacts = (job['artifacts'] as List<Object?>? ?? const [])
        .map(_jsonMap)
        .whereType<Map<String, Object?>>()
        .toList(growable: false);
    final expectedPrefix = 'workspaces/$workspaceId/ghost/$jobId/';
    if (artifacts.any(
      (artifact) =>
          artifact['path'] is! String ||
          !(artifact['path']! as String).startsWith(expectedPrefix) ||
          artifact['generation'] is! String,
    )) {
      throw const ApiError(
        409,
        'ghost_artifact_invalid',
        'The Ghost-mode artifact identity is invalid.',
      );
    }

    final sources = await _deletableGhostSources(job, jobId);
    final connection = await store.requireConnection(
      workspaceId,
      permission: 'assets.write',
    );
    if (!connection.emulated) {
      final client = await clientViaApplicationDefaultCredentials(
        scopes: const ['https://www.googleapis.com/auth/cloud-platform'],
      );
      try {
        final api = storage.StorageApi(client);
        for (final artifact in artifacts) {
          await _deleteObject(
            api,
            connection.bucket,
            artifact['path']! as String,
            artifact['generation']! as String,
          );
        }
        for (final source in sources) {
          await _deleteObject(
            api,
            connection.bucket,
            source.data['path']! as String,
            source.data['generation']! as String,
          );
        }
      } catch (_) {
        throw const ApiError(
          409,
          'ghost_cleanup_failed',
          'The temporary workspace media could not be deleted.',
        );
      } finally {
        client.close();
      }
    }

    for (final source in sources) {
      final latest = await source.ref.get();
      if (latest.exists && latest.data()?['ghostMode'] == true) {
        await source.ref.delete();
      }
    }
    final now = Timestamp.now();
    await ref.set({
      'workspaceId': workspaceId,
      'jobId': jobId,
      'provider': 'ghost',
      'kind': 'ghost-generation',
      'ghostMode': true,
      'events': <Map<String, Object?>>[
        {'kind': 'consumed', 'at': now},
      ],
      'status': 'consumed',
      'consumedAt': now,
      'updatedAt': now,
      'expiresAt': Timestamp.fromDate(
        DateTime.now().toUtc().add(const Duration(days: 1)),
      ),
    });
    return {'jobId': jobId, 'status': 'consumed', 'consumed': true};
  }

  Future<List<_GhostSource>> _deletableGhostSources(
    Map<String, Object?> job,
    String currentJobId,
  ) async {
    final sourceAssetIds = (job['sourceAssetIds'] as List<Object?>? ?? const [])
        .whereType<String>()
        .toSet();
    final result = <_GhostSource>[];
    for (final assetId in sourceAssetIds) {
      final sourceRef = store.firestore.collection('sourceAssets').doc(assetId);
      final sourceSnapshot = await sourceRef.get();
      final source = sourceSnapshot.data();
      if (!sourceSnapshot.exists ||
          source == null ||
          source['workspaceId'] != job['workspaceId'] ||
          source['ghostMode'] != true ||
          source['path'] is! String ||
          !(source['path']! as String).startsWith(
            'workspaces/${job['workspaceId']}/ghost-source-assets/$assetId/',
          ) ||
          source['generation'] is! String) {
        continue;
      }
      final users = await store.firestore
          .collection('jobRuns')
          .where('sourceAssetIds', WhereFilter.arrayContains, assetId)
          .get();
      final stillNeeded = users.docs.any((doc) {
        if (doc.ref.id == currentJobId) return false;
        final other = doc.data();
        if (const {
          'completed',
          'failed',
          'cancelled',
          'consumed',
        }.contains(other['status'])) {
          return false;
        }
        return true;
      });
      if (!stillNeeded) {
        result.add(_GhostSource(ref: sourceRef, data: source));
      }
    }
    return result;
  }
}

Future<void> _deleteObject(
  storage.StorageApi api,
  String bucket,
  String objectName,
  String generation,
) async {
  try {
    await api.objects.delete(bucket, objectName, generation: generation);
  } on DetailedApiRequestError catch (error) {
    if (error.status != 404) rethrow;
  }
}

final class _GhostSource {
  const _GhostSource({required this.ref, required this.data});

  final DocumentReference<Map<String, Object?>> ref;
  final Map<String, Object?> data;
}

Map<String, Object?>? _jsonMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map<Object?, Object?>) return value.cast<String, Object?>();
  return null;
}
