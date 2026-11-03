import 'dart:convert';

import 'package:google_cloud_firestore/google_cloud_firestore.dart';
import 'package:ii_os_functions/src/agent_activation_store.dart';
import 'package:ii_os_functions/src/agent_permission_profile.dart';
import 'package:ii_os_functions/src/agent_ticket_dispatcher.dart';
import 'package:ii_os_functions/src/github_actions_oidc.dart';
import 'package:ii_os_functions/src/ticket_content.dart';
import 'package:test/test.dart';

void main() {
  test('activation digests bind the exact ticket and profile version', () {
    const ticket = TicketContent(
      definitionOfDone: 'Ship the reviewed change.',
      howToTest: 'Run the live test.',
      permissionProfile: 'repository-maintainer',
      permissionRef: 'dev',
      context: '',
      structured: true,
      agentReady: true,
    );
    final profile = AgentPermissionProfile.parse(_profile);
    final changed = AgentPermissionProfile.parse({
      ..._profile,
      'version': '2026-07-27.2',
    });

    expect(
      ticketBodyDigest(ticket),
      isNot(ticketBodyDigest(ticket.withAgentReady(false))),
    );
    expect(
      agentPermissionProfileDigest(profile),
      isNot(agentPermissionProfileDigest(changed)),
    );
    expect(
      agentPermissionProfileDigest(profile),
      '836ffaf9a89eb1109a194ef83af6b7716185beb61be6f37d1d7143b3827c909b',
      reason: 'must match Python canonical_profile_digest',
    );
  });

  test('the receipt snapshot preserves what the run was permitted', () {
    final profile = AgentPermissionProfile.parse(_profile);
    final snapshot = boundedAgentPermissionSnapshot(profile);

    // Lossless on purpose. "What could this agent touch on that run" is not a
    // question a summary can answer once the branch has moved on.
    expect(snapshot, profile.toJson());
    expect(snapshot['allowed_actions'], profile.allowedActions);
    expect(snapshot['denied_actions'], profile.deniedActions);
  });

  test('the snapshot is canonically ordered, so it reads like the digest', () {
    final profile = AgentPermissionProfile.parse(_profile);
    final snapshot = boundedAgentPermissionSnapshot(profile);

    expect(snapshot.keys.toList(), snapshot.keys.toList()..sort());
  });

  test('the snapshot records no secret value, only its name', () {
    final profile = AgentPermissionProfile.parse(_profile);
    final snapshot = boundedAgentPermissionSnapshot(profile);
    final injection = snapshot['secret_injection']! as Map<String, Object?>;
    final bindings = injection['bindings']! as List<Object?>;

    for (final binding in bindings.cast<Map<String, Object?>>()) {
      expect(binding.keys, isNot(contains('value')));
      expect(binding['github_secret'], isA<String>());
    }
  });

  test('the snapshot stays well inside its receipt budget', () {
    final profile = AgentPermissionProfile.parse(_profile);
    final size = utf8
        .encode(jsonEncode(boundedAgentPermissionSnapshot(profile)))
        .length;

    expect(size, lessThan(agentPermissionSnapshotMaxBytes));
  });

  test('a moving dev branch cannot invalidate the frozen approval', () {
    final claim = approvedAgentActivationClaim(
      _activationReceipt,
      projectId: 'project-1',
      ticket: _queueTicket,
    );

    expect(claim, isNotNull);
    expect(claim!.trustedSourceSha, _approvedSourceSha);
    expect(claim.trustedSourceRef, 'ii-os-agent-v4-$_approvedSourceSha');
    expect(claim.profile.id, 'repository-maintainer');
    expect(agentPermissionProfileDigest(claim.profile), _profileDigest);
  });

  test('a changed ticket cannot reuse an earlier approval', () {
    final claim = approvedAgentActivationClaim(
      _activationReceipt,
      projectId: 'project-1',
      ticket: AgentQueueTicket(
        itemId: _queueTicket.itemId,
        issueNumber: _queueTicket.issueNumber,
        title: 'A changed title',
        repository: _queueTicket.repository,
        repositoryId: _queueTicket.repositoryId,
        status: _queueTicket.status,
        permissionProfile: _queueTicket.permissionProfile,
        permissionRef: _queueTicket.permissionRef,
        structured: _queueTicket.structured,
        requirementsComplete: _queueTicket.requirementsComplete,
        content: _queueTicket.content,
      ),
    );

    expect(claim, isNull);
  });

  test('workflow consume keeps the ticket Todo until Fleet is running', () {
    final prematurelyRunning = _ticketAtStatus('In Progress');

    expect(
      dispatchedAgentActivationTicketMatches(
        _activationReceipt,
        projectId: 'project-1',
        ticket: _queueTicket,
      ),
      isTrue,
    );
    expect(
      dispatchedAgentActivationTicketMatches(
        _activationReceipt,
        projectId: 'project-1',
        ticket: prematurelyRunning,
      ),
      isFalse,
      reason: 'dispatch and coordinator startup are not running-work proof',
    );
    expect(
      dispatchedAgentActivationTicketMatches(
        _activationReceipt,
        projectId: 'project-1',
        ticket: AgentQueueTicket(
          itemId: _queueTicket.itemId,
          issueNumber: _queueTicket.issueNumber,
          title: 'Edited after dispatch',
          repository: _queueTicket.repository,
          repositoryId: _queueTicket.repositoryId,
          status: _queueTicket.status,
          permissionProfile: _queueTicket.permissionProfile,
          permissionRef: _queueTicket.permissionRef,
          structured: _queueTicket.structured,
          requirementsComplete: _queueTicket.requirementsComplete,
          content: _queueTicket.content,
        ),
      ),
      isFalse,
      reason: 'the expected status transition must not weaken content binding',
    );
  });

  test('an unconsumed approval accepts only a newer same-run attempt', () {
    final receipt = <String, Object?>{
      'workflowRunId': 9001,
      'workflowRunAttempt': 1,
      'workflowSha': _approvedSourceSha,
    };
    final firstAttempt = _workflowPrincipal(runId: 9001, runAttempt: 1);
    final retry = _workflowPrincipal(runId: 9001, runAttempt: 2);

    expect(
      agentActivationWorkflowRunMatches(
        receipt,
        firstAttempt,
        allowNewerAttempt: false,
      ),
      isTrue,
    );
    expect(
      agentActivationWorkflowRunMatches(
        receipt,
        retry,
        allowNewerAttempt: true,
      ),
      isTrue,
      reason: 'GitHub reruns keep the run id and advance run_attempt',
    );
    expect(
      agentActivationWorkflowRunMatches(
        receipt,
        retry,
        allowNewerAttempt: false,
      ),
      isFalse,
      reason: 'a consumed receipt remains bound to its final exact attempt',
    );
    expect(
      agentActivationWorkflowRunMatches(
        receipt,
        _workflowPrincipal(runId: 9002, runAttempt: 2),
        allowNewerAttempt: true,
      ),
      isFalse,
    );
    expect(
      agentActivationWorkflowRunMatches(
        receipt,
        _workflowPrincipal(
          runId: 9001,
          runAttempt: 2,
          sha: '2222222222222222222222222222222222222222',
        ),
        allowNewerAttempt: true,
      ),
      isFalse,
    );
  });

  test('the exact workflow can repair a lost API-side run binding', () {
    final now = DateTime.utc(2026, 8, 23, 21, 30);
    final receipt = <String, Object?>{
      'status': 'claiming',
      'repository': _queueTicket.repository,
      'repositoryId': _queueTicket.repositoryId,
      'trustedSourceSha': _approvedSourceSha,
      'trustedSourceRef': 'ii-os-agent-v4-$_approvedSourceSha',
      'claimConfirmedAt': Timestamp.fromDate(
        now.subtract(const Duration(seconds: 10)),
      ),
      'claimExpiresAt': Timestamp.fromDate(now.add(const Duration(hours: 2))),
    };
    final principal = _workflowPrincipal(runId: 9001, runAttempt: 1);

    expect(agentActivationWorkflowMaySelfBind(receipt, principal, now), isTrue);
    receipt['workflowRunId'] = 9002;
    expect(
      agentActivationWorkflowMaySelfBind(receipt, principal, now),
      isFalse,
      reason: 'an existing run identity can never be replaced',
    );
  });

  test('Fleet lifecycle states are monotonic and name real proof layers', () {
    expect(
      agentFleetDispatchStatusTransition('workflow_bound', 'submitting'),
      'fleet_submitting',
    );
    expect(
      agentFleetDispatchStatusTransition('fleet_submitting', 'submitting'),
      'fleet_submitting',
      reason: 'a retried pre-submit callback is idempotent',
    );
    expect(
      agentFleetDispatchStatusTransition('fleet_submitting', 'queued'),
      'fleet_queued',
    );
    expect(
      agentFleetDispatchStatusTransition(
        'fleet_submitting',
        'submission_failed',
      ),
      'fleet_submission_failed',
    );
    expect(
      agentFleetDispatchStatusTransition('fleet_queued', 'running'),
      'fleet_running',
    );
    expect(
      agentFleetDispatchStatusTransition('fleet_running', 'cleaning'),
      'fleet_cleaning',
    );
    expect(
      agentFleetDispatchStatusTransition('fleet_cleaning', 'cleaned'),
      'fleet_cleaned',
    );
    expect(
      agentFleetDispatchStatusTransition('workflow_bound', 'running'),
      isNull,
      reason: 'a running claim cannot skip Fleet job submission proof',
    );
    expect(
      agentFleetDispatchStatusTransition('fleet_cleaned', 'running'),
      isNull,
      reason: 'terminal cleanup cannot move backwards',
    );
  });

  test(
    'runtime execution keeps the claim and reset lock until cleanup is resolved',
    () {
      final now = DateTime.utc(2026, 10, 28);
      final activation = <String, Object?>{'status': 'consumed'};
      for (final status in const [
        'execution_accepted',
        'execution_waiting_for_capacity',
        'execution_starting',
        'execution_running',
        'execution_unknown',
        'execution_failed',
        'execution_cancelled',
        'execution_cleaning',
        'execution_cleaned',
      ]) {
        final dispatch = <String, Object?>{
          'status': status,
          'executionId': 'github:1:2:work-ticket',
          'updatedAt': Timestamp.fromDate(
            now.subtract(const Duration(days: 2)),
          ),
        };
        expect(
          agentPickupInFlight(activation, dispatch, now),
          isTrue,
          reason: status,
        );
        expect(
          agentTicketResetAllowed(activation, dispatch, now),
          isFalse,
          reason: status,
        );
        expect(
          agentDispatchWorkflowStalled(dispatch, activation, now),
          isFalse,
        );
      }
    },
  );

  test('terminal failed dispatch releases a legacy live-looking claim', () {
    final now = DateTime.utc(2026, 8, 16, 23);
    final activation = <String, Object?>{
      'status': 'claiming',
      'claimId': 'old-claim',
      'claimExpiresAt': Timestamp.fromDate(now.add(const Duration(hours: 2))),
    };

    for (final status in const [
      'approval_required',
      'retry_failed',
      'workflow_stalled',
      'fleet_submission_failed',
    ]) {
      expect(
        agentPickupInFlight(activation, {'status': status}, now),
        isFalse,
        reason: '$status is terminal and must allow a fresh human review',
      );
    }
  });

  test('active dispatch keeps a live activation claim locked', () {
    final now = DateTime.utc(2026, 8, 16, 23);
    final activation = <String, Object?>{
      'status': 'claiming',
      'claimId': 'current-claim',
      'claimExpiresAt': Timestamp.fromDate(now.add(const Duration(hours: 2))),
    };

    for (final status in const [
      'dispatching',
      'dispatched',
      'dispatched_unconfirmed',
      'workflow_dispatching',
      'workflow_bound',
      'workflow_unconfirmed',
      'fleet_submitting',
      'fleet_queued',
      'fleet_running',
      'fleet_cleaning',
      'fleet_cleaned',
    ]) {
      expect(
        agentPickupInFlight(activation, {'status': status}, now),
        isTrue,
        reason: '$status must remain protected from a concurrent edit',
      );
    }
  });

  test('abandoned Fleet phases release only after their safety deadline', () {
    final now = DateTime.utc(2026, 8, 16, 23);
    final activation = <String, Object?>{
      'status': 'consumed',
      'claimId': 'old-claim',
    };
    final staleLifecycleAt = Timestamp.fromDate(
      now.subtract(agentFleetLifecycleRecoveryTimeout),
    );
    for (final status in const [
      'fleet_submitting',
      'fleet_queued',
      'fleet_running',
      'fleet_cleaning',
    ]) {
      final dispatch = <String, Object?>{
        'status': status,
        'workflowRunId': 9001,
        'workflowRunAttempt': 1,
        'workflowSha': _approvedSourceSha,
        'fleetJobId': 'github:123:9001:1:work-ticket',
        'updatedAt': staleLifecycleAt,
      };
      expect(agentPickupInFlight(activation, dispatch, now), isFalse);
      expect(
        agentDispatchRecoveryStatus(dispatch, activation, now),
        status == 'fleet_submitting'
            ? 'fleet_submission_stalled'
            : 'fleet_lifecycle_stalled',
      );
    }

    final cleaned = <String, Object?>{
      'status': 'fleet_cleaned',
      'workflowRunId': 9001,
      'workflowRunAttempt': 1,
      'workflowSha': _approvedSourceSha,
      'fleetJobId': 'github:123:9001:1:work-ticket',
      'updatedAt': Timestamp.fromDate(
        now.subtract(agentFleetFinalizationRecoveryTimeout),
      ),
    };
    expect(agentPickupInFlight(activation, cleaned, now), isFalse);
    expect(
      agentDispatchRecoveryStatus(cleaned, activation, now),
      'fleet_finalization_stalled',
    );
  });
}

