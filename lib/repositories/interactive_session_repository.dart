import 'package:ii_interactive_sessions/ii_interactive_sessions.dart';

import '../models/models.dart';
import '../services/api_client.dart';

final class InteractiveSessionPage {
  const InteractiveSessionPage({
    required this.sessions,
    required this.runnerPools,
  });

  final List<InteractiveSessionModel> sessions;
  final List<InteractiveRunnerPoolOption> runnerPools;
}

abstract interface class InteractiveSessionRepository {
  Future<InteractiveSessionPage> list(String workspaceId);

  Future<InteractiveSessionModel> get(String workspaceId, String sessionId);

  Future<
    ({InteractiveSessionModel session, InteractiveSessionAttachment attach})
  >
  create(String workspaceId, {String runnerResourceId = ''});

  Future<InteractiveSessionAttachment> attach(
    String workspaceId,
    String sessionId,
  );

  Future<InteractiveSessionModel> putParticipant(
    String workspaceId,
    String sessionId,
    String subject,
    ParticipantRole role,
  );

  Future<InteractiveSessionModel> revokeParticipant(
    String workspaceId,
    String sessionId,
    String subject,
  );

  Future<InteractiveUiAccessGrant> issueUiAccess(
    String workspaceId,
    String sessionId, {
    required String agentSubject,
    required bool allowAct,
  });

  Future<void> stop(String workspaceId, String sessionId);
}

final class InteractiveSessionFailure implements Exception {
  const InteractiveSessionFailure(this.message);

  final String message;
}

final class InteractiveSessionApiRepository
    implements InteractiveSessionRepository {
  const InteractiveSessionApiRepository(this.api);

  final ApiClient api;

  String _base(String workspaceId) =>
      'v1/workspaces/$workspaceId/interactive-sessions';

  @override
  Future<InteractiveSessionPage> list(String workspaceId) =>
      _mapped('Terminal sessions could not be loaded. Try again.', () async {
        final response = await api.get(_base(workspaceId));
        return InteractiveSessionPage(
          sessions: _items(
            response['sessions'],
          ).map(InteractiveSessionModel.fromJson).toList(),
          runnerPools: _items(
            response['runnerPools'],
          ).map(InteractiveRunnerPoolOption.fromJson).toList(),
        );
      });

  @override
  Future<InteractiveSessionModel> get(String workspaceId, String sessionId) =>
      _mapped('This terminal session could not be loaded.', () async {
        final response = await api.get(
          '${_base(workspaceId)}/${Uri.encodeComponent(sessionId)}',
        );
        return InteractiveSessionModel.fromJson(asJsonMap(response['session']));
      });

  @override
  Future<
    ({InteractiveSessionModel session, InteractiveSessionAttachment attach})
  >
  create(String workspaceId, {String runnerResourceId = ''}) => _mapped(
    'The terminal session could not be created. Try again.',
    () async {
      final response = await api.post(
        _base(workspaceId),
        body: {
          if (runnerResourceId.isNotEmpty) 'runnerResourceId': runnerResourceId,
        },
      );
      final data = asJsonMap(response['data']);
      return (
        session: InteractiveSessionModel.fromJson(asJsonMap(data['session'])),
        attach: InteractiveSessionAttachment.fromJson(
          asJsonMap(data['attach']),
        ),
      );
    },
  );

  @override
  Future<InteractiveSessionAttachment> attach(
    String workspaceId,
    String sessionId,
  ) => _mapped('This terminal session could not be joined.', () async {
    final response = await api.post(
      '${_base(workspaceId)}/${Uri.encodeComponent(sessionId)}/attach',
    );
    return InteractiveSessionAttachment.fromJson(asJsonMap(response['attach']));
  });

  @override
  Future<InteractiveSessionModel> putParticipant(
    String workspaceId,
    String sessionId,
    String subject,
    ParticipantRole role,
  ) => _mapped('That person could not be invited to this session.', () async {
    final response = await api.put(
      '${_base(workspaceId)}/${Uri.encodeComponent(sessionId)}/participants/${Uri.encodeComponent(subject)}',
      body: {'role': role.name},
    );
    return InteractiveSessionModel.fromJson(asJsonMap(response['data']));
  });

  @override
  Future<InteractiveSessionModel> revokeParticipant(
    String workspaceId,
    String sessionId,
    String subject,
  ) => _mapped('That participant could not be removed.', () async {
    final response = await api.delete(
      '${_base(workspaceId)}/${Uri.encodeComponent(sessionId)}/participants/${Uri.encodeComponent(subject)}',
    );
    return InteractiveSessionModel.fromJson(asJsonMap(response['data']));
  });

  @override
  Future<InteractiveUiAccessGrant> issueUiAccess(
    String workspaceId,
    String sessionId, {
    required String agentSubject,
    required bool allowAct,
  }) => _mapped('Codex UI access could not be granted.', () async {
    final response = await api.post(
      '${_base(workspaceId)}/${Uri.encodeComponent(sessionId)}/ui-access',
      body: {'agentSubject': agentSubject, 'allowAct': allowAct},
    );
    return InteractiveUiAccessGrant.fromJson(asJsonMap(response['data']));
  });

  @override
  Future<void> stop(String workspaceId, String sessionId) =>
      _mapped('The terminal session could not be stopped.', () async {
        await api.post(
          '${_base(workspaceId)}/${Uri.encodeComponent(sessionId)}/stop',
        );
      });
}

Future<T> _mapped<T>(String fallback, Future<T> Function() action) async {
  try {
    return await action();
  } on ApiFailure catch (error) {
    throw InteractiveSessionFailure(switch (error.code) {
      'interactive_sessions_unavailable' =>
        'Terminal sessions are not configured in this environment.',
      'interactive_runner_grant_required' ||
      'interactive_runner_grant_stale' ||
      'interactive_runner_pool_unavailable' =>
        'Grant this workspace an available Fleet terminal pool first.',
      'interactive_session_concurrency_reached' =>
        'That Fleet pool has no free terminal session slots.',
      'interactive_session_invite_required' =>
        'The session owner has not invited you to this terminal.',
      'interactive_participant_not_member' =>
        'Invite an active member of this workspace.',
      'interactive_session_not_joinable' || 'interactive_session_terminal' =>
        'This terminal session has already ended.',
      'interactive_relay_unavailable' || 'interactive_relay_rejected' =>
        'The terminal relay is temporarily unavailable. Try again.',
      _ => fallback,
    });
  } on FormatException {
    throw const InteractiveSessionFailure(
      'The terminal service returned an invalid response.',
    );
  } on Object {
    throw InteractiveSessionFailure(fallback);
  }
}

List<JsonMap> _items(Object? value) => value is List<Object?>
    ? value.map(asJsonMap).where((item) => item.isNotEmpty).toList()
    : const [];
