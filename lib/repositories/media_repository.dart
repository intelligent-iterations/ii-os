import '../models/models.dart';
import '../services/api_client.dart';
import '../services/artifact_read_url_cache.dart';
import '../services/source_asset_read_grant.dart';
import '../services/verified_artifact_media.dart';
import 'generation_history_repository.dart';

abstract interface class WorkspaceMediaRepository {
  Future<VerifiedArtifactMedia> readVerifiedArtifact({
    required String workspaceId,
    required String jobId,
    required String expectedBucket,
    required JsonMap artifact,
    bool transient = false,
  });

  /// Reads a workspace source asset the caller holds only an id for.
  Future<VerifiedArtifactMedia> readVerifiedSourceAsset({
    required String workspaceId,
    required String assetId,
    required String expectedBucket,
  });

  GenerationHistoryRepository history({
    required String workspaceId,
    required int retentionDays,
  });
}

final class MediaRepository implements WorkspaceMediaRepository {
  MediaRepository({required this.api});

  final ApiClient api;
  final ArtifactReadUrlCache _readUrls = ArtifactReadUrlCache(
    refreshBefore: const Duration(minutes: 2),
  );
  final VerifiedArtifactMediaCache _verifiedMedia =
      VerifiedArtifactMediaCache();
  final Map<String, GenerationHistoryRepository> _histories = {};
  final Map<String, ArtifactAuthorizationIdentity> _sourceAssetIdentities =
      {};

  Future<ArtifactReadGrant> readArtifactUrl({
    required String workspaceId,
    required String jobId,
    required String expectedBucket,
    required JsonMap artifact,
  }) async {
    final expected = _authorizationIdentity(
      workspaceId: workspaceId,
      jobId: jobId,
      expectedBucket: expectedBucket,
      artifact: artifact,
    );
    return _readUrls.resolve(
      expected: expected,
      load: () => api.get(
        'v1/workspaces/$workspaceId/jobs/'
        '${Uri.encodeComponent(jobId)}/artifacts/read-url',
        query: {'object': expected.objectName},
      ),
    );
  }

  @override
  Future<VerifiedArtifactMedia> readVerifiedArtifact({
    required String workspaceId,
    required String jobId,
    required String expectedBucket,
    required JsonMap artifact,
    bool transient = false,
  }) async {
    final expected = _authorizationIdentity(
      workspaceId: workspaceId,
      jobId: jobId,
      expectedBucket: expectedBucket,
      artifact: artifact,
    );
    Future<VerifiedArtifactMedia> load() async {
      final grant = transient
          ? await ArtifactReadUrlCache(refreshBefore: Duration.zero).resolve(
              expected: expected,
              load: () => api.get(
                'v1/workspaces/$workspaceId/jobs/'
                '${Uri.encodeComponent(jobId)}/artifacts/read-url',
                query: {'object': expected.objectName},
              ),
            )
          : await readArtifactUrl(
              workspaceId: workspaceId,
              jobId: jobId,
              expectedBucket: expectedBucket,
              artifact: artifact,
            );
      return downloadVerifiedArtifactMedia(
        api: api,
        grant: grant,
        expected: expected,
        maxBytes: maxPreviewArtifactBytes,
      );
    }

    if (transient) return load();
    return _verifiedMedia.resolve(expected: expected, load: load);
  }

  @override
  Future<VerifiedArtifactMedia> readVerifiedSourceAsset({
    required String workspaceId,
    required String assetId,
    required String expectedBucket,
  }) async {
    Future<SourceAssetReadAuthorization> authorize() async =>
        SourceAssetReadAuthorization.parse(
          asJsonMap(
            (await api.get(
              'v1/workspaces/$workspaceId/source-assets/'
              '${Uri.encodeComponent(assetId)}/read-url',
            ))['data'],
          ),
          workspaceId: workspaceId,
          assetId: assetId,
          expectedBucket: expectedBucket,
        );

    Future<VerifiedArtifactMedia> download(
      SourceAssetReadAuthorization authorization,
    ) => downloadVerifiedArtifactMedia(
      api: api,
      grant: authorization.grant,
      expected: authorization.expected,
      maxBytes: maxPreviewArtifactBytes,
    );

    // A source asset is immutable once ready, so a previously resolved
    // identity serves the media cache without authorizing again.
    final cacheKey = '$workspaceId:$assetId';
    final known = _sourceAssetIdentities[cacheKey];
    if (known != null) {
      return _verifiedMedia.resolve(
        expected: known,
        load: () async => download(await authorize()),
      );
    }
    final authorization = await authorize();
    _sourceAssetIdentities[cacheKey] = authorization.expected;
    return _verifiedMedia.resolve(
      expected: authorization.expected,
      load: () => download(authorization),
    );
  }

  Future<VerifiedArtifactMedia> readGrantedArtifact({
    required ArtifactReadGrant grant,
    required ArtifactAuthorizationIdentity expected,
  }) {
    return _verifiedMedia.resolve(
      expected: expected,
      load: () => downloadVerifiedArtifactMedia(
        api: api,
        grant: grant,
        expected: expected,
        maxBytes: maxPreviewArtifactBytes,
      ),
    );
  }

  @override
  GenerationHistoryRepository history({
    required String workspaceId,
    required int retentionDays,
  }) {
    final key = '$workspaceId:$retentionDays';
    return _histories.putIfAbsent(
      key,
      () => GenerationHistoryRepository(
        api: api,
        workspaceId: workspaceId,
        retentionDays: retentionDays,
      ),
    );
  }

  void clear() {
    _readUrls.clear();
    _verifiedMedia.clear();
    _sourceAssetIdentities.clear();
    for (final history in _histories.values) {
      history.dispose();
    }
    _histories.clear();
  }

  void dispose() => clear();
}

ArtifactAuthorizationIdentity _authorizationIdentity({
  required String workspaceId,
  required String jobId,
  required String expectedBucket,
  required JsonMap artifact,
}) {
  final objectName = artifact['path']?.toString() ?? '';
  final generation = artifact['generation']?.toString() ?? '';
  final sizeBytes = _positiveInt(artifact['size_bytes']);
  final sha256 = artifact['sha256']?.toString().toLowerCase() ?? '';
  final contentType = artifact['content_type']?.toString().toLowerCase() ?? '';
  final normalPrefix = 'workspaces/$workspaceId/runs/$jobId/';
  final ghostPrefix = 'workspaces/$workspaceId/ghost/$jobId/';
  if (workspaceId.isEmpty ||
      jobId.isEmpty ||
      expectedBucket.isEmpty ||
      objectName.isEmpty ||
      (!objectName.startsWith(normalPrefix) &&
          !objectName.startsWith(ghostPrefix)) ||
      !RegExp(r'^[1-9][0-9]{0,29}$').hasMatch(generation) ||
      sizeBytes == null ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256) ||
      !supportedArtifactContentTypes.contains(contentType)) {
    throw const FormatException('The media artifact is unavailable.');
  }
  return ArtifactAuthorizationIdentity(
    workspaceId: workspaceId,
    jobId: jobId,
    bucket: expectedBucket,
    objectName: objectName,
    generation: generation,
    sizeBytes: sizeBytes,
    sha256: sha256,
    contentType: contentType,
  );
}

int? _positiveInt(Object? value) {
  final parsed = switch (value) {
    int number => number,
    num number when number.isFinite && number == number.truncateToDouble() =>
      number.toInt(),
    String text when RegExp(r'^[1-9][0-9]*$').hasMatch(text.trim()) =>
      int.tryParse(text.trim()),
    _ => null,
  };
  return parsed != null && parsed > 0 ? parsed : null;
}
