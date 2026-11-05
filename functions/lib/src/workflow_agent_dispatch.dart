part of 'workflow_api.dart';

extension WorkflowAgentDispatch on WorkflowApi {
  Future<Response> _handleAgentDispatch(
    Request request,
    String requestId,
    List<String> path,
    GitHubActionsPrincipal principal,
  ) async {
    if (request.method != 'POST' ||
        path.length != 5 ||
        !principal.jobUses(iiOsAgentTaskWorkflow)) {
      throw const ApiError(404, 'not_found', 'Workflow route not found.');
    }
    if (credentialOperations.contains(path[4])) {
      return _ticketCredential(
        request,
        requestId,
        path[2],
        path[3],
        path[4],
        principal,
      );
    }
    if (path[4] == 'finalize') {
      return _finalizeAgentDispatch(
        request,
        requestId,
        path[2],
        path[3],
        principal,
      );
    }
    if (path[4] == 'authorize-publication') {
      return _authorizeAgentPublication(
        request,
        requestId,
        path[2],
        path[3],
        principal,
      );
    }
    if (path[4] == 'execution-state') {
      return _recordAgentExecutionState(
        request,
        requestId,
        path[2],
        path[3],
        principal,
      );
    }
    if (path[4] == 'fleet-state') {
      return _recordAgentFleetState(
        request,
        requestId,
        path[2],
        path[3],
        principal,
      );
    }
    if (path[4] != 'consume') {
      throw const ApiError(404, 'not_found', 'Workflow route not found.');
    }
    final workspaceId = path[2];
    final projectItemId = path[3];
    final body = await readJsonObject(request);
    final claimId = requiredString(body, 'dispatchId', maxLength: 200);
    final permissionProfile = requiredString(
      body,
      'permissionProfile',
      maxLength: 128,
    );
    final permissionDigest = requiredString(
      body,
      'permissionDigest',
      maxLength: 64,
    );
    final issueNumber = body['issueNumber'];
    if (issueNumber is! int || issueNumber <= 0) {
      throw const ApiError(
        400,
        'agent_dispatch_input_invalid',
        'The approved issue number is invalid.',
      );
    }
    return _audited(
      requestId: requestId,
      actor: principal.auditActor,
      workspaceId: workspaceId,
      action: 'agent.dispatch.approval.consume',
      targetType: 'github_workflow_run',
      targetId: '${principal.runId}:${principal.runAttempt}',
      metadata: {
        'repository': principal.repository,
        'projectItemId': projectItemId,
        'issueNumber': issueNumber,
        'dispatchId': claimId,
      },
      execute: () async {
        final activations = AgentActivationStore(store, engines: agentEngines);
        final approval = await activations.workflowApproval(
          principal: principal,
          workspaceId: workspaceId,
          projectItemId: projectItemId,
          claimId: claimId,
          issueNumber: issueNumber,
          permissionProfile: permissionProfile,
          permissionDigest: permissionDigest,
        );
        AgentQueueTicket? currentTicket;
        if (approval['alreadyConsumed'] != true) {
          final projectId = approval['projectId'] as String;
          final statusFieldId = approval['projectStatusFieldId'] as String;
          final workspace = await store.getWorkspace(workspaceId);
          final github = await githubForWorkspace(workspace);
          final item = await github.readAgentQueueProjectItem(
            workspace,
            projectId: projectId,
            itemId: projectItemId,
            repository: principal.repository,
          );
          currentTicket = AgentQueueTicket.parse(item, statusFieldId);
        }
        return activations.consumeFromWorkflow(
          principal: principal,
          workspaceId: workspaceId,
          projectItemId: projectItemId,
          claimId: claimId,
          issueNumber: issueNumber,
          permissionProfile: permissionProfile,
          permissionDigest: permissionDigest,
          currentTicket: currentTicket,
        );
      },
    );
  }

