part of 'api.dart';

extension _VideoProjectRoutes on IiOsApi {
  Future<Response> _videoProjectRoute(
    Request request,
    String requestId,
    AuthenticatedUser actor,
    String workspaceId,
    List<String> path,
  ) async {
    if (path.length == 4 && request.method == 'GET') {
      final context = await store.requireAccessContext(
        actor,
        workspaceId,
        Capability.jobsRead,
      );
      final (projects, renderCapability) = await (
        store.listVideoProjects(workspaceId),
        workflows.discoverEditorRenderCapability(context.workspace),
      ).wait;
      return jsonResponse(200, {
        'projects': projects,
        'renderCapability': renderCapability.toJson(),
      }, requestId: requestId);
    }
    if (path.length == 5 && path[4] == 'render' && request.method == 'POST') {
      final context = await store.requireAccessContext(
        actor,
        workspaceId,
        Capability.jobsTrigger,
      );
      final body = await readJsonObject(request);
      final renderManifest = requiredString(
        body,
        'renderManifest',
        maxLength: 60000,
      );
      final ghostMode = _jobGhostMode(body['ghostMode']);
      final capability = await workflows.discoverEditorRenderCapability(
        context.workspace,
      );
      final workflowKey = capability.workflowKey;
      if (capability.status != ConnectedWorkflowStatus.available ||
          workflowKey == null) {
        throw const ApiError(
          409,
          'video_render_unavailable',
          'No compatible workspace render runner is connected.',
        );
      }
      return _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'video.editor.render.dispatch',
        targetType: 'video_editor_render',
        targetId: requestId,
        metadata: {
          'workflowKey': workflowKey,
          'requiredCapabilities': editorRenderRequiredCapabilities.toList()
            ..sort(),
          'minimumCpu': editorRenderMinimumCpu,
          'minimumRamMiB': editorRenderMinimumRamMiB,
        },
        execute: () => workflows.dispatch(
          workspace: context.workspace,
          actorUid: actor.uid,
          requestId: requestId,
          workflowKeyValue: workflowKey,
          input: {'render_manifest': renderManifest},
          notificationDeepLink: ghostMode
              ? null
              : Uri(
                  pathSegments: ['', 'workspaces', workspaceId, 'video-editor'],
                ).toString(),
          allowConnectedWorkflow: true,
          ghostMode: ghostMode,
        ),
      );
    }
    if (path.length == 4 && request.method == 'POST') {
      await store.requireAccess(actor, workspaceId, Capability.jobsTrigger);
      final body = await readJsonObject(request);
      return _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'video.project.create',
        targetType: 'video_project',
        execute: () => store.createVideoProject(
          workspaceId: workspaceId,
          createdBy: actor.uid,
          name: body['name'],
        ),
      );
    }
    if (path.length == 5 && request.method == 'GET') {
      await store.requireAccess(actor, workspaceId, Capability.jobsRead);
      return jsonResponse(200, {
        'project': await store.getVideoProject(workspaceId, path[4]),
      }, requestId: requestId);
    }
    if (path.length == 5 && request.method == 'PUT') {
      await store.requireAccess(actor, workspaceId, Capability.jobsTrigger);
      final body = await readJsonObject(request);
      return _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'video.project.save',
        targetType: 'video_project',
        targetId: path[4],
        execute: () async {
          final before = await store.getVideoProject(workspaceId, path[4]);
          final workspace = await store.getWorkspace(workspaceId);
          final saved = await store.saveVideoProject(
            workspaceId: workspaceId,
            projectId: path[4],
            updatedBy: actor.uid,
            body: body,
          );
          // Hold everything the project now refers to before letting go of
          // what it dropped, so media moved around inside one save is never
          // briefly unheld.
          for (final entry in videoProjectAssetAttachmentGraph(saved).entries) {
            final identity = entry.key.split('/');
            for (final attachment in entry.value) {
              await assetRetention.protectRecord(
                workspaceId: workspaceId,
                collection: identity.first,
                recordId: identity.last,
                attachment: attachment,
              );
            }
          }
          await assetRetention.releaseRemovedGraph(
            workspaceId: workspaceId,
            before: videoProjectAssetAttachmentGraph(before),
            after: videoProjectAssetAttachmentGraph(saved),
            retentionDays: artifactRetentionDays(
              workspace.artifactStorage?.retentionDays,
            ),
          );
          return saved;
        },
      );
    }
    if (path.length == 5 && request.method == 'DELETE') {
      await store.requireAccess(actor, workspaceId, Capability.jobsTrigger);
      return _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'video.project.delete',
        targetType: 'video_project',
        targetId: path[4],
        execute: () async {
          final project = await store.getVideoProject(workspaceId, path[4]);
          final workspace = await store.getWorkspace(workspaceId);
          await store.deleteVideoProject(workspaceId, path[4]);
          // Nothing holds this media any more, so its window starts now.
          await assetRetention.releaseRemovedGraph(
            workspaceId: workspaceId,
            before: videoProjectAssetAttachmentGraph(project),
            after: const {},
            retentionDays: artifactRetentionDays(
              workspace.artifactStorage?.retentionDays,
            ),
          );
          return <String, Object?>{'id': path[4], 'deleted': true};
        },
      );
    }
    if (path.length == 7 && path[5] == 'revisions' && request.method == 'GET') {
      await store.requireAccess(actor, workspaceId, Capability.jobsRead);
      final revision = int.tryParse(path[6]);
      if (revision == null || revision < 0) {
        throw const ApiError(
          400,
          'invalid_video_project_revision',
          'A project version is a whole number.',
        );
      }
      return jsonResponse(200, {
        'revision': await store.getVideoProjectRevision(
          workspaceId: workspaceId,
          projectId: path[4],
          revision: revision,
        ),
      }, requestId: requestId);
    }
    return jsonResponse(404, {
      'error': {'code': 'not_found', 'message': 'Unknown video project route.'},
    }, requestId: requestId);
  }
}