const _approvedSourceSha = '1111111111111111111111111111111111111111';
final _parsedProfile = AgentPermissionProfile.parse(_profile);
final _profileDigest = agentPermissionProfileDigest(_parsedProfile);
const _ticketContent = TicketContent(
  definitionOfDone: 'Ship the reviewed change.',
  howToTest: 'Run the live test.',
  permissionProfile: 'repository-maintainer',
  permissionRef: 'dev',
  context: '',
  structured: true,
  agentReady: false,
);
const _queueTicket = AgentQueueTicket(
  itemId: 'item-1',
  issueNumber: 42,
  title: 'Exact approved ticket',
  repository: 'acme-co/example-app',
  repositoryId: 123,
  status: 'Todo',
  permissionProfile: 'repository-maintainer',
  permissionRef: 'dev',
  structured: true,
  requirementsComplete: true,
  content: _ticketContent,
);

AgentQueueTicket _ticketAtStatus(String status) => AgentQueueTicket(
  itemId: _queueTicket.itemId,
  issueNumber: _queueTicket.issueNumber,
  title: _queueTicket.title,
  repository: _queueTicket.repository,
  repositoryId: _queueTicket.repositoryId,
  status: status,
  permissionProfile: _queueTicket.permissionProfile,
  permissionRef: _queueTicket.permissionRef,
  structured: _queueTicket.structured,
  requirementsComplete: _queueTicket.requirementsComplete,
  content: _queueTicket.content,
);

