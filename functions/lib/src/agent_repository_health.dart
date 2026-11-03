import 'api_error.dart';
import 'codex_auth_store.dart';
import 'domain.dart';
import 'github_client.dart';
import 'trusted_tag_ruleset_attestation_store.dart';

enum AgentRepositoryHealthStatus {
  healthy('healthy'),
  verificationRequired('verification_required'),
  actionRequired('action_required'),
  unavailable('unavailable');

  const AgentRepositoryHealthStatus(this.value);

  final String value;
}

final class AgentRepositoryHealth {
  const AgentRepositoryHealth({
    required this.repository,
    required this.status,
    required this.checkedAt,
    required this.checks,
    required this.sourceSha,
    required this.sourceRef,
  });

  final String repository;
  final AgentRepositoryHealthStatus status;
  final DateTime checkedAt;
  final List<Map<String, Object?>> checks;
  final String sourceSha;
  final String sourceRef;

  bool get dispatchAllowed => status == AgentRepositoryHealthStatus.healthy;

  List<Map<String, Object?>> get blockers =>
      checks.where((check) => !_readinessSatisfied(check['status'])).toList();
  List<Map<String, Object?>> get advisories =>
      checks.where((check) => check['status'] == 'warning').toList();

  Map<String, Object?> toJson() => {
    'repository': repository,
    'status': status.value,
    'dispatchAllowed': dispatchAllowed,
    'checkedAt': checkedAt.toUtc().toIso8601String(),
    'sourceSha': sourceSha,
    'sourceRef': sourceRef,
    'checks': checks,
    'blockers': blockers,
    'advisories': advisories,
  };
}

AgentRepositoryHealth resolveAgentRepositoryHealth({
  required String repository,
  required List<Map<String, Object?>> checks,
  required DateTime checkedAt,
  String sourceSha = '',
  String sourceRef = '',
}) {
  final statuses = checks.map((check) => check['status']).toSet();
  final immutableSource =
      RegExp(r'^[0-9a-f]{40}$').hasMatch(sourceSha) &&
      sourceRef == 'ii-os-agent-v4-$sourceSha';
  final status =
      checks.isNotEmpty &&
          statuses.every(_readinessSatisfied) &&
          immutableSource
      ? AgentRepositoryHealthStatus.healthy
      : statuses.contains('action_required')
      ? AgentRepositoryHealthStatus.actionRequired
      : statuses.contains('unable_to_verify')
      ? AgentRepositoryHealthStatus.unavailable
      : statuses.contains('securely_stored')
      ? AgentRepositoryHealthStatus.verificationRequired
      : AgentRepositoryHealthStatus.unavailable;
  return AgentRepositoryHealth(
    repository: repository,
    status: status,
    checkedAt: checkedAt,
    checks: checks,
    sourceSha: sourceSha,
    sourceRef: sourceRef,
  );
}

/// Setup health is intentionally narrower than agent execution health.
///
/// GitHub setup proves only that the App key works, the selected repository is
/// reachable, and the required repository permissions are granted. Runtime
/// activation keeps its separate, stricter Fleet and permission-profile gate.
AgentRepositoryHealth resolveGitHubSetupRepositoryHealth({
  required String repository,
  required List<Map<String, Object?>> checks,
  required DateTime checkedAt,
}) {
  final statuses = checks.map((check) => check['status']).toSet();
  final status = checks.isNotEmpty && statuses.every(_readinessSatisfied)
      ? AgentRepositoryHealthStatus.healthy
      : statuses.contains('action_required')
      ? AgentRepositoryHealthStatus.actionRequired
      : AgentRepositoryHealthStatus.unavailable;
  return AgentRepositoryHealth(
    repository: repository,
    status: status,
    checkedAt: checkedAt,
    checks: checks,
    sourceSha: '',
    sourceRef: '',
  );
}

Future<AgentRepositoryHealth> inspectAgentRepositoryHealth({
  required Workspace workspace,
  required String repository,
  required GitHubClient github,
  required CodexAuthStore codexAuth,
  String? permissionProfileId,
  DateTime Function()? clock,
}) async {
  final checkedAt = (clock ?? _utcNow)();
  final checks = <Map<String, Object?>>[
    readinessCheck(
      id: 'github_installation',
      label: 'GitHub App installation connected',
      passed: workspace.githubInstallationId != null,
      repository: repository,
      detail: workspace.githubInstallationId == null
          ? 'No GitHub App installation is connected.'
          : 'Installation ${workspace.githubInstallationId} is connected.',
      guidance:
          'Open workspace access, connect the GitHub App, and validate the installation.',
    ),
    readinessCheck(
      id: 'repository_selected',
      label: 'Repository selected for agent work',
      passed: workspace.repositories.contains(repository),
      repository: repository,
      detail: workspace.repositories.contains(repository)
          ? '$repository is connected to this workspace.'
          : '$repository is not connected to this workspace.',
      guidance:
          'Open workspace access and add this repository before enabling agents.',
    ),
  ];
  if (checks.any((check) => check['status'] != 'passed')) {
    return resolveAgentRepositoryHealth(
      repository: repository,
      checks: checks,
      checkedAt: checkedAt,
    );
  }

  try {
    final state = await codexAuth.repositoryState(workspace.id, repository);
    final tagRulesetAttestation = await TrustedTagRulesetAttestationStore(
      codexAuth.store,
    ).read(workspaceId: workspace.id, repository: repository);
    final inspection = await github.inspectAgentRepositoryReadiness(
      workspace,
      repository: repository,
      codexAuthState: state,
      tagRulesetAttestation: tagRulesetAttestation,
      permissionProfileId: permissionProfileId,
    );
    checks.addAll(inspection.checks);
    return resolveAgentRepositoryHealth(
      repository: repository,
      checks: checks,
      checkedAt: checkedAt,
      sourceSha: inspection.sourceSha,
      sourceRef: inspection.sourceRef,
    );
  } on ApiError catch (error) {
    checks.add(
      readinessUnable(
        id: 'github_remote_checks',
        label: 'Live repository health verified',
        repository: repository,
        error: error,
        guidance:
            'Check the GitHub App installation and GitHub availability, then retry.',
      ),
    );
  } on Object {
    checks.add({
      'id': 'github_remote_checks',
      'label': 'Live repository health verified',
      'status': 'unable_to_verify',
      'detail': 'ii-os could not complete the live repository health check.',
      'guidance':
          'Check the GitHub App installation and GitHub availability, then retry.',
      'repository': repository,
    });
  }
  return resolveAgentRepositoryHealth(
    repository: repository,
    checks: checks,
    checkedAt: checkedAt,
  );
}

void requireHealthyAgentRepository(AgentRepositoryHealth health) {
  if (health.dispatchAllowed) return;
  throw ApiError(
    409,
    'agent_repository_not_healthy',
    'Agent work is blocked until ${health.repository} is live-verified.',
    details: health.toJson(),
  );
}

DateTime _utcNow() => DateTime.now().toUtc();

bool _readinessSatisfied(Object? status) =>
    status == 'passed' || status == 'warning';
