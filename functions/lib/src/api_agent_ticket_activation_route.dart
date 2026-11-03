part of 'api.dart';

extension on IiOsApi {
  Future<Response?> _agentTicketActivationRoute(
    Request request,
    String requestId,
    AuthenticatedUser actor,
    String workspaceId,
    List<String> path,
  ) async {
    if (path.length != 7 ||
        path[4] != 'items' ||
        path[6] != 'agent-activation' ||
        request.method != 'PATCH') {
      return null;
    }
    await store.requireAccess(actor, workspaceId, Capability.ticketsWrite);
    final body = await readJsonObject(request);
    final ready = body['ready'];
    if (ready is! bool) {
      throw const ApiError(
        400,
        'agent_activation_invalid',
        'Choose whether to deploy or cancel this ticket.',
      );
    }
    final response = _optionalActivationResponse(body['response']);
    final projectId = requiredString(body, 'projectId', maxLength: 200);
    final workspace = await store.getWorkspace(workspaceId);
    final selectedRepository = selectedWorkspaceRepository(
      workspace,
      body['repository'],
    );
    final github = await githubForWorkspace(workspace);
    final target = AgentTicketActivationTarget.fromProject(
      projectId: projectId,
      itemId: path[5],
      project: await github.readAgentQueueProject(
        workspace,
        projectId,
        repository: selectedRepository,
      ),
      expectedRepository: selectedRepository,
    );
    final dispatchState = ready
        ? await _agentDispatchState(workspaceId, target.itemId)
        : const <String, Object?>{};
    final activationState = ready
        ? await _agentActivationState(workspaceId, target.itemId)
        : const <String, Object?>{};
    final effectiveDispatchState = ready
        ? cohesiveAgentDispatchState(dispatchState, activationState)
        : const <String, Object?>{};
    final effectiveDispatchStatus =
        effectiveDispatchState['status'] as String? ?? '';
    final retryFailed = effectiveDispatchState['status'] == 'retry_failed';
    final agentRequestedResponse = agentActivationRequiresResponse(
      activationState,
      currentTicketBodyDigest: ticketBodyDigest(target.ticket),
    );
    final requiresHumanResponse =
        target.needsHumanResponse || agentRequestedResponse;
    if (ready) {
      target.validateActivation(
        allowRecovery: true,
        dispatchStatus: effectiveDispatchStatus,
      );
      if (requiresHumanResponse && response.isEmpty) {
        throw const ApiError(
          422,
          'agent_response_required',
          'Answer the agent question before approving another agent pass.',
        );
      }
      final health = await inspectAgentRepositoryHealth(
        workspace: workspace,
        repository: target.repository,
        github: github,
        codexAuth: workflowApi.codexAuth,
        permissionProfileId: target.ticket.permissionProfile,
      );
      requireHealthyAgentRepository(health);
      final profile = await _validateAgentPermission(
        workspace,
        github,
        target,
        health.sourceSha,
      );
      final recoveryProof =
          await AgentWorkflowRecovery(
            readRun: (runId) => github.getWorkflowRun(
              workspace,
              repository: target.repository,
              runId: runId,
            ),
            cancelRun: (runId) => github.cancelWorkflowRun(
              workspace,
              repository: target.repository,
              runId: runId,
            ),
            discoverRuns: (dispatch) async {
              final dispatchedAt = dispatch['dispatchedAt'];
              final requestId = dispatch['requestId'];
              final issueNumber = dispatch['issueNumber'];
              final sourceSha = dispatch['trustedSourceSha'];
              final sourceRef = dispatch['trustedSourceRef'];
              if (dispatchedAt is! Timestamp ||
                  requestId is! String ||
                  issueNumber is! int ||
                  sourceSha is! String ||
                  sourceRef is! String) {
                throw const ApiError(
                  409,
                  'agent_recovery_workflow_invalid',
                  'The stopped workflow no longer matches this ticket. Refresh before deploying it again.',
                );
              }
              final runs = await github.listWorkflowRuns(
                workspace,
                repository: target.repository,
                workflowPath: '.github/workflows/$iiOsAgentTaskWorkflow',
                createdSince: dispatchedAt.toDate().toUtc().subtract(
                  const Duration(minutes: 1),
                ),
              );
              return matchingHumanDeploymentWorkflowRuns(
                runs,
                expectedTitle:
                    'ii-os agent / ${target.repository}#$issueNumber / $requestId',
                expectedActor: await github.agentBrokerBotLogin(),
                expectedSourceRef: sourceRef,
                expectedSourceSha: sourceSha,
                dispatchedAt: dispatchedAt.toDate().toUtc(),
              );
            },
          ).stopIfRequired(
            recoveryStatus: effectiveDispatchStatus,
            repository: target.repository,
            dispatch: dispatchState,
            allowNewerRunAttempt: activationState['status'] == 'claiming',
          );
      return _updateAgentActivation(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        projectId: projectId,
        target: target,
        profile: profile,
        health: health,
        workspace: workspace,
        github: github,
        response: response,
        retryFailed: retryFailed,
        resumingQuestion: requiresHumanResponse,
        ready: true,
        recoveryProof: recoveryProof,
      );
    }

    return _updateAgentActivation(
      requestId: requestId,
      actor: actor,
      workspaceId: workspaceId,
      projectId: projectId,
      target: target,
      workspace: workspace,
      github: github,
      response: response,
      retryFailed: retryFailed,
      resumingQuestion: false,
      ready: false,
    );
  }

