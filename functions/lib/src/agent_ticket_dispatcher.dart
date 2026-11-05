import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:google_cloud_firestore/google_cloud_firestore.dart';

import 'agent_activation_store.dart';
import 'agent_permission_profile.dart';
import 'agent_ticket_activation.dart';
import 'api_error.dart';
import 'audit_sink.dart';
import 'auth_service.dart';
import 'codex_auth_store.dart';
import 'domain.dart';
import 'github_client.dart';
import 'ticket_content.dart';
import 'workspace_store.dart';

/// Dispatches one exact human-approved Workshop pass immediately.
///
/// The browser request is the trigger. This class does not scan queues, poll,
/// recur, or create approvals. Fleet remains downstream of the allowlisted
/// GitHub workflow and owns workload placement, isolation, and cleanup proof.
final class AgentTicketDispatcher {
  AgentTicketDispatcher({
    required this.store,
    required this.audit,
    required this.codexAuth,
    required this.activations,
  });

  final WorkspaceStore store;
  final AuditSink audit;
  final CodexAuthStore codexAuth;
  final AgentActivationStore activations;

  Future<Map<String, Object?>> dispatchHumanDeployment({
    required Workspace workspace,
    required GitHubClient github,
    required AgentTicketActivationTarget target,
    required String requestId,
    required AuthenticatedUser actor,
  }) async {
    final ticket = AgentQueueTicket(
      itemId: target.itemId,
      issueNumber: target.issueNumber,
      title: target.title,
      repository: target.repository,
      repositoryId: target.repositoryId,
      status: target.status,
      permissionProfile: target.ticket.permissionProfile,
      permissionRef: target.ticket.permissionRef,
      structured: target.ticket.structured,
      requirementsComplete:
          target.ticket.definitionOfDone.isNotEmpty &&
          target.ticket.howToTest.isNotEmpty,
      content: target.ticket,
    );
    if (ticket.status != 'Todo') {
      throw const ApiError(
        409,
        'agent_ticket_not_todo',
        'The approved ticket must still be open and in Todo.',
      );
    }
    final queue = AgentQueueProject(
      projectId: target.projectId,
      statusFieldId: target.statusFieldId,
      inProgressOptionId: target.inProgressOptionId,
    );
    final dispatchId = humanAgentDispatchId(requestId, target.itemId);
    final approval = await activations.claim(
      workspaceId: workspace.id,
      projectId: target.projectId,
      ticket: ticket,
      claimId: dispatchId,
    );
    if (approval == null) {
      throw const ApiError(
        409,
        'agent_approval_unavailable',
        'This deployment approval changed before dispatch. Review and deploy it again.',
      );
    }
    await _dispatch(
      workspace: workspace,
      github: github,
      queue: queue,
      ticket: ticket,
      approval: approval,
      dispatchId: dispatchId,
      actor: actor,
    );
    return {
      'dispatchId': dispatchId,
      'status': 'workflow_bound',
      'projectItemId': target.itemId,
    };
  }

