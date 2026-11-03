part of 'api.dart';

extension _StoryboardAnimationRoute on IiOsApi {
  Future<Response> _animateStoryboardPanel(
    Request request,
    String requestId,
    AuthenticatedUser actor,
    String workspaceId,
    List<String> path,
  ) async {
    await store.requireAccess(actor, workspaceId, Capability.jobsTrigger);
    final body = await readJsonObject(request);
    final workflowKey = requiredString(body, 'workflowKey', maxLength: 400);
    final parsedWorkflow = parseWorkflowKey(workflowKey);
    if (parsedWorkflow.workflowId != 'image-to-video') {
      throw const ApiError(
        409,
        'storyboard_video_workflow_required',
        'Panel animation must use an image-to-video workflow.',
      );
    }
    final input = _storyboardVideoInput(body['input']);
    final prompt = requiredString(input, 'prompt', maxLength: 8000);
    final duration = _storyboardVideoDuration(input['duration_seconds']);
    final storyboard = await store.getStoryboard(workspaceId, path[4]);
    final panels = _storyboardMaps(storyboard['panels']);
    final panel = panels.cast<Map<String, Object?>?>().firstWhere(
      (candidate) => candidate?['id'] == path[6],
      orElse: () => null,
    );
    if (panel == null) {
      throw const ApiError(
        404,
        'storyboard_panel_not_found',
        'Storyboard panel not found.',
      );
    }
    final selectedImage = storyboardSelectedPanelImage(panel);
    final sourceJobId = selectedImage?['jobId'] ?? panel['jobId'];
    if (sourceJobId is! String || sourceJobId.isEmpty) {
      throw const ApiError(
        409,
        'storyboard_panel_image_required',
        'Generate the panel image before animating it.',
      );
    }
    final workspace = await store.getWorkspace(workspaceId);
    return _audited(
      requestId: requestId,
      actor: actor,
      workspaceId: workspaceId,
      action: 'storyboard.panel.animate',
      targetType: 'storyboard_panel',
      targetId: path[6],
      metadata: {
        'storyboardId': path[4],
        'panelId': path[6],
        'sourceJobId': sourceJobId,
        'workflowKey': workflowKey,
      },
      execute: () async {
        final sourceAssetId = await _storyboardPanelSourceAsset(
          workspace: workspace,
          workspaceId: workspaceId,
          actor: actor,
          sourceJobId: sourceJobId,
          selectedImage: selectedImage,
          panelId: path[6],
          requestId: requestId,
        );
        final recorded = await store.recordStoryboardPanelVideoGeneration(
          workspaceId: workspaceId,
          storyboardId: path[4],
          panelId: path[6],
          jobId: requestId,
          generationPrompt: prompt,
          durationSeconds: duration,
          updatedBy: actor.uid,
        );
        await assetRetention.releaseRemovedGraph(
          workspaceId: workspaceId,
          before: storyboardAssetAttachmentGraph(storyboard),
          after: storyboardAssetAttachmentGraph(recorded),
          retentionDays: artifactRetentionDays(
            workspace.artifactStorage?.retentionDays,
          ),
        );
        Map<String, Object?> job;
        try {
          job = await workflows.dispatch(
            workspace: workspace,
            actorUid: actor.uid,
            requestId: requestId,
            workflowKeyValue: workflowKey,
            input: {
              ...input,
              'source_asset_id': sourceAssetId,
              'prompt': prompt,
              'duration_seconds': duration,
            },
            retentionAttachment: {
              'kind': 'storyboard_panel_video',
              'storyboardId': path[4],
              'panelId': path[6],
            },
            notificationDeepLink: Uri(
              pathSegments: [
                '',
                'workspaces',
                workspaceId,
                'storyboards',
                path[4],
              ],
              queryParameters: {'panel': path[6], 'view': 'animate'},
            ).toString(),
          );
        } on Object catch (error) {
          final code = error is ApiError
              ? error.code
              : error.runtimeType.toString();
          final message = error is ApiError
              ? error.message
              : 'The animation request could not be dispatched.';
          await store.recordStoryboardPanelVideoGenerationFailure(
            workspaceId: workspaceId,
            storyboardId: path[4],
            panelId: path[6],
            jobId: requestId,
            code: code,
            message: message,
            updatedBy: actor.uid,
          );
          rethrow;
        }
        final updated = await store.getStoryboard(workspaceId, path[4]);
        return {
          'storyboard': await _withStoryboardJobs(workspace, updated),
          'job': job,
        };
      },
    );
  }

  Future<String> _storyboardPanelSourceAsset({
    required Workspace workspace,
    required String workspaceId,
    required AuthenticatedUser actor,
    required String sourceJobId,
    required Map<String, Object?>? selectedImage,
    required String panelId,
    required String requestId,
  }) async {
    final sourceJob = await workflows.getJob(workspace, sourceJobId);
    final artifact = _storyboardPanelImageArtifact(sourceJob, selectedImage);
    final path = artifact['path'] as String;
    final contentType = artifact['content_type'] as String;
    if (!path.startsWith('workspaces/$workspaceId/runs/$sourceJobId/')) {
      throw const ApiError(
        409,
        'storyboard_panel_image_invalid',
        'The generated panel image is outside its expected workspace run.',
      );
    }
    final extension = switch (contentType) {
      'image/jpeg' => 'jpg',
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => throw const ApiError(
        409,
        'storyboard_panel_image_unsupported',
        'The generated panel image format cannot be used as a source.',
      ),
    };
    final asset = await workflowApi.sourceAssets.registerWorkspaceObject(
      workspaceId: workspaceId,
      actorUid: actor.uid,
      objectName: path,
      generation: artifact['generation'] as String? ?? '',
      filename: 'storyboard-panel-$panelId-$requestId.$extension',
      contentType: contentType,
      retentionDays: artifactRetentionDays(
        workspace.artifactStorage?.retentionDays,
      ),
    );
    return asset['assetId']! as String;
  }
}

Map<String, Object?> _storyboardVideoInput(Object? value) {
  if (value is! Map) {
    throw const ApiError(
      400,
      'invalid_job_input',
      'Storyboard animation input is invalid.',
    );
  }
  final input = value.cast<String, Object?>();
  return {...input}..remove('source_asset_id');
}

int _storyboardVideoDuration(Object? value) {
  if (value is! num || value.toInt() != value || value < 2 || value > 20) {
    throw const ApiError(
      400,
      'invalid_storyboard_video_duration',
      'Panel animation duration must be between 2 and 20 seconds.',
    );
  }
  return value.toInt();
}

Map<String, Object?> _storyboardPanelImageArtifact(
  Map<String, Object?> job,
  Map<String, Object?>? selected,
) {
  for (final raw in (job['artifacts'] as List<Object?>? ?? const [])) {
    if (raw is! Map) continue;
    final artifact = raw.cast<String, Object?>();
    final contentType = artifact['content_type'];
    final path = artifact['path'];
    if (contentType is String &&
        contentType.startsWith('image/') &&
        path is String &&
        path.isNotEmpty &&
        (selected == null ||
            (selected['path'] == path &&
                selected['generation'] == artifact['generation']))) {
      return artifact;
    }
  }
  throw const ApiError(
    409,
    'storyboard_panel_image_required',
    'The panel image must finish generating before it can be used.',
  );
}
