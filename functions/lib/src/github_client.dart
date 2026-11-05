import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:yaml/yaml.dart';

import 'agent_permission_profile.dart';
import 'agent_trusted_source_manifest.dart';
import 'api_error.dart';
import 'domain.dart';
import 'github_app_transport.dart';
import 'github_qa_deployment_cache.dart';
import 'organization_resources.dart';
import 'ticket_content.dart';
import 'ticket_deletion_target.dart';
import 'trusted_tag_ruleset_attestation_store.dart';

part 'github_agent_permissions.dart';
part 'github_agent_finalization.dart';
part 'github_agent_queue.dart';
part 'github_agent_readiness.dart';
part 'github_agent_readiness_checks.dart';
part 'github_agent_readiness_helpers.dart';
part 'github_agent_readiness_policy.dart';
part 'github_runtime_workflow_policy.dart';
part 'github_codex_auth.dart';
part 'github_pull_requests.dart';
part 'github_qa_deployments.dart';
part 'github_projects.dart';
part 'github_ticket_content.dart';
part 'github_ticket_deletion.dart';
part 'github_trusted_tag_ruleset.dart';

typedef GitHubClientProvider =
    Future<GitHubClient> Function(Workspace workspace);

final class GitHubClient {
  GitHubClient({
    required String appId,
    required String privateKey,
    http.Client? httpClient,
    GitHubQaDeploymentCache? qaDeploymentCache,
    this.agentTrustedSourceManifest =
        const AgentTrustedSourceManifest.disabled(),
    this.agentEngines = AgentEngineCatalog.codexOnly,
  }) : _transport = GitHubAppTransport(
         appId: appId,
         privateKey: privateKey,
         httpClient: httpClient,
       ),
       _qaDeploymentCache = qaDeploymentCache ?? GitHubQaDeploymentCache();

  final GitHubAppTransport _transport;
  final GitHubQaDeploymentCache _qaDeploymentCache;
  final AgentTrustedSourceManifest agentTrustedSourceManifest;
  final AgentEngineCatalog agentEngines;

  Future<Set<String>> grantedInstallationPermissionEnvelope(
    Workspace workspace,
  ) async => githubPermissionEnvelope(
    await _transport.grantedInstallationPermissions(workspace),
  );

  Future<({Set<String> repositories, Set<String> permissions})>
  grantedInstallationResources(Workspace workspace) async {
    final discovered = await _transport.discoverInstallation(
      workspace.githubInstallationId ?? 0,
    );
    return (
      repositories: discovered.repositories,
      permissions: githubPermissionEnvelope(discovered.permissions),
    );
  }

  Future<String> appPermissionSettingsUrl() async =>
      (await _transport.appIdentity()).permissionSettingsUrl;

  /// Where the owner should go to clear the outstanding permission gap.
  ///
  /// Widening the App's own permissions and accepting the resulting
  /// installation request are two different pages, and only one of them is
  /// useful at a time. Sending an owner who already edited the App back to the
  /// App settings page is the loop this resolves.
  Future<String> permissionActionUrl(Workspace workspace) async {
    final installationPermissions = await _transport.installationPermissions(
      workspace,
      refresh: true,
    );
    final requiresWorkshop = workspace.projects.isNotEmpty;
    if (missingGitHubAppPermissions(
      installationPermissions,
      requiresWorkshop: requiresWorkshop,
    ).isEmpty) {
      return (await _transport.appIdentity()).permissionSettingsUrl;
    }
    final appPermissions = await _transport.appPermissions();
    if (githubAppPermissionEditPending(
      appPermissions: appPermissions,
      installationPermissions: installationPermissions,
      requiresWorkshop: requiresWorkshop,
    )) {
      return (await _transport.appIdentity()).permissionSettingsUrl;
    }
    return (await _transport.installationIdentity(
      workspace,
    )).permissionUpdateUrl;
  }

