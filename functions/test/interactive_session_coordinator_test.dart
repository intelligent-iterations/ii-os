import 'package:ii_interactive_sessions/ii_interactive_sessions.dart';
import 'package:ii_os_functions/src/auth_service.dart';
import 'package:ii_os_functions/src/domain.dart';
import 'package:ii_os_functions/src/interactive_session.dart';
import 'package:ii_os_functions/src/interactive_session_coordinator.dart';
import 'package:ii_os_functions/src/interactive_session_workspace_access.dart';
import 'package:ii_os_functions/src/organization_resources.dart';
import 'package:ii_os_functions/src/session_relay_control.dart';
import 'package:ii_os_functions/src/workspace_resource_grants.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 25, 12);
  late SessionGrantSigner signer;
  late InMemorySessionRelay relayEngine;
  late _Relay relayControl;
  late _MemorySessions sessions;
  late InteractiveSessionCoordinator coordinator;
  late AuthenticatedUser owner;

  setUp(() {
    signer = SessionGrantSigner(List<int>.generate(32, (index) => index));
    relayEngine = InMemorySessionRelay(signer: signer, clock: () => now);
    relayControl = _Relay(relayEngine);
    sessions = _MemorySessions();
    owner = const AuthenticatedUser(
      uid: 'owner-1',
      email: 'owner@example.test',
      emailVerified: true,
      displayName: 'Owner',
      isOwner: false,
    );
    coordinator = InteractiveSessionCoordinator(
      workspaces: _WorkspaceAccess(_workspace(), {
        'owner-1': _membership('owner-1', WorkspaceRole.owner),
        'member-2': _membership('member-2', WorkspaceRole.editor),
      }),
      sessions: sessions,
      relay: relayControl,
      signer: signer,
      image:
          'registry.example/session@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      clock: () => now,
    );
  });

  test(
    'creates an exact-pool session without persisting a relay grant',
    () async {
      final result = await coordinator.create(
        actor: owner,
        workspaceId: 'workspace-1',
      );
      final session = (result['session']! as Map).cast<String, Object?>();
      final attach = (result['attach']! as Map).cast<String, Object?>();

      expect(session['poolId'], 'personal-owner');
      expect(session['runnerResourceId'], 'runner-personal');
      expect(attach['grant'], isA<String>());
      expect(sessions.fleetRequest['pool'], 'personal-owner');
      expect(
        sessions.fleetRequest.toString(),
        isNot(contains(attach['grant'])),
      );
      expect(
        sessions.record!.toJson().toString(),
        isNot(contains(attach['grant'])),
      );
      expect(relayControl.readySessionIds, [session['id']]);

      final claims = signer.verify(
        attach['grant']! as String,
        audience: 'ii-session-relay',
        now: now,
      );
      expect(claims.role, ParticipantRole.owner);
      expect(claims.capabilities, contains(SessionCapability.terminalWrite));
    },
  );

  test(
    'invites a member and mints a one-use role-bounded attach grant',
    () async {
      final created = await coordinator.create(
        actor: owner,
        workspaceId: 'workspace-1',
      );
      final id = ((created['session']! as Map)['id'])! as String;
      await coordinator.putParticipant(
        actor: owner,
        workspaceId: 'workspace-1',
        sessionId: id,
        subject: 'member-2',
        role: ParticipantRole.viewer,
      );
      final attach = await coordinator.attach(
        actor: const AuthenticatedUser(
          uid: 'member-2',
          email: 'member@example.test',
          emailVerified: true,
          displayName: 'Member',
          isOwner: false,
        ),
        workspaceId: 'workspace-1',
        sessionId: id,
      );
      final claims = signer.verify(
        attach['grant']! as String,
        audience: 'ii-session-relay',
        now: now,
        sessionId: id,
      );
      expect(claims.capabilities, contains(SessionCapability.terminalObserve));
      expect(
        claims.capabilities,
        isNot(contains(SessionCapability.terminalWrite)),
      );

      await relayEngine.connect(
        relayUri: Uri.parse(attach['relayUri']! as String),
        grant: attach['grant']! as String,
        acknowledgedSequence: 0,
      );
      await expectLater(
        relayEngine.connect(
          relayUri: Uri.parse(attach['relayUri']! as String),
          grant: attach['grant']! as String,
          acknowledgedSequence: 0,
        ),
        throwsA(
          isA<SessionProtocolException>().having(
            (error) => error.code,
            'code',
            'grant_replayed',
          ),
        ),
      );
    },
  );

  test(
    'separates frontend publishing from revocable agent UI access',
    () async {
      final created = await coordinator.create(
        actor: owner,
        workspaceId: 'workspace-1',
      );
      final id = ((created['session']! as Map)['id'])! as String;
      await coordinator.putParticipant(
        actor: owner,
        workspaceId: 'workspace-1',
        sessionId: id,
        subject: 'agent:codex',
        role: ParticipantRole.agent,
      );
      final grants = await coordinator.issueUiAccess(
        actor: owner,
        workspaceId: 'workspace-1',
        sessionId: id,
        agentSubject: 'agent:codex',
        allowAct: false,
      );
      final agent = signer.verify(
        grants['agentGrant']! as String,
        audience: 'ii-session-relay',
        now: now,
      );
      final frontend = signer.verify(
        grants['frontendGrant']! as String,
        audience: 'ii-session-relay',
        now: now,
      );
      expect(agent.capabilities, contains(SessionCapability.uiObserve));
      expect(agent.capabilities, isNot(contains(SessionCapability.uiAct)));
      expect(frontend.capabilities, {
        SessionCapability.sessionJoin,
        SessionCapability.frontend,
      });
    },
  );

  test(
    'role changes close stale live authority and rotate attach grants',
    () async {
      final created = await coordinator.create(
        actor: owner,
        workspaceId: 'workspace-1',
      );
      final id = ((created['session']! as Map)['id'])! as String;
      await coordinator.putParticipant(
        actor: owner,
        workspaceId: 'workspace-1',
        sessionId: id,
        subject: 'member-2',
        role: ParticipantRole.viewer,
      );
      final member = const AuthenticatedUser(
        uid: 'member-2',
        email: 'member@example.test',
        emailVerified: true,
        displayName: 'Member',
        isOwner: false,
      );
      final first = await coordinator.attach(
        actor: member,
        workspaceId: 'workspace-1',
        sessionId: id,
      );
      final stale = await relayEngine.connect(
        relayUri: Uri.parse(first['relayUri']! as String),
        grant: first['grant']! as String,
        acknowledgedSequence: 0,
      );
      final revoked = expectLater(
        stale.frames,
        emitsError(
          isA<SessionProtocolException>().having(
            (error) => error.code,
            'code',
            'participant_revoked',
          ),
        ),
      );

      await coordinator.putParticipant(
        actor: owner,
        workspaceId: 'workspace-1',
        sessionId: id,
        subject: 'member-2',
        role: ParticipantRole.collaborator,
      );
      await revoked;
      final second = await coordinator.attach(
        actor: member,
        workspaceId: 'workspace-1',
        sessionId: id,
      );
      final claims = signer.verify(
        second['grant']! as String,
        audience: 'ii-session-relay',
        now: now,
      );
      expect(claims.generation, 2);
      expect(claims.capabilities, contains(SessionCapability.terminalWrite));
    },
  );
}