  Future<Response> _recordAgentFleetState(
    Request request,
    String requestId,
    String workspaceId,
    String projectItemId,
    GitHubActionsPrincipal principal,
  ) async {
    final body = await readJsonObject(request);
    final claimId = requiredString(body, 'dispatchId', maxLength: 200);
    final fleetJobId = requiredString(body, 'fleetJobId', maxLength: 200);
    final state = requiredString(body, 'state', maxLength: 32);
    final leaseValue = body['fleetLeaseId'];
    final fleetLeaseId = leaseValue == null
        ? ''
        : requiredString(body, 'fleetLeaseId', maxLength: 128);
    final issueNumber = body['issueNumber'];
    if (issueNumber is! int || issueNumber <= 0) {
      throw const ApiError(
        400,
        'agent_fleet_state_invalid',
        'The Fleet lifecycle issue number is invalid.',
      );
    }
    return _audited(
      requestId: requestId,
      actor: principal.auditActor,
      workspaceId: workspaceId,
      action: 'agent.dispatch.fleet.state',
      targetType: 'fleet_job',
      targetId: fleetJobId,
      metadata: {
        'repository': principal.repository,
        'projectItemId': projectItemId,
        'issueNumber': issueNumber,
        'dispatchId': claimId,
        'state': state,
      },
      execute: () async {
        final recorded =
            await AgentActivationStore(
              store,
              engines: agentEngines,
            ).recordFleetState(
              principal: principal,
              workspaceId: workspaceId,
              projectItemId: projectItemId,
              claimId: claimId,
              issueNumber: issueNumber,
              fleetJobId: fleetJobId,
              fleetLeaseId: fleetLeaseId,
              state: state,
            );
        if (state == 'running') {
          final projectId = recorded['projectId'] as String? ?? '';
          final fieldId = recorded['projectStatusFieldId'] as String? ?? '';
          final optionId =
              recorded['projectInProgressOptionId'] as String? ?? '';
          if (projectId.isEmpty || fieldId.isEmpty || optionId.isEmpty) {
            throw const ApiError(
              409,
              'agent_fleet_state_invalid',
              'The Fleet lifecycle status authority is invalid.',
            );
          }
          final workspace = await store.getWorkspace(workspaceId);
          final github = await githubForWorkspace(workspace);
          await github.updateProjectItemField(
            workspace,
            projectId: projectId,
            itemId: projectItemId,
            fieldId: fieldId,
            value: {'singleSelectOptionId': optionId},
            repository: principal.repository,
          );
        }
        return recorded;
      },
    );
  }

  Future<Response> _authorizeAgentPublication(
    Request request,
    String requestId,
    String workspaceId,
    String projectItemId,
    GitHubActionsPrincipal principal,
  ) async {
    final result = AgentDispatchResult.parse(await readJsonObject(request));
    if (result.projectItemId != projectItemId ||
        result.repository != principal.repository ||
        result.repositoryId != principal.repositoryId ||
        !result.hasPublishableChange ||
        !agentRepositories.allowsPublication(
          source: principal.repository,
          target: result.pullRequest!.repository,
        )) {
      throw _finalizationInvalid;
    }
    final digest = sha256
        .convert(utf8.encode(jsonEncode(result.canonicalJson)))
        .toString();
    final repositoryPolicy =
        await AgentActivationStore(
          store,
          engines: agentEngines,
        ).repositoryPolicyForFinalization(
          principal: principal,
          workspaceId: workspaceId,
          projectItemId: projectItemId,
          claimId: result.dispatchId,
          issueNumber: result.issueNumber,
        );
    if (!repositoryPolicy.mayPublishChanges) {
      throw const ApiError(
        403,
        'agent_repository_action_forbidden',
        'This agent permission profile cannot publish repository changes.',
      );
    }
    return _audited(
      requestId: requestId,
      actor: principal.auditActor,
      workspaceId: workspaceId,
      action: 'agent.dispatch.branch.authorize',
      targetType: 'github_workflow_run',
      targetId: '${principal.runId}:${principal.runAttempt}',
      metadata: {
        'repository': principal.repository,
        'projectItemId': projectItemId,
        'issueNumber': result.issueNumber,
        'dispatchId': result.dispatchId,
        'resultDigest': digest,
      },
      execute: () async {
        await AgentFinalizationStore(store).authorizePublication(
          principal: principal,
          workspaceId: workspaceId,
          projectItemId: projectItemId,
          claimId: result.dispatchId,
          issueNumber: result.issueNumber,
        );
        final workspace = await store.getWorkspace(workspaceId);
        final github = await githubForWorkspace(workspace);
        final target = result.pullRequest!;
        final writer = await github.issueAgentBranchWriterToken(
          workspace,
          repository: target.repository,
          repositoryId: target.repositoryId,
        );
        return {
          'authorized': true,
          'resultDigest': digest,
          'publicationToken': writer.token,
          'publicationAppLogin': await github.agentBrokerBotLogin(),
          'publicationRepository': target.repository,
          'publicationRepositoryId': target.repositoryId,
        };
      },
    );
  }

  Future<Response> _finalizeAgentDispatch(
    Request request,
    String requestId,
    String workspaceId,
    String projectItemId,
    GitHubActionsPrincipal principal,
  ) async {
    final body = await readJsonObject(request);
    final result = AgentDispatchResult.parse(body);
    if (result.projectItemId != projectItemId ||
        result.repository != principal.repository ||
        result.repositoryId != principal.repositoryId) {
      throw const ApiError(
        409,
        'agent_dispatch_finalization_invalid',
        'This result is not bound to the exact workflow and Project item.',
      );
    }
    final digest = sha256
        .convert(utf8.encode(jsonEncode(result.canonicalJson)))
        .toString();
    return _audited(
      requestId: requestId,
      actor: principal.auditActor,
      workspaceId: workspaceId,
      action: 'agent.dispatch.result.finalize',
      targetType: 'github_workflow_run',
      targetId: '${principal.runId}:${principal.runAttempt}',
      metadata: {
        'repository': principal.repository,
        'projectItemId': projectItemId,
        'issueNumber': result.issueNumber,
        'dispatchId': result.dispatchId,
        'outcome': result.outcome,
        'projectStatus': result.projectStatus,
        if (result.automationFailure != null)
          'automationFailureCode': result.automationFailure!.code,
      },
      execute: () => _applyAgentDispatchResult(
        workspaceId: workspaceId,
        projectItemId: projectItemId,
        principal: principal,
        result: result,
        resultDigest: digest,
      ),
    );
  }