  /// Verifies setup directly with GitHub from the Firebase control function.
  ///
  /// Minting the installation token proves the workspace's customer-owned
  /// Secret Manager key is usable. Reading the exact repository proves that
  /// the installation includes it. No workflow or runner is started.
  Future<List<Map<String, Object?>>> inspectGitHubSetupRepository(
    Workspace workspace, {
    required String repository,
  }) async {
    _requireRepository(workspace, repository);
    final permissions = await _transport.installationPermissions(
      workspace,
      refresh: true,
      repository: repository,
    );
    final repositoryData = _asMap(
      await _rest(workspace, 'GET', '/repos/$repository'),
    );
    if (repositoryData['full_name'] != repository ||
        repositoryData['id'] is! num) {
      throw const ApiError(
        502,
        'github_response_invalid',
        'GitHub returned an unexpected repository.',
      );
    }
    return [
      readinessCheck(
        id: 'github_repository_access',
        label: 'Selected repository is available to the GitHub App',
        passed: true,
        repository: repository,
        detail: '$repository is included in this GitHub App installation.',
        guidance:
            'Open the GitHub App installation and grant access to this repository.',
      ),
      for (final check in githubAppPermissionChecks(
        permissions,
        requiresWorkshop: workspace.projects.isNotEmpty,
      ))
        {...check, 'repository': repository},
    ];
  }

  Future<List<Map<String, Object?>>> listIssues(
    Workspace workspace,
    String repository,
  ) async {
    _requireRepository(workspace, repository);
    _requireGitHubIssuePermission(workspace, level: 'read');
    final response = await _rest(
      workspace,
      'GET',
      '/repos/$repository/issues?state=all&per_page=50',
    );
    if (response is! List<Object?>) {
      throw const ApiError(
        502,
        'github_response_invalid',
        'GitHub returned invalid issue data.',
      );
    }
    return response
        .whereType<Map<String, Object?>>()
        .where((issue) {
          return !issue.containsKey('pull_request');
        })
        .map(_normalizeIssue)
        .toList();
  }

  Future<Map<String, Object?>> createIssue(
    Workspace workspace, {
    required String repository,
    required String title,
    String? body,
    String? projectId,
  }) async {
    _requireRepository(workspace, repository);
    _requireGitHubIssuePermission(workspace, level: 'write');
    if (projectId != null) {
      if (!workspace.containsProject(projectId)) {
        throw const ApiError(
          400,
          'project_not_allowed',
          'Project is not configured for this workspace.',
        );
      }
      _requireGitHubProjectPermission(workspace, level: 'write');
    }
    final response = await _rest(
      workspace,
      'POST',
      '/repos/$repository/issues',
      body: {'title': title, 'body': ?body},
    );
    final issue = _asMap(response);
    String? projectItemId;
    if (projectId != null) {
      final nodeId = issue['node_id'] as String?;
      if (nodeId != null) {
        final added = await _graphql(
          workspace,
          r'''
            mutation AddIssue($projectId: ID!, $contentId: ID!) {
              addProjectV2ItemById(input: {projectId: $projectId, contentId: $contentId}) {
                item { id }
              }
            }
          ''',
          {'projectId': projectId, 'contentId': nodeId},
          repository: repository,
        );
        projectItemId =
            (_asMap(_asMap(added['addProjectV2ItemById'])['item'])['id']
                as String?);
      }
    }
    return {..._normalizeIssue(issue), 'projectItemId': ?projectItemId};
  }

  Future<Map<String, Object?>> updateIssue(
    Workspace workspace, {
    required String repository,
    required int number,
    String? title,
    String? body,
    String? state,
  }) async {
    _requireRepository(workspace, repository);
    _requireGitHubIssuePermission(workspace, level: 'write');
    if (state != null && state != 'open' && state != 'closed') {
      throw const ApiError(
        400,
        'invalid_issue_state',
        'Issue state must be open or closed.',
      );
    }
    if (title == null && body == null && state == null) {
      throw const ApiError(
        400,
        'empty_issue_update',
        'Provide an issue field to update.',
      );
    }
    final response = await _rest(
      workspace,
      'PATCH',
      '/repos/$repository/issues/$number',
      body: {'title': ?title, 'body': ?body, 'state': ?state},
    );
    return _normalizeIssue(_asMap(response));
  }

  Future<void> addIssueComment(
    Workspace workspace, {
    required String repository,
    required int number,
    required String body,
  }) async {
    _requireRepository(workspace, repository);
    _requireGitHubIssuePermission(workspace, level: 'write');
    if (number <= 0 || body.trim().isEmpty || body.length > 10000) {
      throw const ApiError(
        400,
        'issue_comment_invalid',
        'Provide a valid issue comment.',
      );
    }
    await _rest(
      workspace,
      'POST',
      '/repos/$repository/issues/$number/comments',
      body: {'body': body.trim()},
    );
  }