final class _WorkspaceAccess implements InteractiveSessionWorkspaceAccess {
  const _WorkspaceAccess(this.workspace, this.memberships);

  final Workspace workspace;
  final Map<String, Membership> memberships;

  @override
  Future<Membership?> membership(String workspaceId, String subject) async =>
      memberships[subject];

  @override
  Future<({Membership membership, Workspace workspace})> require(
    AuthenticatedUser actor,
    String workspaceId,
    Capability capability,
  ) async {
    final membership = memberships[actor.uid];
    if (membership == null || !membership.allows(capability)) {
      throw StateError('forbidden');
    }
    return (membership: membership, workspace: workspace);
  }
}

final class _MemorySessions implements InteractiveSessionRepository {
  InteractiveSessionRecord? record;
  Map<String, Object?> fleetRequest = const {};

  @override
  Future<void> create({
    required InteractiveSessionRecord session,
    required Map<String, Object?> fleetRequest,
    required int maxConcurrent,
  }) async {
    record = session;
    this.fleetRequest = fleetRequest;
  }

  @override
  Future<InteractiveSessionRecord> get(
    String workspaceId,
    String sessionId,
  ) async => record!;

  @override
  Future<List<InteractiveSessionRecord>> list(String workspaceId) async => [
    record!,
  ];

