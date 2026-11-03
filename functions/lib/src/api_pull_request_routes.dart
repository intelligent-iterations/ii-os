part of 'api.dart';

extension on IiOsApi {
  Future<Response?> _pullRequestRoute(
    Request request,
    String requestId,
    AuthenticatedUser actor,
    String workspaceId,
    List<String> path,
  ) async {
    final isRead =
        path.length == 7 &&
        path[4] == 'items' &&
        path[6] == 'pull-request' &&
        request.method == 'GET';
    final isMerge =
        path.length == 8 &&
        path[4] == 'items' &&
        path[6] == 'pull-request' &&
        path[7] == 'merge' &&
        request.method == 'POST';
    if (!isRead && !isMerge) return null;

    await store.requireAccess(
      actor,
      workspaceId,
      isMerge ? Capability.pullRequestsMerge : Capability.ticketsRead,
    );
    final workspace = await store.getWorkspace(workspaceId);
    final identity = await _recordedAgentPullRequest(
      workspaceId,
      path[5],
      workspace,
    );
    final github = await githubForWorkspace(workspace);
    if (isRead) {
      return jsonResponse(200, {
        'pullRequest': await github.getPullRequestWithQaDeployment(
          workspace,
          repository: identity.$1,
          number: identity.$2,
        ),
      }, requestId: requestId);
    }

    final body = await readJsonObject(request);
    final expectedHeadSha = requiredString(
      body,
      'expectedHeadSha',
      maxLength: 40,
    );
    return _audited(
      requestId: requestId,
      actor: actor,
      workspaceId: workspaceId,
      action: 'pull_request.approve_and_merge',
      targetType: 'github_pull_request',
      targetId: '${identity.$1}#${identity.$2}',
      metadata: {
        'repository': identity.$1,
        'number': identity.$2,
        'expectedHeadSha': expectedHeadSha,
        'approvalSource': 'ii-os-workspace-member',
      },
      execute: () => github.mergeAgentPullRequest(
        workspace,
        repository: identity.$1,
        number: identity.$2,
        expectedHeadSha: expectedHeadSha,
      ),
    );
  }

  Future<(String, int, String?)> _recordedAgentPullRequest(
    String workspaceId,
    String itemId,
    Workspace workspace,
  ) async {
    final root = store.firestore.collection('workspaces').doc(workspaceId);
    final records = await store.firestore.getAll([
      root.collection('agentDispatches').doc(itemId),
      // The activation is the immutable receipt and wins over its mutable
      // dispatch mirror when both carry a final pull request.
      root.collection('agentActivations').doc(itemId),
    ]);
    String? url;
    String? activatedRepository;
    String? ticketBodyDigest;
    for (final record in records) {
      final data = record.data();
      if (data == null) continue;
      final candidate = data['finalPullRequestUrl'];
      if (candidate is String && candidate.isNotEmpty) url = candidate;
      final repository = data['repository'];
      if (repository is String && repository.isNotEmpty) {
        activatedRepository = repository;
      }
      final digest = data['ticketBodyDigest'];
      if (digest is String && digest.isNotEmpty) ticketBodyDigest = digest;
    }
    final uri = url == null ? null : Uri.tryParse(url);
    final segments = uri?.pathSegments ?? const <String>[];
    final number = segments.length == 4 && segments[2] == 'pull'
        ? int.tryParse(segments[3])
        : null;
    final repository = segments.length == 4
        ? '${segments[0]}/${segments[1]}'
        : '';
    final sourceTargetAllowed = agentRepositories.allowsPublication(
      source: activatedRepository ?? '',
      target: repository,
    );
    if (uri?.scheme != 'https' ||
        uri?.host != 'github.com' ||
        uri?.hasQuery == true ||
        uri?.hasFragment == true ||
        number == null ||
        number <= 0 ||
        !workspace.containsRepository(repository) ||
        !sourceTargetAllowed) {
      throw const ApiError(
        404,
        'agent_pull_request_not_found',
        'This ticket does not have a trusted agent pull request yet.',
      );
    }
    return (repository, number, ticketBodyDigest);
  }
}
