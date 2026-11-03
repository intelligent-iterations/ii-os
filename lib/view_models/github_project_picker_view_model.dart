import 'package:stacked/stacked.dart';

import '../models/models.dart';
import '../repositories/github_project_repository.dart';

final class GitHubProjectPickerViewModel extends BaseViewModel {
  GitHubProjectPickerViewModel({
    required this.workspaceId,
    required List<String> repositories,
    required this.connectedProjectIds,
    required this.repository,
  }) : repositories = List.unmodifiable(repositories),
       selectedRepository = repositories.firstOrNull;

  final String workspaceId;
  final List<String> repositories;
  final Set<String> connectedProjectIds;
  final GitHubProjectRepository repository;

  String? selectedRepository;
  List<ProjectConnection> projects = const [];
  ProjectConnection? selectedProject;
  String? errorMessage;
  bool loaded = false;

  Future<void> start() => _load();

  Future<void> selectRepository(String? value) async {
    if (value == null || value == selectedRepository) return;
    selectedRepository = value;
    await _load();
  }

  void selectProject(ProjectConnection? value) {
    selectedProject = value;
    notifyListeners();
  }

  Future<void> retry() => _load();

  Future<void> _load() async {
    final selectedRepositoryName = selectedRepository;
    projects = const [];
    selectedProject = null;
    errorMessage = null;
    loaded = false;
    if (selectedRepositoryName == null) {
      loaded = true;
      notifyListeners();
      return;
    }
    setBusy(true);
    try {
      final available = await repository.listAvailable(
        workspaceId: workspaceId,
        repository: selectedRepositoryName,
      );
      projects = available
          .where((project) => !connectedProjectIds.contains(project.id))
          .toList(growable: false);
      selectedProject = projects.firstOrNull;
      loaded = true;
    } on Object {
      errorMessage =
          'GitHub Projects could not be loaded. Check the GitHub App Projects permission, then retry.';
      loaded = true;
    } finally {
      setBusy(false);
    }
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
