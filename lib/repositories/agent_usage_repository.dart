import '../models/agent_usage.dart';
import '../models/models.dart';
import '../services/api_client.dart';

typedef AgentUsageLoader =
    Future<AgentUsageReport> Function({
      required String workspaceId,
      required int days,
      required AgentExecutionOrigin origin,
    });

final class AgentUsageRepository {
  const AgentUsageRepository(this.api);

  final ApiClient api;

  Future<AgentUsageReport> read({
    required String workspaceId,
    required int days,
    required AgentExecutionOrigin origin,
  }) async {
    final response = await api.get(
      'v1/workspaces/$workspaceId/agent-usage',
      query: {'days': '$days', 'origin': origin.value},
    );
    return AgentUsageReport.fromJson(asJsonMap(response));
  }
}