  Future<void> _dispatch({
    required Workspace workspace,
    required GitHubClient github,
    required AgentQueueProject queue,
    required AgentQueueTicket ticket,
    required AgentActivationClaim approval,
    required String dispatchId,
    required AuthenticatedUser actor,
  }) async {
    await audit.record(
      requestId: dispatchId,
      actor: actor,
      action: 'agent.ticket.dispatch',
      phase: 'requested',
      workspaceId: workspace.id,
      targetType: 'github_issue',
      targetId: '${ticket.repository}#${ticket.issueNumber}',
      metadata: {
        'trigger': 'human_deploy',
        'projectId': queue.projectId,
        'projectItemId': ticket.itemId,
        'permissionProfile': ticket.permissionProfile,
        'permissionRef': ticket.permissionRef,
      },
    );
    var workflowDispatched = false;
    try {
      final codexState = await codexAuth.repositoryState(
        workspace.id,
        ticket.repository,
        repositoryId: ticket.repositoryId,
      );
      final currentTicket = await _readCurrentTicket(
        workspace,
        github,
        queue,
        ticket.itemId,
        repository: ticket.repository,
      );
      if (currentTicket == null || currentTicket.status != 'Todo') {
        throw const ApiError(
          409,
          'agent_ticket_changed_during_dispatch',
          'The approved ticket changed before dispatch. Review and deploy it again.',
        );
      }
      final dispatchedAt = DateTime.now().toUtc();
      await _journalDispatch(
        workspace,
        queue,
        currentTicket,
        dispatchId,
        dispatchedAt,
        approval.trustedSourceSha,
        approval.trustedSourceRef,
      );
      if (!await activations.confirmClaim(
        workspaceId: workspace.id,
        projectId: queue.projectId,
        ticket: currentTicket,
        approval: approval,
        claimId: dispatchId,
      )) {
        throw const ApiError(
          409,
          'agent_approval_unavailable',
          'The approved deployment changed before dispatch.',
        );
      }

      // GitHub returns no run id from workflow_dispatch. Journal the dispatch
      // first so a lost response can never authorize a duplicate click.
      workflowDispatched = true;
      await github.dispatchWorkflow(
        workspace,
        repository: currentTicket.repository,
        workflowPath: '.github/workflows/$iiOsAgentTaskWorkflow',
        ref: approval.trustedSourceRef,
        inputs: {
          'repository': currentTicket.repository,
          'issue_number': currentTicket.issueNumber.toString(),
          'permission_profile': currentTicket.permissionProfile,
          'permission_ref': currentTicket.permissionRef,
          'permission_digest': agentPermissionProfileDigest(approval.profile),
          'project_item_id': currentTicket.itemId,
          'dispatch_id': dispatchId,
          'workspace_id': workspace.id,
          'codex_secret_digest': codexState?['secretDigest'] as String? ?? '',
          'trusted_source_sha': approval.trustedSourceSha,
        },
      );
      await _bindDispatchedWorkflowRun(
        workspace: workspace,
        github: github,
        ticket: currentTicket,
        dispatchId: dispatchId,
        dispatchedAt: dispatchedAt,
        expectedSourceSha: approval.trustedSourceSha,
        expectedSourceRef: approval.trustedSourceRef,
      );
      await _dispatchRef(
        workspace.id,
        ticket.itemId,
      ).update({'status': 'workflow_bound', 'updatedAt': Timestamp.now()});
    } on Object catch (error) {
      await _recordDispatchFailure(
        workspace: workspace,
        queue: queue,
        ticket: ticket,
        dispatchId: dispatchId,
        workflowDispatched: workflowDispatched,
        error: error,
      );
      await audit.record(
        requestId: dispatchId,
        actor: actor,
        action: 'agent.ticket.dispatch',
        phase: 'failed',
        workspaceId: workspace.id,
        targetType: 'github_issue',
        targetId: '${ticket.repository}#${ticket.issueNumber}',
        metadata: {
          'trigger': 'human_deploy',
          'projectItemId': ticket.itemId,
          'errorType': error.runtimeType.toString(),
          'workflowDispatched': workflowDispatched,
        },
      );
      rethrow;
    }
    await audit.record(
      requestId: dispatchId,
      actor: actor,
      action: 'agent.ticket.dispatch',
      phase: 'completed',
      workspaceId: workspace.id,
      targetType: 'github_issue',
      targetId: '${ticket.repository}#${ticket.issueNumber}',
      metadata: {'trigger': 'human_deploy', 'projectItemId': ticket.itemId},
    );
  }

  Future<AgentQueueTicket?> _readCurrentTicket(
    Workspace workspace,
    GitHubClient github,
    AgentQueueProject queue,
    String itemId, {
    required String repository,
  }) async {
    final item = await github.readAgentQueueProjectItem(
      workspace,
      projectId: queue.projectId,
      itemId: itemId,
      repository: repository,
    );
    return AgentQueueTicket.parse(item, queue.statusFieldId);
  }