  Future<Map<String, Object?>> _applyAgentDispatchResult({
    required String workspaceId,
    required String projectItemId,
    required GitHubActionsPrincipal principal,
    required AgentDispatchResult result,
    required String resultDigest,
  }) async {
    final finalizations = AgentFinalizationStore(store);
    final reservation = await finalizations.reserve(
      principal: principal,
      workspaceId: workspaceId,
      projectItemId: projectItemId,
      claimId: result.dispatchId,
      issueNumber: result.issueNumber,
      resultDigest: resultDigest,
    );
    if (reservation['reservationState'] == 'finalized') {
      return agentFinalizationResponse(
        workspaceId: workspaceId,
        projectItemId: projectItemId,
        principal: principal,
        result: result,
        resultDigest: resultDigest,
        idempotent: true,
        mutated: reservation['finalMutationApplied'] == true,
        projectStatus: reservation['finalProjectStatus'] as String?,
      );
    }
    final reservationId =
        reservation['finalizationReservationId'] as String? ?? '';
    if (reservationId.isEmpty) throw _finalizationInvalid;
    final activatedRepository = reservation['repository'] as String? ?? '';
    final activatedIssueNumber = reservation['issueNumber'];
    final activatedTicketTitle = reservation['ticketTitle'];
    if (activatedRepository != principal.repository ||
        activatedIssueNumber is! int ||
        activatedIssueNumber <= 0 ||
        activatedTicketTitle is! String ||
        activatedTicketTitle.trim().isEmpty) {
      throw _finalizationInvalid;
    }
    try {
      final workspace = await store.getWorkspace(workspaceId);
      final github = await githubForWorkspace(workspace);
      final pullRequest = result.pullRequest;
      final pullRequestUrl = pullRequest == null
          ? null
          : await github.ensureAgentPullRequest(
              workspace,
              repository: pullRequest.repository,
              issueNumber: activatedIssueNumber,
              issueTitle: activatedTicketTitle,
              head: pullRequest.head,
              base: pullRequest.base,
              headSha: pullRequest.headSha,
              baseSha: pullRequest.baseSha,
            );
      final consumedAt = reservation['consumedAt'];
      final existing = await github.listIssueComments(
        workspace,
        repository: activatedRepository,
        number: activatedIssueNumber,
        createdSince: consumedAt is Timestamp
            ? consumedAt.toDate().toUtc().subtract(const Duration(minutes: 1))
            : null,
      );
      final trustedBrokerLogin = await github.agentBrokerBotLogin();
      final markerPrefix = sha256
          .convert(utf8.encode('${result.dispatchId}:$resultDigest'))
          .toString()
          .substring(0, 32);
      final comments = [
        ...result.comments,
        if (pullRequestUrl != null)
          'Trusted post-cleanup broker pull request: $pullRequestUrl',
      ];
      for (var index = 0; index < comments.length; index++) {
        final marker = '<!-- ii-os:agent-finalization:$markerPrefix:$index -->';
        if (existing.any(
          (comment) =>
              _trustedFinalizationComment(comment, marker, trustedBrokerLogin),
        )) {
          continue;
        }
        await github.addIssueComment(
          workspace,
          repository: activatedRepository,
          number: activatedIssueNumber,
          body: '$marker\n${comments[index]}',
        );
      }

      await finalizations.complete(
        workspaceId: workspaceId,
        projectItemId: projectItemId,
        reservationId: reservationId,
        outcome: result.outcome,
        projectStatus: result.projectStatus,
        mutated: true,
        resultDigest: resultDigest,
        pullRequestUrl: pullRequestUrl,
      );
      return agentFinalizationResponse(
        workspaceId: workspaceId,
        projectItemId: projectItemId,
        principal: principal,
        result: result,
        resultDigest: resultDigest,
        idempotent: false,
        mutated: true,
        projectStatus: result.projectStatus,
        pullRequestUrl: pullRequestUrl,
      );
    } on Object {
      await finalizations.release(
        workspaceId: workspaceId,
        projectItemId: projectItemId,
        reservationId: reservationId,
      );
      rethrow;
    }
  }
}

const _finalizationInvalid = ApiError(
  409,
  'agent_dispatch_finalization_invalid',
  'This result is not bound to the exact consumed agent dispatch.',
);

bool _trustedFinalizationComment(
  Map<String, Object?> comment,
  String marker,
  String trustedBrokerLogin,
) {
  final user = comment['user'];
  return (comment['body'] as String? ?? '').contains(marker) &&
      user is Map<String, Object?> &&
      user['login'] == trustedBrokerLogin &&
      user['type'] == 'Bot';
}
