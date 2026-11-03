part of 'api.dart';

extension _AgentUsageKeyRoutes on IiOsApi {
  Future<Response?> _agentUsageKeyRoute(
    Request request,
    String requestId,
    AuthenticatedUser actor,
    String workspaceId,
    List<String> path,
  ) async {
    if (path.length < 4 || path[3] != 'agent-usage-keys') return null;
    await store.requireAccess(actor, workspaceId, Capability.membersManage);
    if (path.length == 4 && request.method == 'GET') {
      return jsonResponse(200, {
        'credentials': await agentUsageKeys.list(workspaceId),
      }, requestId: requestId);
    }
    if (path.length == 4 && request.method == 'POST') {
      final body = await readJsonObject(request);
      final label = requiredString(body, 'label', maxLength: 100);
      final expiresInDays = (body['expiresInDays'] as num?)?.toInt() ?? 90;
      return _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'agent_usage_key.issue',
        targetType: 'agent_usage_key',
        metadata: {'label': label, 'expiresInDays': expiresInDays},
        execute: () => agentUsageKeys.issue(
          workspaceId: workspaceId,
          label: label,
          expiresInDays: expiresInDays,
          createdBy: actor.uid,
        ),
      );
    }
    if (path.length == 5 && request.method == 'DELETE') {
      final keyId = path[4];
      if (!RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      ).hasMatch(keyId)) {
        throw const ApiError(
          400,
          'invalid_agent_usage_key_id',
          'Agent usage reporting key ID is invalid.',
        );
      }
      return _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'agent_usage_key.revoke',
        targetType: 'agent_usage_key',
        targetId: keyId,
        execute: () => agentUsageKeys.revoke(
          workspaceId: workspaceId,
          keyId: keyId,
          revokedBy: actor.uid,
        ),
      );
    }
    throw const ApiError(
      405,
      'method_not_allowed',
      'Agent usage reporting key route does not support this method.',
    );
  }
}