  Future<Response> _updateAgentActivation({
    required String requestId,
    required AuthenticatedUser actor,
    required String workspaceId,
    required String projectId,
    required AgentTicketActivationTarget target,
    required Workspace workspace,
    required GitHubClient github,
    required String response,
    required bool retryFailed,
    required bool resumingQuestion,
    required bool ready,
    AgentPermissionProfile? profile,
    AgentRepositoryHealth? health,
    AgentWorkflowRecoveryProof? recoveryProof,
  }) => _audited(
    requestId: requestId,
    actor: actor,
    workspaceId: workspaceId,
    action: ready ? 'agent.ticket.activate' : 'agent.ticket.pause',
    targetType: 'github_issue',
    targetId: '${target.repository}#${target.issueNumber}',
    metadata: {
      'projectId': projectId,
      'projectItemId': target.itemId,
      'permissionProfile': target.ticket.permissionProfile,
      'permissionRef': target.ticket.permissionRef,
      'resumingQuestion': resumingQuestion,
      'retryingConfigurationFailure': retryFailed,
      'hasResponse': response.isNotEmpty,
    },
    execute: () async {
      if (ready) {
        final activations = AgentActivationStore(store);
        await activations.activate(
          workspaceId: workspaceId,
          projectId: projectId,
          projectStatusFieldId: target.statusFieldId,
          projectInProgressOptionId: target.inProgressOptionId,
          projectItemId: target.itemId,
          repositoryId: target.repositoryId,
          repository: target.repository,
          issueNumber: target.issueNumber,
          title: target.title,
          ticket: target.ticket,
          activationResponse: response,
          profile: profile!,
          trustedSourceSha: health!.sourceSha,
          trustedSourceRef: health.sourceRef,
          actor: actor,
          recoveryProof: recoveryProof,
        );
        var dispatchTarget = target;
        if (target.status != 'Todo') {
          await github.updateProjectItemField(
            workspace,
            repository: target.repository,
            projectId: projectId,
            itemId: target.itemId,
            fieldId: target.statusFieldId,
            value: {'singleSelectOptionId': target.todoOptionId},
          );
          dispatchTarget = AgentTicketActivationTarget.fromProject(
            projectId: projectId,
            itemId: target.itemId,
            project: await github.readAgentQueueProject(
              workspace,
              projectId,
              repository: target.repository,
            ),
            expectedRepository: target.repository,
          );
          dispatchTarget.validateActivation();
          if (!_sameActivationTicket(target, dispatchTarget)) {
            throw const ApiError(
              409,
              'agent_ticket_changed_during_activation',
              'The ticket changed while returning it to Todo. Review it again before deploying.',
            );
          }
        }
        final dispatch =
            await AgentTicketDispatcher(
              store: store,
              audit: audit,
              codexAuth: workflowApi.codexAuth,
              activations: activations,
            ).dispatchHumanDeployment(
              workspace: workspace,
              github: github,
              target: dispatchTarget,
              requestId: requestId,
              actor: actor,
            );
        return {
          'projectId': projectId,
          'projectItemId': target.itemId,
          'repository': target.repository,
          'issueNumber': target.issueNumber,
          'agent': {'ready': true},
          ...dispatch,
        };
      } else {
        await AgentActivationStore(store).revoke(
          workspaceId: workspaceId,
          projectItemId: target.itemId,
          actor: actor,
        );
      }
      return {
        'projectId': projectId,
        'projectItemId': target.itemId,
        'repository': target.repository,
        'issueNumber': target.issueNumber,
        'agent': {'ready': ready},
        'status': 'paused',
      };
    },
  );

