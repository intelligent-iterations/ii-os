import '../models/agent_permission.dart';
import '../models/codex_auth_session.dart';
import '../models/models.dart';
import '../services/api_client.dart';

final class AgentPermissionsRepository {
  const AgentPermissionsRepository(this.api);

  final ApiClient api;

  Future<List<AgentPermissionModel>> listProfiles({
    required String workspaceId,
    required String repository,
  }) async {
    final response = await api.get(
      'v1/workspaces/$workspaceId/agent-permissions',
      query: {'repository': repository, 'ref': 'dev'},
    );
    return (response['profiles'] as List<Object?>? ?? const [])
        .map(asJsonMap)
        .map(AgentPermissionModel.fromJson)
        .toList();
  }

  Future<void> install({
    required String workspaceId,
    required String repository,
    required JsonMap profile,
  }) async {
    await api.post(
      'v1/workspaces/$workspaceId/agent-permissions/install',
      body: {'repository': repository, 'ref': 'dev', 'profile': profile},
    );
  }

  Future<CodexAuthSessionModel> startCodex({
    required String workspaceId,
    required String repository,
    bool reauthenticate = false,
  }) async {
    final response = await api.post(
      'v1/workspaces/$workspaceId/codex-auth-sessions',
      body: {'repository': repository, 'reauthenticate': reauthenticate},
    );
    return parseStartedCodexSession(response);
  }

  Future<CodexAuthSessionModel> readCodex({
    required String workspaceId,
    required String sessionId,
  }) async {
    final response = await api.get(
      'v1/workspaces/$workspaceId/codex-auth-sessions/$sessionId',
    );
    return CodexAuthSessionModel.fromJson(asJsonMap(response['session']));
  }
}

CodexAuthSessionModel parseStartedCodexSession(JsonMap response) {
  final data = asJsonMap(response['data']);
  return CodexAuthSessionModel.fromJson(asJsonMap(data['session']));
}