GitHubActionsPrincipal _workflowPrincipal({
  required int runId,
  required int runAttempt,
  String sha = _approvedSourceSha,
}) => GitHubActionsPrincipal(
  repository: _queueTicket.repository,
  repositoryId: _queueTicket.repositoryId,
  runId: runId,
  runAttempt: runAttempt,
  sha: sha,
  ref: 'refs/tags/ii-os-agent-v4-$sha',
  workflowRef: '',
  jobWorkflowRef: '',
  actor: 'ii-bot',
  subject: '',
  environment: 'ii-os-agent-maintainer',
);

final _activationReceipt = <String, Object?>{
  'projectId': 'project-1',
  'projectItemId': _queueTicket.itemId,
  'repositoryId': _queueTicket.repositoryId,
  'repository': _queueTicket.repository,
  'issueNumber': _queueTicket.issueNumber,
  'ticketTitle': _queueTicket.title,
  'ticketBodyDigest': ticketBodyDigest(_ticketContent),
  'permissionProfile': _parsedProfile.id,
  'permissionVersion': _parsedProfile.version,
  'permissionDigest': _profileDigest,
  'permissionRef': 'dev',
  'permissionProfileSnapshot': boundedAgentPermissionSnapshot(_parsedProfile),
  'workflowFile': 'ii-os-agent-task.yml',
  'trustedSourceSha': _approvedSourceSha,
  'trustedSourceRef': 'ii-os-agent-v4-$_approvedSourceSha',
};