  Future<Map<String, Object?>> _agentDispatchState(
    String workspaceId,
    String itemId,
  ) async {
    final snapshot = await store.firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('agentDispatches')
        .doc(itemId)
        .get();
    return snapshot.data() ?? const {};
  }

  Future<Map<String, Object?>> _agentActivationState(
    String workspaceId,
    String itemId,
  ) async {
    final snapshot = await store.firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('agentActivations')
        .doc(itemId)
        .get();
    return snapshot.data() ?? const {};
  }

  Future<AgentPermissionProfile> _validateAgentPermission(
    Workspace workspace,
    GitHubClient github,
    AgentTicketActivationTarget target,
    String trustedSourceSha,
  ) async {
    final workflowKey = '${target.repository}#$iiOsAgentTaskWorkflow';
    if (!workspace.workflows.contains(workflowKey)) {
      throw const ApiError(
        409,
        'agent_workflow_not_enabled',
        'Enable the ii-os agent workflow for this repository first.',
      );
    }
    final profiles = await github.listAgentPermissionProfiles(
      workspace,
      repository: target.repository,
      ref: trustedSourceSha,
    );
    final profile = executableAgentPermissionProfileFromListings(
      profiles,
      target.ticket.permissionProfile,
    );
    if (profile == null) {
      throw const ApiError(
        422,
        'agent_permission_not_installed',
        'Install the selected agent permission profile before activation.',
      );
    }
    if (profile.workflow.file != iiOsAgentTaskWorkflow ||
        profile.workflow.ref != target.ticket.permissionRef) {
      throw const ApiError(
        422,
        'agent_permission_workflow_invalid',
        'The selected permission profile does not dispatch the approved agent workflow.',
      );
    }
    return profile;
  }
}

bool _sameActivationTicket(
  AgentTicketActivationTarget before,
  AgentTicketActivationTarget after,
) =>
    before.projectId == after.projectId &&
    before.itemId == after.itemId &&
    before.repository == after.repository &&
    before.repositoryId == after.repositoryId &&
    before.issueNumber == after.issueNumber &&
    before.title == after.title &&
    before.issueUrl == after.issueUrl &&
    before.issueState == after.issueState &&
    before.statusFieldId == after.statusFieldId &&
    before.todoOptionId == after.todoOptionId &&
    before.inProgressOptionId == after.inProgressOptionId &&
    ticketBodyDigest(before.ticket) == ticketBodyDigest(after.ticket);

String _optionalActivationResponse(Object? value) {
  if (value == null) return '';
  if (value is! String || value.length > 8000) {
    throw const ApiError(
      400,
      'agent_response_invalid',
      'The response to the agent is invalid or too long.',
    );
  }
  return value.trim();
}