  @override
  Future<InteractiveSessionRecord> putParticipant({
    required String workspaceId,
    required String sessionId,
    required InteractiveSessionParticipant participant,
  }) async {
    final current = record!;
    final existing = current.participant(participant.subject);
    final next = InteractiveSessionParticipant(
      subject: participant.subject,
      role: participant.role,
      generation: existing == null
          ? participant.generation
          : existing.generation + 1,
    );
    record = _copy(current, [
      ...current.participants.where(
        (item) => item.subject != participant.subject,
      ),
      next,
    ]);
    return record!;
  }

  @override
  Future<InteractiveSessionRecord> revokeParticipant({
    required String workspaceId,
    required String sessionId,
    required String subject,
  }) async {
    final current = record!;
    record = _copy(current, [
      for (final participant in current.participants)
        if (participant.subject == subject)
          InteractiveSessionParticipant(
            subject: participant.subject,
            role: participant.role,
            generation: participant.generation + 1,
            revoked: true,
          )
        else
          participant,
    ]);
    return record!;
  }

  @override
  Future<InteractiveSessionRecord> stop({
    required String workspaceId,
    required String sessionId,
    required DateTime now,
  }) async => record!;
}

final class _Relay implements SessionRelayControl {
  _Relay(this.relay);

  final InMemorySessionRelay relay;
  final List<String> readySessionIds = [];

  @override
  Uri connectUri(String sessionId) =>
      Uri.parse('wss://relay.example/v1/connect/$sessionId');

  @override
  Future<void> register(InteractiveSessionDescriptor descriptor) async =>
      relay.register(descriptor);

  @override
  Future<void> ready(String sessionId) async => readySessionIds.add(sessionId);

  @override
  Future<void> discard(String sessionId) async => relay.discard(sessionId);

  @override
  Future<void> update(InteractiveSessionDescriptor descriptor) async =>
      relay.update(descriptor);

  @override
  Future<void> rotateParticipant(
    String sessionId,
    String subject,
    int generation,
  ) async => relay.rotateSubject(sessionId, subject, generation);

  @override
  Future<void> end(String sessionId) async => relay.end(sessionId);
}

Workspace _workspace() {
  const runner = OrganizationRunnerPool(
    id: 'runner-personal',
    name: 'Personal host',
    provider: 'fleet',
    providerPoolId: 'personal-owner',
    capabilities: {'runtime-docker', 'interactive-pty'},
    maxCpu: 8,
    maxRamMiB: 16384,
    maxConcurrent: 2,
  );
  return const Workspace(
    id: 'workspace-1',
    name: 'Workspace',
    organizationId: 'organization-1',
    environment: 'dev',
    githubInstallationId: null,
    repositories: [],
    projects: [],
    workflows: [],
    artifactStorage: null,
    organizationResources: OrganizationResourceCatalog(
      gcpResources: [],
      githubResources: [],
      runnerPools: [runner],
    ),
    resourceGrants: WorkspaceResourceGrants(
      gcp: [],
      github: [],
      runners: [
        WorkspaceRunnerGrant(
          resourceId: 'runner-personal',
          capabilities: {'runtime-docker', 'interactive-pty'},
          maxCpu: 4,
          maxRamMiB: 8192,
          maxConcurrent: 1,
          primary: true,
        ),
      ],
    ),
    resourceGrantsExplicit: true,
  );
}

Membership _membership(String uid, WorkspaceRole role) => Membership(
  workspaceId: 'workspace-1',
  uid: uid,
  email: '$uid@example.test',
  role: role,
  featureClaims: roleCapabilityCeilings[role]!
      .map((item) => item.value)
      .toSet(),
);

InteractiveSessionRecord _copy(
  InteractiveSessionRecord current,
  List<InteractiveSessionParticipant> participants,
) => InteractiveSessionRecord(
  descriptor: InteractiveSessionDescriptor(
    id: current.descriptor.id,
    organizationId: current.descriptor.organizationId,
    workspaceId: current.descriptor.workspaceId,
    ownerSubject: current.descriptor.ownerSubject,
    runnerResourceId: current.descriptor.runnerResourceId,
    poolId: current.descriptor.poolId,
    jobId: current.descriptor.jobId,
    image: current.descriptor.image,
    lifecycle: current.descriptor.lifecycle,
    policyRevision: current.descriptor.policyRevision + 1,
    createdAt: current.descriptor.createdAt,
    expiresAt: current.descriptor.expiresAt,
  ),
  relayUri: current.relayUri,
  participants: participants,
);
