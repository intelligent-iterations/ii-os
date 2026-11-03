part of 'api.dart';

extension _AgentUsageRoute on IiOsApi {
  bool _isAgentUsageIngestRoute(List<String> path) =>
      path.length == 5 &&
      path[0] == 'v1' &&
      path[1] == 'workspaces' &&
      path[3] == 'agent-usage' &&
      path[4] == 'events';

  Future<Response> _agentUsageKeyIngestRoute(
    Request request,
    String requestId,
    List<String> path,
  ) async {
    if (request.method != 'POST') {
      throw const ApiError(
        405,
        'method_not_allowed',
        'Use POST to report agent usage.',
      );
    }
    final principal = await agentUsageKeys.authenticate(request);
    final workspaceId = path[2];
    if (principal.workspaceId != workspaceId) {
      throw const ApiError(
        403,
        'agent_usage_key_workspace_mismatch',
        'The reporting key is not authorized for this workspace.',
      );
    }
    final events = await _readAgentUsageEvents(request);
    return _audited(
      requestId: requestId,
      actor: principal.auditActor,
      workspaceId: workspaceId,
      action: 'agent_usage.ingest',
      targetType: 'agent_usage_batch',
      metadata: {'eventCount': events.length, 'auth': 'reporting_key'},
      execute: () => agentUsage.ingest(
        workspaceId: workspaceId,
        reporterId: 'key:${principal.keyId}',
        events: events,
      ),
    );
  }

  Future<Response?> _agentUsageRoute(
    Request request,
    String requestId,
    AuthenticatedUser actor,
    String workspaceId,
    List<String> path,
  ) async {
    if (path.length < 4 || path[3] != 'agent-usage') return null;
    if (path.length == 5 && path[4] == 'events') {
      if (request.method != 'POST') {
        throw const ApiError(
          405,
          'method_not_allowed',
          'Use POST to report agent usage.',
        );
      }
      await store.requireAccess(actor, workspaceId, Capability.agentUsageWrite);
      final events = await _readAgentUsageEvents(request);
      return _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'agent_usage.ingest',
        targetType: 'agent_usage_batch',
        metadata: {'eventCount': events.length, 'auth': 'workspace_member'},
        execute: () => agentUsage.ingest(
          workspaceId: workspaceId,
          reporterId: 'member:${actor.uid}',
          events: events,
        ),
      );
    }
    if (path.length == 4 && request.method == 'GET') {
      await store.requireAccess(actor, workspaceId, Capability.auditRead);
      final days =
          int.tryParse(request.url.queryParameters['days'] ?? '') ?? 30;
      final origin = request.url.queryParameters['origin'] ?? 'all';
      return jsonResponse(
        200,
        await agentUsage.read(
          workspaceId: workspaceId,
          days: days,
          origin: origin,
        ),
        requestId: requestId,
      );
    }
    if (path.length == 4) {
      throw const ApiError(
        405,
        'method_not_allowed',
        'Agent usage route does not support this method.',
      );
    }
    return null;
  }

  Future<List<Map<String, Object?>>> _readAgentUsageEvents(
    Request request,
  ) async {
    final body = await readJsonObject(request);
    if (body.keys.any((key) => key != 'events')) {
      throw const ApiError(
        400,
        'invalid_agent_usage_event_batch',
        'The request may contain only an events array.',
      );
    }
    final raw = body['events'];
    if (raw is! List<Object?>) {
      throw const ApiError(
        400,
        'invalid_agent_usage_event_batch',
        'Agent usage events must be an array.',
      );
    }
    return raw.map((value) {
      if (value is Map<String, Object?>) return value;
      if (value is Map) return value.cast<String, Object?>();
      throw const ApiError(
        400,
        'invalid_agent_usage_event_batch',
        'Each agent usage event must be an object.',
      );
    }).toList();
  }
}
