part of 'api.dart';

extension _InteractiveSessionRoutes on IiOsApi {
  Future<Response?> _interactiveSessionRoute(
    Request request,
    String requestId,
    AuthenticatedUser actor,
    String workspaceId,
    List<String> path,
  ) async {
    if (path.length < 4 || path[3] != 'interactive-sessions') return null;
    final coordinator = interactiveSessions;
    if (coordinator == null) {
      throw const ApiError(
        503,
        'interactive_sessions_unavailable',
        'Interactive sessions are not configured in this environment.',
      );
    }

    if (path.length == 4 && request.method == 'GET') {
      final page = await coordinator.listPage(
        actor: actor,
        workspaceId: workspaceId,
      );
      return jsonResponse(200, page, requestId: requestId);
    }

    if (path.length == 4 && request.method == 'POST') {
      final body = await readJsonObject(request);
      final runnerResourceId =
          body['runnerResourceId']?.toString().trim() ?? '';
      return _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'interactive_session.create',
        targetType: 'interactive_session',
        metadata: {
          if (runnerResourceId.isNotEmpty) 'runnerResourceId': runnerResourceId,
        },
        execute: () => coordinator.create(
          actor: actor,
          workspaceId: workspaceId,
          runnerResourceId: runnerResourceId,
        ),
      );
    }

    if (path.length < 5) return null;
    final sessionId = _interactiveIdentity(path[4], 'session');
    if (path.length == 5 && request.method == 'GET') {
      return jsonResponse(200, {
        'session': await coordinator.get(
          actor: actor,
          workspaceId: workspaceId,
          sessionId: sessionId,
        ),
      }, requestId: requestId);
    }

    if (path.length == 6 && path[5] == 'attach' && request.method == 'POST') {
      return jsonResponse(200, {
        'attach': await coordinator.attach(
          actor: actor,
          workspaceId: workspaceId,
          sessionId: sessionId,
        ),
      }, requestId: requestId);
    }

    if (path.length == 6 &&
        path[5] == 'ui-access' &&
        request.method == 'POST') {
      final body = await readJsonObject(request);
      final agentSubject = requiredString(body, 'agentSubject', maxLength: 200);
      return _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'interactive_session.ui_access.issue',
        targetType: 'interactive_session',
        targetId: sessionId,
        metadata: {'allowAct': body['allowAct'] == true},
        execute: () => coordinator.issueUiAccess(
          actor: actor,
          workspaceId: workspaceId,
          sessionId: sessionId,
          agentSubject: agentSubject,
          allowAct: body['allowAct'] == true,
        ),
      );
    }

    if (path.length == 6 && path[5] == 'stop' && request.method == 'POST') {
      return _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'interactive_session.stop',
        targetType: 'interactive_session',
        targetId: sessionId,
        execute: () => coordinator.stop(
          actor: actor,
          workspaceId: workspaceId,
          sessionId: sessionId,
        ),
      );
    }

    if (path.length == 7 &&
        path[5] == 'participants' &&
        const {'PUT', 'DELETE'}.contains(request.method)) {
      final subject = _interactiveIdentity(path[6], 'participant');
      if (request.method == 'DELETE') {
        return _audited(
          requestId: requestId,
          actor: actor,
          workspaceId: workspaceId,
          action: 'interactive_session.participant.revoke',
          targetType: 'interactive_session_participant',
          targetId: subject,
          execute: () => coordinator.revokeParticipant(
            actor: actor,
            workspaceId: workspaceId,
            sessionId: sessionId,
            subject: subject,
          ),
        );
      }
      final body = await readJsonObject(request);
      final roleName = requiredString(body, 'role', maxLength: 24);
      late ParticipantRole role;
      try {
        role = ParticipantRole.values.byName(roleName);
      } on ArgumentError {
        throw const ApiError(
          400,
          'interactive_participant_role_invalid',
          'The interactive session role is invalid.',
        );
      }
      return _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'interactive_session.participant.put',
        targetType: 'interactive_session_participant',
        targetId: subject,
        metadata: {'role': role.name},
        execute: () => coordinator.putParticipant(
          actor: actor,
          workspaceId: workspaceId,
          sessionId: sessionId,
          subject: subject,
          role: role,
        ),
      );
    }
    return null;
  }
}

String _interactiveIdentity(String value, String label) {
  final decoded = Uri.decodeComponent(value).trim();
  if (decoded.isEmpty || decoded.length > 200 || decoded.contains('/')) {
    throw ApiError(
      400,
      'interactive_${label}_invalid',
      'The interactive $label identity is invalid.',
    );
  }
  return decoded;
}
