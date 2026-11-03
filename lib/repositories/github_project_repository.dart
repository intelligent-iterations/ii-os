import '../models/models.dart';
import '../services/api_client.dart';

abstract interface class GitHubProjectRepository {
  Future<List<ProjectConnection>> listAvailable({
    required String workspaceId,
    required String repository,
  });
}

final class GitHubProjectApiRepository implements GitHubProjectRepository {
  const GitHubProjectApiRepository(this.api);

  final ApiClient api;

  @override
  Future<List<ProjectConnection>> listAvailable({
    required String workspaceId,
    required String repository,
  }) async {
    final response = await api.get(
      'v1/workspaces/$workspaceId/github-projects',
      query: {'repository': repository},
    );
    return parseAvailableGitHubProjects(response);
  }
}

List<ProjectConnection> parseAvailableGitHubProjects(JsonMap response) {
  final projects = response['projects'];
  if (projects is! List<Object?>) return const [];
  return projects
      .whereType<Map<String, Object?>>()
      .map(ProjectConnection.fromJson)
      .where(
        (project) =>
            project.id.isNotEmpty &&
            project.number > 0 &&
            project.owner.isNotEmpty &&
            project.title.isNotEmpty,
      )
      .toList(growable: false);
}
