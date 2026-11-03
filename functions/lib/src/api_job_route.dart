part of 'api.dart';

extension _JobRoute on IiOsApi {
  Future<Response> _jobRoute(
    Request request,
    String requestId,
    AuthenticatedUser actor,
    String workspaceId,
    List<String> path,
  ) async {
    if (path.length == 4 && request.method == 'GET') {
      await store.requireAccess(actor, workspaceId, Capability.jobsRead);
      final workspace = await store.getWorkspace(workspaceId);
      final query = request.url.queryParameters;
      final limit = _jobListLimit(query['limit']);
      final cursor = switch (query['cursor']?.trim()) {
        final value? when value.isNotEmpty => JobListCursor.decode(value),
        _ => null,
      };
      final changesSinceValue = query['changesSince']?.trim();
      if (changesSinceValue != null && changesSinceValue.isNotEmpty) {
        final changesSince = DateTime.tryParse(changesSinceValue)?.toUtc();
        if (changesSince == null) {
          throw const ApiError(
            400,
            'invalid_job_changes_cursor',
            'The job history change cursor is invalid.',
          );
        }
        return jsonResponse(
          200,
          await workflows.listJobChanges(
            workspace,
            changesSince: changesSince,
            limit: limit,
            cursor: cursor,
          ),
          requestId: requestId,
        );
      }
      return jsonResponse(
        200,
        await workflows.listJobs(
          workspace,
          limit: limit,
          cursor: cursor,
          reconcile: query['reconcile'] != 'false',
        ),
        requestId: requestId,
      );
    }
    if (path.length == 4 && request.method == 'POST') {
      await store.requireAccess(actor, workspaceId, Capability.jobsTrigger);
      final body = await readJsonObject(request);
      final workflowKey = requiredString(body, 'workflowKey', maxLength: 400);
      final ghostMode = _jobGhostMode(body['ghostMode']);
      final promptEnhancementBypass = requestedPromptEnhancementBypass(
        body['promptEnhancementBypass'],
      );
      final input = body['input'];
      if (input is! Map<String, Object?>) {
        throw const ApiError(
          400,
          'invalid_job_input',
          'Job input is required.',
        );
      }
      final workspace = await store.getWorkspace(workspaceId);
      final notificationDeepLink = _notificationDeepLink(
        body['notificationDeepLink'],
        workspaceId,
      );
      return _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: ghostMode
            ? 'ghost_generation.dispatch'
            : 'github_workflow.dispatch',
        targetType: ghostMode ? 'ghost_generation' : 'github_workflow_run',
        targetId: requestId,
        metadata: ghostMode ? const {} : {'workflowKey': workflowKey},
        execute: () => workflows.dispatch(
          workspace: workspace,
          actorUid: actor.uid,
          requestId: requestId,
          workflowKeyValue: workflowKey,
          input: input,
          notificationDeepLink: ghostMode ? null : notificationDeepLink,
          ghostMode: ghostMode,
          promptEnhancementBypass: promptEnhancementBypass,
        ),
      );
    }
    if (path.length == 5 && request.method == 'GET') {
      await store.requireAccess(actor, workspaceId, Capability.jobsRead);
      final jobId = Uri.decodeComponent(path[4]);
      final workspace = await store.getWorkspace(workspaceId);
      return jsonResponse(200, {
        'job': await workflows.getJob(workspace, jobId),
      }, requestId: requestId);
    }
    if (path.length == 6 && path[5] == 'cancel' && request.method == 'POST') {
      await store.requireAccess(actor, workspaceId, Capability.jobsTrigger);
      final jobId = Uri.decodeComponent(path[4]);
      final workspace = await store.getWorkspace(workspaceId);
      return _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'github_workflow.cancel',
        targetType: 'github_workflow_run',
        targetId: jobId,
        execute: () => workflows.cancelJob(workspace, jobId),
      );
    }
    if (path.length == 7 &&
        path[5] == 'artifacts' &&
        path[6] == 'consume' &&
        request.method == 'POST') {
      await store.requireAccess(actor, workspaceId, Capability.jobsTrigger);
      final jobId = Uri.decodeComponent(path[4]);
      return _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'ghost_generation.consume',
        targetType: 'ghost_generation',
        targetId: jobId,
        execute: () => connectedDataApi.consumeGhostJob(
          workspaceId: workspaceId,
          jobId: jobId,
        ),
      );
    }
    throw const ApiError(404, 'not_found', 'Job route not found.');
  }
}

bool _jobGhostMode(Object? value) {
  if (value == null) return false;
  if (value is bool) return value;
  throw const ApiError(
    400,
    'invalid_ghost_mode',
    'Ghost mode must be true or false.',
  );
}

String? _notificationDeepLink(Object? value, String workspaceId) {
  if (value == null) return null;
  if (value is! String || value.length > 500) {
    throw const ApiError(
      400,
      'invalid_notification_deep_link',
      'Notification deep link is invalid.',
    );
  }
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.path.startsWith('/workspaces/$workspaceId/')) {
    throw const ApiError(
      400,
      'invalid_notification_deep_link',
      'Notification deep link must target this workspace.',
    );
  }
  return uri.toString();
}

int _jobListLimit(String? value) {
  if (value == null || value.trim().isEmpty) return 50;
  final parsed = int.tryParse(value);
  if (parsed == null || parsed < 1 || parsed > 50) {
    throw const ApiError(
      400,
      'invalid_job_limit',
      'The job history page size must be between 1 and 50.',
    );
  }
  return parsed;
}