const _profile = <String, Object?>{
  'schema_version': 1,
  'id': 'repository-maintainer',
  'version': '2026-07-27.1',
  'display_name': 'Repository maintainer',
  'description': 'Maintains one repository.',
  'allowed_actions': ['Edit code'],
  'denied_actions': ['Create tickets'],
  'fleet': {
    'profile': 'ii-os-agent',
    'image':
        'coder@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    'runtime_kind': 'docker',
    'resources': {'ram_mb': 4096, 'cpu': 2, 'disk_gb': 40, 'timeout_s': 3600},
    'capabilities': [
      'runtime-docker',
      'auto-agent',
      'github-app-token',
      'codex-oauth',
      'codex-sandbox',
      'agent-usage-reporting',
      'linux-amd64',
    ],
  },
  'secret_injection': {
    'environment': 'ii-os-agent-maintainer',
    'bindings': [
      {
        'id': 'github-app-token',
        'capability': 'github-app-token',
        'github_secret': 'IIAUTO_GITHUB_TOKEN',
        'target': 'file',
        'target_name': 'GITHUB_TOKEN_FILE',
      },
      {
        'id': 'codex-auth',
        'capability': 'codex-oauth',
        'github_secret': 'CODEX_AUTH_JSON',
        'target': 'file',
        'target_name': 'CODEX_AUTH_JSON_FILE',
      },
      {
        'id': 'agent-usage',
        'capability': 'agent-usage-reporting',
        'github_secret': 'II_OS_AGENT_USAGE_API_KEY',
        'target': 'file',
        'target_name': 'AGENT_USAGE_KEY_FILE',
      },
    ],
  },
  'workflow': {'file': 'ii-os-agent-task.yml', 'ref': 'dev'},
};
