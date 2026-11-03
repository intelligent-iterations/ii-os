import 'models.dart';

export 'codex_auth_session.dart';

final class GitHubSetupReadinessModel {
  const GitHubSetupReadinessModel({
    required this.status,
    required this.checkedAt,
    required this.githubAppSettingsUrl,
    required this.checks,
    required this.workspace,
    required this.repositories,
  });

  factory GitHubSetupReadinessModel.fromJson(JsonMap json) {
    final checks = (json['checks'] as List<Object?>? ?? const [])
        .map(asJsonMap)
        .map(GitHubSetupCheckModel.fromJson)
        .toList();
    final workspaceJson = asJsonMap(json['workspace']);
    final repositoryJson = (json['repositories'] as List<Object?>? ?? const [])
        .map(asJsonMap)
        .toList();
    return GitHubSetupReadinessModel(
      status: json['status'] as String? ?? 'action_required',
      checkedAt: DateTime.tryParse(json['checkedAt'] as String? ?? ''),
      githubAppSettingsUrl: json['githubAppSettingsUrl'] as String? ?? '',
      checks: checks,
      workspace: workspaceJson.isNotEmpty
          ? GitHubWorkspaceAutomationModel.fromJson(workspaceJson)
          : GitHubWorkspaceAutomationModel(
              status: 'ready',
              dispatchAllowed: true,
              checkedAt: DateTime.tryParse(json['checkedAt'] as String? ?? ''),
              checks: const [],
            ),
      repositories: repositoryJson
          .map(GitHubRepositoryHealthModel.fromJson)
          .toList(),
    );
  }

  final String status;
  final DateTime? checkedAt;
  final String githubAppSettingsUrl;
  final List<GitHubSetupCheckModel> checks;
  final GitHubWorkspaceAutomationModel workspace;
  final List<GitHubRepositoryHealthModel> repositories;

  bool get ready =>
      workspace.ready &&
      repositories.isNotEmpty &&
      repositories.every((repository) => repository.ready);

  GitHubRepositoryHealthModel? healthFor(String repository) =>
      repositories.where((item) => item.repository == repository).firstOrNull;

  bool readyFor(String repository) {
    final health = healthFor(repository);
    return workspace.ready && health?.ready == true;
  }

  List<GitHubSetupCheckModel> checksFor(String repository) {
    final health = healthFor(repository);
    if (health != null) return health.checks;
    return checks
        .where(
          (check) => check.repository.isEmpty || check.repository == repository,
        )
        .toList();
  }

  List<GitHubSetupStageModel> stagesFor(String repository) {
    final selected = checksFor(repository);
    List<GitHubSetupCheckModel> matching(Set<String> ids) =>
        selected.where((check) => ids.contains(check.id)).toList();
    return [
      GitHubSetupStageModel(
        id: 'repository',
        title: 'Connect GitHub App',
        description:
            'Use the workspace key to verify the installation and selected repository.',
        checks: matching(repositoryConnectionCheckIds),
      ),
      GitHubSetupStageModel(
        id: 'permissions',
        title: 'Repository permissions',
        description:
            'Grant the required write access and review the recommended deployment verification access.',
        checks: matching(permissionSetupCheckIds),
      ),
    ];
  }
}

const repositoryConnectionCheckIds = {
  'github_installation',
  'repository_selected',
  'github_repository_access',
};

const permissionSetupCheckIds = {
  'github_app_actions',
  'github_app_contents',
  'github_app_deployments',
  'github_app_pull_requests',
  'permission_bootstrap_tag',
};

final class GitHubWorkspaceAutomationModel {
  const GitHubWorkspaceAutomationModel({
    required this.status,
    required this.dispatchAllowed,
    required this.checkedAt,
    required this.checks,
  });

  factory GitHubWorkspaceAutomationModel.fromJson(JsonMap json) =>
      GitHubWorkspaceAutomationModel(
        status: json['status'] as String? ?? 'action_required',
        dispatchAllowed: json['dispatchAllowed'] == true,
        checkedAt: DateTime.tryParse(json['checkedAt'] as String? ?? ''),
        checks: (json['checks'] as List<Object?>? ?? const [])
            .map(asJsonMap)
            .map(GitHubSetupCheckModel.fromJson)
            .toList(),
      );

  final String status;
  final bool dispatchAllowed;
  final DateTime? checkedAt;
  final List<GitHubSetupCheckModel> checks;

  bool get ready =>
      dispatchAllowed &&
      (checks.isEmpty || checks.every((check) => check.dispatchable));
  GitHubSetupCheckModel? get blocker =>
      checks.where((check) => !check.dispatchable).firstOrNull;
}

final class GitHubRepositoryHealthModel {
  const GitHubRepositoryHealthModel({
    required this.repository,
    required this.status,
    required this.dispatchAllowed,
    required this.checkedAt,
    required this.checks,
  });

