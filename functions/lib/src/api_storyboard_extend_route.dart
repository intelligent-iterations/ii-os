part of 'api.dart';

const int storyboardExtendMaxFrameBytes = 25 * 1024 * 1024;

extension _StoryboardExtendRoute on IiOsApi {
  Future<Response> _prepareStoryboardPanelExtendUpload(
    Request request,
    String requestId,
    AuthenticatedUser actor,
    String workspaceId,
    List<String> path,
  ) async {
    await store.requireAccess(actor, workspaceId, Capability.jobsTrigger);
    final body = await readJsonObject(request);
    final sourcePanelId = requiredString(body, 'sourcePanelId', maxLength: 100);
    final contentType = requiredString(body, 'contentType', maxLength: 100);
    if (contentType != 'image/png') {
      throw const ApiError(
        400,
        'invalid_storyboard_extend_content_type',
        'Extended panel frames must be uploaded as image/png.',
      );
    }
    final sizeBytes = body['sizeBytes'];
    if (sizeBytes is! num ||
        sizeBytes.toInt() != sizeBytes ||
        sizeBytes <= 0 ||
        sizeBytes > storyboardExtendMaxFrameBytes) {
      throw const ApiError(
        400,
        'invalid_storyboard_extend_size',
        'The extended frame must be a positive size under 25 MiB.',
      );
    }
    final sha256Hex = requiredString(body, 'sha256', maxLength: 64);
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256Hex.toLowerCase())) {
      throw const ApiError(
        400,
        'invalid_storyboard_extend_sha256',
        'The extended frame checksum is invalid.',
      );
    }
    final storyboard = await store.getStoryboard(workspaceId, path[4]);
    final panels = _storyboardMaps(storyboard['panels']);
    if (!panels.any((panel) => panel['id'] == path[6])) {
      throw const ApiError(
        404,
        'storyboard_panel_not_found',
        'Storyboard panel not found.',
      );
    }
    final sourcePanel = panels.cast<Map<String, Object?>?>().firstWhere(
      (candidate) => candidate?['id'] == sourcePanelId,
      orElse: () => null,
    );
    if (sourcePanel == null) {
      throw const ApiError(
        404,
        'storyboard_panel_not_found',
        'Source storyboard panel not found.',
      );
    }
    final sourceVideoJobId = sourcePanel['videoJobId'];
    if (sourceVideoJobId is! String || sourceVideoJobId.isEmpty) {
      throw const ApiError(
        409,
        'storyboard_panel_video_required',
        'Animate the selected panel before extending from it.',
      );
    }
    final workspace = await store.getWorkspace(workspaceId);
    final sourceVideoJob = await workflows.getJob(workspace, sourceVideoJobId);
    final videoArtifact = _storyboardPanelVideoArtifact(sourceVideoJob);
    final videoPath = videoArtifact['path']! as String;
    if (!videoPath.startsWith(
      'workspaces/$workspaceId/runs/$sourceVideoJobId/',
    )) {
      throw const ApiError(
        409,
        'storyboard_panel_video_invalid',
        'The generated panel video is outside its expected workspace run.',
      );
    }
    final objectName =
        'workspaces/$workspaceId/runs/$requestId/'
        'extended-frame.png';
    final signer = await connectedDataApi.signerForWorkspace(workspaceId);
    final grant = await signer.signWriteUrl(
      objectName: objectName,
      contentType: contentType,
      sha256Hex: sha256Hex.toLowerCase(),
    );
    return _audited(
      requestId: requestId,
      actor: actor,
      workspaceId: workspaceId,
      action: 'storyboard.panel.extend.prepare',
      targetType: 'storyboard_panel',
      targetId: path[6],
      metadata: {
        'storyboardId': path[4],
        'panelId': path[6],
        'sourcePanelId': sourcePanelId,
      },
      execute: () async => {
        'jobId': requestId,
        'uploadUrl': grant.url,
        'uploadHeaders': grant.headers,
        'uploadExpiresAt': grant.expiresAt.toIso8601String(),
        'uploadBucket': signer.connection.bucket,
        'uploadObject': objectName,
      },
    );
  }

  Future<Response> _completeStoryboardPanelExtend(
    Request request,
    String requestId,
    AuthenticatedUser actor,
    String workspaceId,
    List<String> path,
  ) async {
    await store.requireAccess(actor, workspaceId, Capability.jobsTrigger);
    final body = await readJsonObject(request);
    final sourcePanelId = requiredString(body, 'sourcePanelId', maxLength: 100);
    final jobId = requiredString(body, 'jobId', maxLength: 200);
    final expectedSizeBytes = body['sizeBytes'] == null
        ? null
        : _storyboardExtendSize(body['sizeBytes']);
    final expectedSha256 = body['sha256'] == null
        ? null
        : _storyboardExtendSha256(body['sha256']);
    if ((expectedSizeBytes == null) != (expectedSha256 == null)) {
      throw const ApiError(
        400,
        'invalid_storyboard_extend_identity',
        'The extended frame identity is incomplete.',
      );
    }
    final storyboard = await store.getStoryboard(workspaceId, path[4]);
    final panels = _storyboardMaps(storyboard['panels']);
    if (!panels.any((panel) => panel['id'] == path[6])) {
      throw const ApiError(
        404,
        'storyboard_panel_not_found',
        'Storyboard panel not found.',
      );
    }
    final sourcePanel = panels.cast<Map<String, Object?>?>().firstWhere(
      (candidate) => candidate?['id'] == sourcePanelId,
      orElse: () => null,
    );
    if (sourcePanel == null) {
      throw const ApiError(
        404,
        'storyboard_panel_not_found',
        'Source storyboard panel not found.',
      );
    }
    final sourceVideoJobId = sourcePanel['videoJobId'];
    if (sourceVideoJobId is! String || sourceVideoJobId.isEmpty) {
      throw const ApiError(
        409,
        'storyboard_panel_video_required',
        'Animate the selected panel before extending from it.',
      );
    }
    final objectName =
        'workspaces/$workspaceId/runs/$jobId/'
        'extended-frame.png';
    final connection = await store.requireConnection(
      workspaceId,
      permission: 'assets.write',
    );
    final uploaded = await _storyboardExtendVerifyUpload(
      connection: connection,
      objectName: objectName,
      expectedSizeBytes: expectedSizeBytes,
      expectedSha256: expectedSha256,
    );
    final workspace = await store.getWorkspace(workspaceId);
    return _audited(
      requestId: requestId,
      actor: actor,
      workspaceId: workspaceId,
      action: 'storyboard.panel.extend.complete',
      targetType: 'storyboard_panel',
      targetId: path[6],
      metadata: {
        'storyboardId': path[4],
        'panelId': path[6],
        'sourcePanelId': sourcePanelId,
        'jobId': jobId,
      },
      execute: () async {
        await store.recordClientExtractedFrameJob(
          workspaceId: workspaceId,
          jobId: jobId,
          sourcePanelId: sourcePanelId,
          sourceVideoJobId: sourceVideoJobId,
          artifact: {
            'path': objectName,
            'generation': uploaded.generation,
            'content_type': uploaded.contentType,
            'size_bytes': uploaded.sizeBytes,
            'sha256': uploaded.sha256,
          },
          createdBy: actor.uid,
          retentionDays: artifactRetentionDays(
            workspace.artifactStorage?.retentionDays,
          ),
        );
        final attachment = 'storyboard/${path[4]}/panel/${path[6]}/image';
        final acquired = await assetRetention.protectRecord(
          workspaceId: workspaceId,
          collection: 'jobRuns',
          recordId: jobId,
          attachment: attachment,
        );
        late Map<String, Object?> updated;
        try {
          updated = await store.recordStoryboardPanelExtendedFrame(
            workspaceId: workspaceId,
            storyboardId: path[4],
            panelId: path[6],
            sourcePanelId: sourcePanelId,
            jobId: jobId,
            path: objectName,
            generation: uploaded.generation,
            contentType: uploaded.contentType,
            sizeBytes: uploaded.sizeBytes,
            sha256: uploaded.sha256,
            updatedBy: actor.uid,
          );
        } catch (_) {
          if (acquired) {
            await assetRetention.releaseRecordAttachments(
              workspaceId: workspaceId,
              collection: 'jobRuns',
              recordId: jobId,
              attachments: {attachment},
              retentionDays: artifactRetentionDays(
                workspace.artifactStorage?.retentionDays,
              ),
            );
          }
          rethrow;
        }
        return {
          'storyboard': await _withStoryboardJobs(workspace, updated),
          'job': await workflows.getJob(workspace, jobId),
        };
      },
    );
  }

  Future<
    ({String generation, String contentType, int sizeBytes, String sha256})
  >
  _storyboardExtendVerifyUpload({
    required DataPlaneConnection connection,
    required String objectName,
    required int? expectedSizeBytes,
    required String? expectedSha256,
  }) async {
    if (connection.emulated) {
      return (
        generation: '1',
        contentType: 'image/png',
        sizeBytes: expectedSizeBytes ?? 1,
        sha256: expectedSha256 ?? List.filled(64, '0').join(),
      );
    }
    final client = await clientViaApplicationDefaultCredentials(
      scopes: const ['https://www.googleapis.com/auth/cloud-platform'],
    );
    try {
      final remote = await storage.StorageApi(
        client,
      ).objects.get(connection.bucket, objectName);
      if (remote is! storage.Object ||
          remote.generation == null ||
          remote.size == null) {
        throw const ApiError(
          409,
          'storyboard_extend_upload_missing',
          'The extended frame upload was not found.',
        );
      }
      final contentType = remote.contentType ?? '';
      final sizeBytes = int.tryParse(remote.size!) ?? 0;
      final objectSha256 = remote.metadata?['ii-os-sha256'] ?? '';
      if (contentType != 'image/png' ||
          sizeBytes <= 0 ||
          sizeBytes > storyboardExtendMaxFrameBytes ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(objectSha256) ||
          (expectedSizeBytes != null && sizeBytes != expectedSizeBytes) ||
          (expectedSha256 != null && objectSha256 != expectedSha256)) {
        throw const ApiError(
          409,
          'storyboard_extend_upload_invalid',
          'The extended frame upload metadata does not match.',
        );
      }
      return (
        generation: remote.generation!,
        contentType: contentType,
        sizeBytes: sizeBytes,
        sha256: objectSha256,
      );
    } on ApiError {
      rethrow;
    } catch (_) {
      throw const ApiError(
        409,
        'storyboard_extend_upload_invalid',
        'The extended frame upload could not be verified.',
      );
    } finally {
      client.close();
    }
  }
}

int _storyboardExtendSize(Object? value) {
  if (value is! num ||
      value.toInt() != value ||
      value <= 0 ||
      value > storyboardExtendMaxFrameBytes) {
    throw const ApiError(
      400,
      'invalid_storyboard_extend_size',
      'The extended frame must be a positive size under 25 MiB.',
    );
  }
  return value.toInt();
}

String _storyboardExtendSha256(Object? value) {
  final sha256 = value?.toString().toLowerCase() ?? '';
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256)) {
    throw const ApiError(
      400,
      'invalid_storyboard_extend_sha256',
      'The extended frame checksum is invalid.',
    );
  }
  return sha256;
}

Map<String, Object?> _storyboardPanelVideoArtifact(Map<String, Object?> job) {
  for (final raw in (job['artifacts'] as List<Object?>? ?? const [])) {
    if (raw is! Map) continue;
    final artifact = raw.cast<String, Object?>();
    final contentType = artifact['content_type'];
    final path = artifact['path'];
    if (contentType is String &&
        contentType.startsWith('video/') &&
        path is String &&
        path.isNotEmpty) {
      return artifact;
    }
  }
  throw const ApiError(
    409,
    'storyboard_panel_video_required',
    'The source panel video must finish generating before it can be used.',
  );
}
