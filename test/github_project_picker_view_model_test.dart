import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/repositories/github_project_repository.dart';
import 'package:ii_os/view_models/github_project_picker_view_model.dart';

void main() {
  test('available project response parses the exact API envelope', () {
    final projects = parseAvailableGitHubProjects({
      'projects': [
        {
          'id': 'PVT_delivery',
          'number': 7,
          'owner': 'acme',
          'title': 'Delivery',
        },
      ],
    });

    expect(projects.single.id, 'PVT_delivery');
    expect(projects.single.title, 'Delivery');
  });

  test(
    'picker defaults to the first repository and first available project',
    () async {
      final repository = _ProjectsRepository({
        'acme/app': const [
          ProjectConnection(
            id: 'PVT_delivery',
            number: 7,
            owner: 'acme',
            title: 'Delivery',
          ),
        ],
      });
      final model = GitHubProjectPickerViewModel(
        workspaceId: 'workspace-1',
        repositories: const ['acme/app', 'acme/api'],
        connectedProjectIds: const {},
        repository: repository,
      );

      await model.start();

      expect(model.selectedRepository, 'acme/app');
      expect(model.selectedProject?.id, 'PVT_delivery');
      expect(repository.requests, ['acme/app']);
    },
  );

  test('picker excludes projects already connected to the workspace', () async {
    final repository = _ProjectsRepository({
      'acme/app': const [
        ProjectConnection(
          id: 'PVT_connected',
          number: 1,
          owner: 'acme',
          title: 'Connected',
        ),
        ProjectConnection(
          id: 'PVT_new',
          number: 2,
          owner: 'acme',
          title: 'New',
        ),
      ],
    });
    final model = GitHubProjectPickerViewModel(
      workspaceId: 'workspace-1',
      repositories: const ['acme/app'],
      connectedProjectIds: const {'PVT_connected'},
      repository: repository,
    );

    await model.start();

    expect(model.projects.map((project) => project.id), ['PVT_new']);
    expect(model.selectedProject?.id, 'PVT_new');
  });
}

final class _ProjectsRepository implements GitHubProjectRepository {
  _ProjectsRepository(this.results);

  final Map<String, List<ProjectConnection>> results;
  final List<String> requests = [];

  @override
  Future<List<ProjectConnection>> listAvailable({
    required String workspaceId,
    required String repository,
  }) async {
    requests.add(repository);
    return results[repository] ?? const [];
  }
}