  factory GitHubRepositoryHealthModel.fromJson(JsonMap json) =>
      GitHubRepositoryHealthModel(
        repository: json['repository'] as String? ?? '',
        status: json['status'] as String? ?? 'unavailable',
        dispatchAllowed: json['dispatchAllowed'] == true,
        checkedAt: DateTime.tryParse(json['checkedAt'] as String? ?? ''),
        checks: (json['checks'] as List<Object?>? ?? const [])
            .map(asJsonMap)
            .map(GitHubSetupCheckModel.fromJson)
            .toList(),
      );

  final String repository;
  final String status;
  final bool dispatchAllowed;
  final DateTime? checkedAt;
  final List<GitHubSetupCheckModel> checks;

  bool get ready =>
      status == 'healthy' &&
      dispatchAllowed &&
      checks.isNotEmpty &&
      checks.every((check) => check.dispatchable);
  bool get verificationRequired => status == 'verification_required';
  bool get unavailable => status == 'unavailable';
  List<GitHubSetupCheckModel> get blockers =>
      checks.where((check) => !check.dispatchable).toList();
  List<GitHubSetupCheckModel> get recommendations =>
      checks.where((check) => check.warning).toList();

  String get label => switch (status) {
    'healthy' => 'Live verified',
    'verification_required' => 'Verification required',
    'unavailable' => 'Check unavailable',
    _ => 'Action required',
  };
}

final class GitHubSetupStageModel {
  const GitHubSetupStageModel({
    required this.id,
    required this.title,
    required this.description,
    required this.checks,
  });

  final String id;
  final String title;
  final String description;
  final List<GitHubSetupCheckModel> checks;

  bool get ready =>
      checks.isNotEmpty && checks.every((check) => check.dispatchable);
  int get remaining => checks.where((check) => !check.dispatchable).length;
  bool get needsEnvironment => checks.any(
    (check) =>
        const {
          'agent_environment',
          'agent_bootstrap_environment',
        }.contains(check.id) &&
        !check.passed,
  );

  GitHubSetupCheckModel? get nextTask =>
      checks.where((check) => !check.dispatchable).firstOrNull;
  List<GitHubSetupCheckModel> get outstanding =>
      checks.where((check) => !check.dispatchable).toList();
  List<GitHubSetupCheckModel> get recommendations =>
      checks.where((check) => check.warning).toList();
}

enum GitHubSetupAction { configureRepository, configureGitHubApp, refresh }

final class GitHubSetupCheckModel {
  const GitHubSetupCheckModel({
    required this.id,
    required this.label,
    required this.status,
    required this.detail,
    required this.guidance,
    required this.repository,
    required this.action,
    required this.currentValue,
    required this.requiredValue,
    this.command = '',
    this.runStatus = '',
    this.runUrl = '',
    this.runSourceSha = '',
    this.requiresNoBypassAttestation = false,
    this.rulesetId = 0,
    this.rulesetUpdatedAt = '',
  });

  factory GitHubSetupCheckModel.fromJson(JsonMap json) => GitHubSetupCheckModel(
    id: json['id'] as String? ?? '',
    label: json['label'] as String? ?? '',
    status: json['status'] as String? ?? 'unable_to_verify',
    detail: json['detail'] as String? ?? '',
    guidance: json['guidance'] as String? ?? '',
    repository: json['repository'] as String? ?? '',
    action: json['action'] as String? ?? '',
    currentValue: json['currentValue'] as String? ?? '',
    requiredValue: json['requiredValue'] as String? ?? '',
    command: json['command'] as String? ?? '',
    runStatus: json['runStatus'] as String? ?? '',
    runUrl: json['runUrl'] as String? ?? '',
    runSourceSha: json['runSourceSha'] as String? ?? '',
    requiresNoBypassAttestation: json['requiresNoBypassAttestation'] == true,
    rulesetId: (json['rulesetId'] as num?)?.toInt() ?? 0,
    rulesetUpdatedAt: json['rulesetUpdatedAt'] as String? ?? '',
  );

  final String id;
  final String label;
  final String status;
  final String detail;
  final String guidance;
  final String repository;
  final String action;
  final String currentValue;
  final String requiredValue;

  /// Exact shell command that clears a check ii-os is not allowed to clear.
  final String command;
  final String runStatus;
  final String runUrl;
  final String runSourceSha;
  final bool requiresNoBypassAttestation;
  final int rulesetId;
  final String rulesetUpdatedAt;

  bool get passed => status == 'passed';
  bool get warning => status == 'warning';
  bool get securelyStored => status == 'securely_stored';
  bool get dispatchable => passed || warning;
  bool get unableToVerify => status == 'unable_to_verify';
  bool get runInProgress => runStatus == 'running';
  bool get runFailed => runStatus == 'failed';
  bool get runVerificationFailed => runStatus == 'verification_failed';
  bool get runFinishedWithoutInstall => runFailed || runVerificationFailed;

  GitHubSetupAction get suggestedAction => switch (id) {
    'github_installation' ||
    'repository_selected' => GitHubSetupAction.configureRepository,
    'github_app_actions' ||
    'github_app_contents' ||
    'github_app_deployments' ||
    'github_app_pull_requests' => GitHubSetupAction.configureGitHubApp,
    _ => GitHubSetupAction.refresh,
  };
}