  /// Restores the label shape produced by [createIssue].
  ///
  /// New Workshop issues are filed without labels. Replacing the exact
  /// issue's labels with an empty list is idempotent, leaves the issue and its
  /// comments intact, and avoids relying on a changing label catalog.
  Future<void> clearIssueLabels(
    Workspace workspace, {
    required String repository,
    required int number,
  }) async {
    _requireRepository(workspace, repository);
    _requireGitHubIssuePermission(workspace, level: 'write');
    if (number <= 0) {
      throw const ApiError(
        400,
        'invalid_issue_number',
        'Issue number is invalid.',
      );
    }
    await _rest(
      workspace,
      'PUT',
      '/repos/$repository/issues/$number/labels',
      body: {'labels': <String>[]},
    );
  }

  Future<Map<String, Object?>> readWorkflowCatalogFile(
    Workspace workspace,
    String repository,
  ) async {
    _requireRepository(workspace, repository);
    final repositoryData = _asMap(
      await _rest(workspace, 'GET', '/repos/$repository'),
    );
    final repositoryId = repositoryData['id'];
    final defaultBranch = repositoryData['default_branch'];
    if (repositoryId is! num ||
        repositoryId.toInt() <= 0 ||
        defaultBranch is! String ||
        defaultBranch.isEmpty) {
      throw const ApiError(
        502,
        'github_response_invalid',
        'GitHub returned an invalid default branch.',
      );
    }
    final ref = Uri.encodeQueryComponent(defaultBranch);
    final file = _asMap(
      await _rest(
        workspace,
        'GET',
        '/repos/$repository/contents/.ii-os/catalog.yaml?ref=$ref',
      ),
    );
    final encoded = file['content'];
    final sha = file['sha'];
    if (file['type'] != 'file' ||
        file['encoding'] != 'base64' ||
        encoded is! String ||
        sha is! String) {
      throw const ApiError(
        422,
        'workflow_catalog_invalid',
        'The repository workflow catalog is not a readable file.',
      );
    }
    try {
      return {
        'repository': repository,
        'repositoryId': repositoryId.toInt(),
        'ref': defaultBranch,
        'sha': sha,
        'content': utf8.decode(base64Decode(encoded.replaceAll('\n', ''))),
      };
    } on FormatException {
      throw const ApiError(
        422,
        'workflow_catalog_invalid',
        'The repository workflow catalog is not valid UTF-8.',
      );
    }
  }

  Future<void> dispatchWorkflow(
    Workspace workspace, {
    required String repository,
    required String workflowPath,
    required String ref,
    required Map<String, String> inputs,
  }) async {
    _requireRepository(workspace, repository);
    final filename = Uri.encodeComponent(_workflowFilename(workflowPath));
    await _rest(
      workspace,
      'POST',
      '/repos/$repository/actions/workflows/$filename/dispatches',
      body: {'ref': ref, 'inputs': inputs},
    );
  }

  Future<List<Map<String, Object?>>> listRepositoryWorkflows(
    Workspace workspace,
    String repository,
  ) async {
    _requireRepository(workspace, repository);
    final response = _asMap(
      await _rest(
        workspace,
        'GET',
        '/repos/$repository/actions/workflows?per_page=100',
      ),
    );
    final workflows = response['workflows'];
    if (workflows is! List<Object?>) {
      throw const ApiError(
        502,
        'github_response_invalid',
        'GitHub returned invalid workflow data.',
      );
    }
    return workflows.whereType<Map<String, Object?>>().toList();
  }

  Future<List<Map<String, Object?>>> listWorkflowRuns(
    Workspace workspace, {
    required String repository,
    required String workflowPath,
    DateTime? createdSince,
    DateTime? createdUntil,
  }) async {
    _requireRepository(workspace, repository);
    final filename = Uri.encodeComponent(_workflowFilename(workflowPath));
    final createdRange = switch ((createdSince, createdUntil)) {
      (final DateTime since, final DateTime until) =>
        '${since.toUtc().toIso8601String()}..${until.toUtc().toIso8601String()}',
      (final DateTime since, null) => '>=${since.toUtc().toIso8601String()}',
      (null, final DateTime until) => '<=${until.toUtc().toIso8601String()}',
      (null, null) => null,
    };
    final createdFilter = createdRange == null
        ? ''
        : '&created=${Uri.encodeQueryComponent(createdRange)}';
    final response = _asMap(
      await _rest(
        workspace,
        'GET',
        '/repos/$repository/actions/workflows/$filename/runs?event=workflow_dispatch&per_page=100$createdFilter',
      ),
    );
    final runs = response['workflow_runs'];
    if (runs is! List<Object?>) {
      throw const ApiError(
        502,
        'github_response_invalid',
        'GitHub returned invalid workflow run data.',
      );
    }
    return runs.whereType<Map<String, Object?>>().toList();
  }