  Future<void> _journalDispatch(
    Workspace workspace,
    AgentQueueProject queue,
    AgentQueueTicket ticket,
    String dispatchId,
    DateTime dispatchedAt,
    String trustedSourceSha,
    String trustedSourceRef,
  ) => _dispatchRef(workspace.id, ticket.itemId).set({
    'workspaceId': workspace.id,
    'projectId': queue.projectId,
    'projectItemId': ticket.itemId,
    'repository': ticket.repository,
    'issueNumber': ticket.issueNumber,
    'requestId': dispatchId,
    'trigger': 'human_deploy',
    'trustedSourceSha': trustedSourceSha,
    'trustedSourceRef': trustedSourceRef,
    'status': 'workflow_dispatching',
    'dispatchedAt': Timestamp.fromDate(dispatchedAt),
    'expiresAt': Timestamp.fromDate(
      DateTime.now().toUtc().add(const Duration(days: 30)),
    ),
  });

  Future<void> _bindDispatchedWorkflowRun({
    required Workspace workspace,
    required GitHubClient github,
    required AgentQueueTicket ticket,
    required String dispatchId,
    required DateTime dispatchedAt,
    required String expectedSourceSha,
    required String expectedSourceRef,
  }) async {
    final expectedTitle =
        'ii-os agent / ${ticket.repository}#${ticket.issueNumber} / $dispatchId';
    final expectedActor = await github.agentBrokerBotLogin();
    for (var attempt = 0; attempt < 20; attempt++) {
      final runs = await github.listWorkflowRuns(
        workspace,
        repository: ticket.repository,
        workflowPath: '.github/workflows/$iiOsAgentTaskWorkflow',
      );
      final matches = matchingHumanDeploymentWorkflowRuns(
        runs,
        expectedTitle: expectedTitle,
        expectedActor: expectedActor,
        expectedSourceRef: expectedSourceRef,
        expectedSourceSha: expectedSourceSha,
        dispatchedAt: dispatchedAt,
      );
      if (matches.length > 1) throw _ambiguousAgentDispatchRun;
      if (matches.length == 1) {
        final run = matches.single;
        final runId = (run['id'] as num?)?.toInt() ?? 0;
        final runAttempt = (run['run_attempt'] as num?)?.toInt() ?? 0;
        final sha = run['head_sha'] as String? ?? '';
        final bound =
            runId > 0 &&
            runAttempt == 1 &&
            sha == expectedSourceSha &&
            await activations.bindWorkflowRun(
              workspaceId: workspace.id,
              projectItemId: ticket.itemId,
              claimId: dispatchId,
              repository: ticket.repository,
              repositoryId: ticket.repositoryId,
              issueNumber: ticket.issueNumber,
              runId: runId,
              runAttempt: runAttempt,
              workflowSha: sha,
              workflowRunUrl: run['html_url'] as String? ?? '',
            );
        if (!bound) throw _ambiguousAgentDispatchRun;
        await _dispatchRef(workspace.id, ticket.itemId).update({
          'workflowRunId': runId,
          'workflowRunAttempt': runAttempt,
          'workflowSha': sha,
          'workflowRunUrl': run['html_url'],
          'workflowBoundAt': Timestamp.now(),
          'updatedAt': Timestamp.now(),
        });
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw _ambiguousAgentDispatchRun;
  }

  Future<void> _recordDispatchFailure({
    required Workspace workspace,
    required AgentQueueProject queue,
    required AgentQueueTicket ticket,
    required String dispatchId,
    required bool workflowDispatched,
    required Object error,
  }) async {
    if (!workflowDispatched) {
      await activations.release(
        workspaceId: workspace.id,
        projectItemId: ticket.itemId,
        claimId: dispatchId,
      );
    }
    await _dispatchRef(workspace.id, ticket.itemId).set({
      'workspaceId': workspace.id,
      'projectId': queue.projectId,
      'projectItemId': ticket.itemId,
      'repository': ticket.repository,
      'issueNumber': ticket.issueNumber,
      'requestId': dispatchId,
      'trigger': 'human_deploy',
      'status': workflowDispatched ? 'workflow_unconfirmed' : 'dispatch_failed',
      'errorType': error.runtimeType.toString(),
      'updatedAt': Timestamp.now(),
    }, options: const SetOptions.merge());
  }

  DocumentReference<Map<String, Object?>> _dispatchRef(
    String workspaceId,
    String itemId,
  ) => store.firestore
      .collection('workspaces')
      .doc(workspaceId)
      .collection('agentDispatches')
      .doc(itemId);
}

List<Map<String, Object?>> matchingHumanDeploymentWorkflowRuns(
  Iterable<Map<String, Object?>> runs, {
  required String expectedTitle,
  required String expectedActor,
  required String expectedSourceRef,
  required String expectedSourceSha,
  required DateTime dispatchedAt,
}) => runs.where((run) {
  final actor = run['actor'];
  final actorLogin = actor is Map ? actor['login'] : null;
  final createdAt = DateTime.tryParse(
    run['created_at'] as String? ?? '',
  )?.toUtc();
  return run['display_title'] == expectedTitle &&
      run['event'] == 'workflow_dispatch' &&
      run['run_attempt'] == 1 &&
      actorLogin == expectedActor &&
      run['head_branch'] == expectedSourceRef &&
      run['head_sha'] == expectedSourceSha &&
      run['path'] == '.github/workflows/$iiOsAgentTaskWorkflow' &&
      createdAt != null &&
      !createdAt.isBefore(
        dispatchedAt.toUtc().subtract(const Duration(minutes: 1)),
      );
}).toList();

String humanAgentDispatchId(String requestId, String projectItemId) {
  final digest = sha256
      .convert(utf8.encode('$requestId:$projectItemId'))
      .toString()
      .substring(0, 32);
  return 'human:$digest:$projectItemId';
}

final class AgentQueueProject {
  const AgentQueueProject({
    required this.projectId,
    required this.statusFieldId,
    required this.inProgressOptionId,
  });

  final String projectId;
  final String statusFieldId;
  final String inProgressOptionId;
}

final class AgentQueueTicket {
  const AgentQueueTicket({
    required this.itemId,
    required this.issueNumber,
    required this.title,
    required this.repository,
    required this.repositoryId,
    required this.status,
    required this.permissionProfile,
    required this.permissionRef,
    required this.structured,
    required this.requirementsComplete,
    required this.content,
  });

  static AgentQueueTicket? parse(
    Map<String, Object?> item,
    String statusFieldId,
  ) {
    if (item['isArchived'] == true) return null;
    final content = item['content'];
    if (content is! Map<String, Object?> ||
        content['__typename'] != 'Issue' ||
        content['state'] != 'OPEN') {
      return null;
    }
    final repository = content['repository'];
    final nameWithOwner = repository is Map<String, Object?>
        ? repository['nameWithOwner'] as String? ?? ''
        : '';
    final repositoryId = repository is Map<String, Object?>
        ? (repository['databaseId'] as num?)?.toInt() ?? 0
        : 0;
    final issueNumber = (content['number'] as num?)?.toInt() ?? 0;
    final itemId = item['id'] as String? ?? '';
    if (nameWithOwner.isEmpty ||
        repositoryId <= 0 ||
        issueNumber <= 0 ||
        itemId.isEmpty) {
      return null;
    }
    var status = '';
    for (final value in _nodes(item['fieldValues'])) {
      final field = value['field'];
      if (field is Map<String, Object?> && field['id'] == statusFieldId) {
        status = value['name'] as String? ?? '';
      }
    }
    final ticket = TicketContent.parse(content['body']);
    return AgentQueueTicket(
      itemId: itemId,
      issueNumber: issueNumber,
      title: content['title'] as String? ?? '',
      repository: nameWithOwner,
      repositoryId: repositoryId,
      status: status,
      permissionProfile: ticket.permissionProfile,
      permissionRef: ticket.permissionRef,
      structured: ticket.structured,
      requirementsComplete:
          ticket.definitionOfDone.isNotEmpty && ticket.howToTest.isNotEmpty,
      content: ticket,
    );
  }

  final String itemId;
  final int issueNumber;
  final String title;
  final String repository;
  final int repositoryId;
  final String status;
  final String permissionProfile;
  final String permissionRef;
  final bool structured;
  final bool requirementsComplete;
  final TicketContent content;
}

List<Map<String, Object?>> _nodes(Object? connection) {
  if (connection is! Map<String, Object?>) return const [];
  final nodes = connection['nodes'];
  return nodes is List<Object?>
      ? nodes.whereType<Map<String, Object?>>().toList()
      : const [];
}

const _ambiguousAgentDispatchRun = ApiError(
  409,
  'agent_dispatch_run_ambiguous',
  'The exact workflow run for this deployment could not be bound.',
);
