import 'package:ii_interactive_sessions/ii_interactive_sessions.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/repositories/interactive_session_repository.dart';

const InteractiveSessionRepository emptyInteractiveSessionRepository =
    _EmptyInteractiveSessionRepository();

final class _EmptyInteractiveSessionRepository
    implements InteractiveSessionRepository {
  const _EmptyInteractiveSessionRepository();

  @override
  Future<InteractiveSessionPage> list(String workspaceId) async =>
      const InteractiveSessionPage(sessions: [], runnerPools: []);

  @override
  Future<InteractiveSessionModel> get(String workspaceId, String sessionId) =>
      throw UnsupportedError('The page golden never opens a session.');

  @override
  Future<
    ({InteractiveSessionModel session, InteractiveSessionAttachment attach})
  >
  create(String workspaceId, {String runnerResourceId = ''}) =>
      throw UnsupportedError('The page golden never creates a session.');

  @override
  Future<InteractiveSessionAttachment> attach(
    String workspaceId,
    String sessionId,
  ) => throw UnsupportedError('The page golden never attaches.');

  @override
  Future<InteractiveSessionModel> putParticipant(
    String workspaceId,
    String sessionId,
    String subject,
    ParticipantRole role,
  ) => throw UnsupportedError('The page golden never invites a participant.');

  @override
  Future<InteractiveSessionModel> revokeParticipant(
    String workspaceId,
    String sessionId,
    String subject,
  ) => throw UnsupportedError('The page golden never removes a participant.');

  @override
  Future<InteractiveUiAccessGrant> issueUiAccess(
    String workspaceId,
    String sessionId, {
    required String agentSubject,
    required bool allowAct,
  }) => throw UnsupportedError('The page golden never grants UI access.');

  @override
  Future<void> stop(String workspaceId, String sessionId) =>
      throw UnsupportedError('The page golden never stops a session.');
}