  Future<Map<String, Object?>> getWorkflowRun(
    Workspace workspace, {
    required String repository,
    required int runId,
  }) async {
    _requireRepository(workspace, repository);
    if (runId <= 0) {
      throw const ApiError(
        400,
        'invalid_workflow_run',
        'The GitHub workflow run ID is invalid.',
      );
    }
    return _asMap(
      await _rest(workspace, 'GET', '/repos/$repository/actions/runs/$runId'),
    );
  }

  Future<void> cancelWorkflowRun(
    Workspace workspace, {
    required String repository,
    required int runId,
  }) async {
    _requireRepository(workspace, repository);
    if (runId <= 0) {
      throw const ApiError(
        400,
        'invalid_workflow_run',
        'The GitHub workflow run ID is invalid.',
      );
    }
    await _rest(
      workspace,
      'POST',
      '/repos/$repository/actions/runs/$runId/cancel',
    );
  }

  Future<Object?> _rest(
    Workspace workspace,
    String method,
    String path, {
    Map<String, Object?>? body,
    Duration timeout = const Duration(seconds: 25),
  }) => _transport.rest(workspace, method, path, body: body, timeout: timeout);

  Future<Map<String, Object?>> _graphql(
    Workspace workspace,
    String query,
    Map<String, Object?> variables, {
    String? repository,
  }) => _transport.graphql(workspace, query, variables, repository: repository);

  void _requireRepository(Workspace workspace, String repository) {
    if (workspace.githubInstallationId == null) {
      throw const ApiError(
        409,
        'github_installation_required',
        'Configure the GitHub App installation and repository first.',
      );
    }
    final valid = RegExp(
      r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$',
    ).hasMatch(repository);
    if (!valid || !workspace.containsRepository(repository)) {
      throw const ApiError(
        400,
        'repository_not_allowed',
        'Repository is not configured for this workspace.',
      );
    }
  }
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  throw const ApiError(
    502,
    'github_response_invalid',
    'GitHub returned invalid data.',
  );
}

List<GitHubProjectConfig> parseLinkedGitHubProjects(
  Map<String, Object?> data, {
  required String owner,
}) {
  final repository = _asMap(data['repository']);
  final connection = _asMap(repository['projectsV2']);
  final nodes = connection['nodes'];
  if (nodes is! List<Object?>) {
    throw const ApiError(
      502,
      'github_response_invalid',
      'GitHub returned invalid Project data.',
    );
  }
  return nodes
      .whereType<Map<String, Object?>>()
      .where((node) => node['closed'] != true)
      .map(
        (node) => GitHubProjectConfig(
          id: node['id'] as String? ?? '',
          number: (node['number'] as num?)?.toInt() ?? 0,
          owner: owner,
          title: node['title'] as String? ?? '',
        ),
      )
      .where(
        (project) =>
            project.id.isNotEmpty &&
            project.number > 0 &&
            project.title.isNotEmpty,
      )
      .toList(growable: false);
}

Map<String, Object?> _normalizeIssue(Map<String, Object?> issue) {
  final content = TicketContent.parse(issue['body']);
  return {
    'id': issue['node_id'],
    'number': issue['number'],
    'title': issue['title'],
    'body': issue['body'],
    'state': issue['state'],
    'url': issue['html_url'],
    'updatedAt': issue['updated_at'],
    ...content.toJson(),
  };
}

String _workflowFilename(String path) {
  final valid = RegExp(
    r'^\.github/workflows/[A-Za-z0-9_.-]+\.ya?ml$',
  ).hasMatch(path);
  if (!valid) {
    throw const ApiError(
      422,
      'workflow_catalog_invalid',
      'A dispatch workflow path is invalid.',
    );
  }
  return path.split('/').last;
}
