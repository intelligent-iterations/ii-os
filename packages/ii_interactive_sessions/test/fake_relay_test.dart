import 'dart:convert';
import 'dart:typed_data';

import 'package:ii_interactive_sessions/ii_interactive_sessions.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 25, 12);
  late SessionGrantSigner signer;
  late FakeSessionRelay relay;

  setUp(() {
    signer = SessionGrantSigner(utf8.encode('r' * 32));
    relay = FakeSessionRelay(signer: signer, clock: () => now);
    relay.register(
      InteractiveSessionDescriptor(
        id: 'session-1',
        organizationId: 'org-1',
        workspaceId: 'workspace-1',
        ownerSubject: 'owner',
        runnerResourceId: 'runner-personal',
        poolId: 'personal-alice',
        jobId: 'ii-session:session-1',
        image: 'terminal@sha256:${'a' * 64}',
        lifecycle: SessionLifecycle.joinable,
        policyRevision: 1,
        createdAt: now,
        expiresAt: now.add(const Duration(hours: 1)),
      ),
    );
  });

  test('many observers receive output while only the holder writes', () async {
    final owner = await _connect(
      relay,
      signer,
      now,
      subject: 'owner',
      role: ParticipantRole.owner,
      tokenId: 'owner-token',
      capabilities: const {
        SessionCapability.sessionManage,
        SessionCapability.terminalObserve,
        SessionCapability.terminalWrite,
      },
    );
    final collaborator = await _connect(
      relay,
      signer,
      now,
      subject: 'collaborator',
      role: ParticipantRole.collaborator,
      tokenId: 'collaborator-token',
      capabilities: const {
        SessionCapability.terminalObserve,
        SessionCapability.terminalWrite,
      },
    );
    final supervisor = await _connect(
      relay,
      signer,
      now,
      subject: 'supervisor',
      role: ParticipantRole.supervisor,
      tokenId: 'supervisor-token',
      capabilities: const {SessionCapability.supervisor},
    );
    final ownerFrames = <SessionFrame>[];
    final collaboratorFrames = <SessionFrame>[];
    owner.frames.listen(ownerFrames.add);
    collaborator.frames.listen(collaboratorFrames.add);

    await supervisor.send(
      SessionFrame(
        type: 'terminal.output',
        id: 'output-1',
        payload: terminalBytes(
          Uint8List.fromList(utf8.encode(r'$ npm test\r\n')),
        ),
      ),
    );
    expect(
      ownerFrames
          .where((frame) => frame.type == 'terminal.output')
          .single
          .sequence,
      1,
    );
    expect(
      collaboratorFrames.where((frame) => frame.type == 'terminal.output'),
      hasLength(1),
    );

    await expectLater(
      collaborator.send(
        SessionFrame(
          type: 'terminal.input',
          id: 'input-denied',
          payload: {
            ...terminalBytes(Uint8List.fromList([65])),
            'leaseRevision': 1,
          },
        ),
      ),
      throwsA(_protocolCode('input_lease_stale')),
    );
    await owner.send(
      const SessionFrame(
        type: 'terminal.input.grant',
        id: 'handoff-1',
        payload: {'subject': 'collaborator', 'expectedRevision': 1},
      ),
    );
    await collaborator.send(
      SessionFrame(
        type: 'terminal.input',
        id: 'input-accepted',
        payload: {
          ...terminalBytes(Uint8List.fromList([65])),
          'leaseRevision': 2,
        },
      ),
    );
  });

  test('grants are one-use and revocation closes existing authority', () async {
    final token = _token(
      signer,
      now,
      subject: 'viewer',
      role: ParticipantRole.viewer,
      tokenId: 'viewer-token',
      capabilities: const {SessionCapability.terminalObserve},
    );
    final connection = await relay.connect(
      relayUri: Uri.parse('wss://relay.test/sessions/session-1'),
      grant: token,
      acknowledgedSequence: 0,
    );
    await expectLater(
      relay.connect(
        relayUri: Uri.parse('wss://relay.test/sessions/session-1'),
        grant: token,
        acknowledgedSequence: 0,
      ),
      throwsA(_protocolCode('grant_replayed')),
    );
    final error = expectLater(
      connection.frames,
      emitsError(_protocolCode('participant_revoked')),
    );
    relay.rotateSubject('session-1', 'viewer', 2);
    await error;
  });

  test('ending a session notifies and closes every live connection', () async {
    final owner = await _connect(
      relay,
      signer,
      now,
      subject: 'owner',
      role: ParticipantRole.owner,
      tokenId: 'owner-token',
      capabilities: const {
        SessionCapability.sessionManage,
        SessionCapability.terminalObserve,
      },
    );
    final ending = owner.frames.firstWhere(
      (frame) => frame.type == 'session.end',
    );

    relay.end('session-1', reason: 'test_complete');

    expect((await ending).payload['reason'], 'test_complete');
    await expectLater(
      owner.send(
        const SessionFrame(type: 'ui.observe', id: 'late', payload: {}),
      ),
      throwsA(_protocolCode('connection_closed')),
    );
    await expectLater(
      _connect(
        relay,
        signer,
        now,
        subject: 'late-viewer',
        role: ParticipantRole.viewer,
        tokenId: 'late-token',
        capabilities: const {SessionCapability.terminalObserve},
      ),
      throwsA(_protocolCode('session_ended')),
    );
  });

  test('descriptor expiry ends an already attached connection', () async {
    final liveNow = DateTime.now().toUtc();
    final liveSigner = SessionGrantSigner(utf8.encode('e' * 32));
    final expiring = FakeSessionRelay(signer: liveSigner)
      ..register(
        InteractiveSessionDescriptor(
          id: 'expiring-session',
          organizationId: 'org-1',
          workspaceId: 'workspace-1',
          ownerSubject: 'owner',
          runnerResourceId: 'runner-personal',
          poolId: 'personal-alice',
          jobId: 'ii-session:expiring-session',
          image: 'terminal@sha256:${'a' * 64}',
          lifecycle: SessionLifecycle.joinable,
          policyRevision: 1,
          createdAt: liveNow,
          expiresAt: liveNow.add(const Duration(seconds: 2)),
        ),
      );
    final connection = await expiring.connect(
      relayUri: Uri.parse('wss://relay.test/sessions/expiring-session'),
      grant: liveSigner.mint(
        SessionGrantClaims(
          audience: 'ii-session-relay',
          sessionId: 'expiring-session',
          organizationId: 'org-1',
          workspaceId: 'workspace-1',
          subject: 'owner',
          role: ParticipantRole.owner,
          capabilities: const {
            SessionCapability.sessionJoin,
            SessionCapability.sessionManage,
          },
          generation: 1,
          policyRevision: 1,
          tokenId: 'expiring-token',
          issuedAt: liveNow,
          expiresAt: liveNow.add(const Duration(seconds: 2)),
        ),
      ),
      acknowledgedSequence: 0,
    );
    final ending = connection.frames.firstWhere(
      (frame) => frame.type == 'session.end',
    );

    expect(
      (await ending.timeout(const Duration(seconds: 3))).payload['reason'],
      'expired',
    );
    await Future<void>.delayed(Duration.zero);
    await expectLater(
      connection.send(
        const SessionFrame(type: 'session.stop', id: 'late', payload: {}),
      ),
      throwsA(_protocolCode('connection_closed')),
    );
  });

  test('agent grant installation requires a connected supervisor', () async {
    final owner = await _connect(
      relay,
      signer,
      now,
      subject: 'owner',
      role: ParticipantRole.owner,
      tokenId: 'owner-token',
      capabilities: const {SessionCapability.sessionManage},
    );
    final agentGrant = _token(
      signer,
      now,
      subject: 'agent:codex',
      role: ParticipantRole.agent,
      tokenId: 'agent-token',
      capabilities: const {
        SessionCapability.sessionJoin,
        SessionCapability.uiObserve,
      },
    );
    final install = SessionFrame(
      type: 'agent.grant.install',
      id: 'install-agent',
      payload: {'grant': agentGrant},
    );
    await expectLater(
      owner.send(install),
      throwsA(_protocolCode('supervisor_unavailable')),
    );

    final supervisor = await _connect(
      relay,
      signer,
      now,
      subject: 'supervisor',
      role: ParticipantRole.supervisor,
      tokenId: 'supervisor-token',
      capabilities: const {SessionCapability.supervisor},
    );
    final received = supervisor.frames.firstWhere(
      (frame) => frame.type == 'agent.grant.install',
    );
    await owner.send(
      SessionFrame(
        type: install.type,
        id: 'install-agent-retry',
        payload: install.payload,
      ),
    );
    expect((await received).payload['grant'], agentGrant);
  });

  test('Fleet supervisor grants use a separate bounded trust key', () async {
    final supervisorSigner = SessionGrantSigner(utf8.encode('s' * 32));
    relay =
        FakeSessionRelay(
          signer: signer,
          supervisorSigner: supervisorSigner,
          clock: () => now,
        )..register(
          InteractiveSessionDescriptor(
            id: 'session-1',
            organizationId: 'org-1',
            workspaceId: 'workspace-1',
            ownerSubject: 'owner',
            runnerResourceId: 'runner-personal',
            poolId: 'personal-alice',
            jobId: 'ii-session:session-1',
            image: 'terminal@sha256:${'a' * 64}',
            lifecycle: SessionLifecycle.starting,
            policyRevision: 1,
            createdAt: now,
            expiresAt: now.add(const Duration(hours: 1)),
          ),
        );
    relay.update(
      InteractiveSessionDescriptor(
        id: 'session-1',
        organizationId: 'org-1',
        workspaceId: 'workspace-1',
        ownerSubject: 'owner',
        runnerResourceId: 'runner-personal',
        poolId: 'personal-alice',
        jobId: 'ii-session:session-1',
        image: 'terminal@sha256:${'a' * 64}',
        lifecycle: SessionLifecycle.starting,
        policyRevision: 2,
        createdAt: now,
        expiresAt: now.add(const Duration(hours: 1)),
      ),
    );
    final valid = _token(
      supervisorSigner,
      now,
      subject: 'supervisor:lease-1',
      role: ParticipantRole.supervisor,
      tokenId: 'fleet-supervisor-token',
      capabilities: const {
        SessionCapability.sessionJoin,
        SessionCapability.supervisor,
      },
      jobId: 'ii-session:session-1',
      leaseId: 'lease-1',
    );
    final connection = await relay.connect(
      relayUri: Uri.parse('wss://relay.test/sessions/session-1'),
      grant: valid,
      acknowledgedSequence: 0,
    );
    await connection.close();

    final overpowered = _token(
      supervisorSigner,
      now,
      subject: 'supervisor:lease-2',
      role: ParticipantRole.supervisor,
      tokenId: 'fleet-overpowered-token',
      capabilities: const {
        SessionCapability.sessionJoin,
        SessionCapability.supervisor,
        SessionCapability.uiAct,
      },
      jobId: 'ii-session:session-1',
      leaseId: 'lease-2',
    );
    await expectLater(
      relay.connect(
        relayUri: Uri.parse('wss://relay.test/sessions/session-1'),
        grant: overpowered,
        acknowledgedSequence: 0,
      ),
      throwsA(_protocolCode('supervisor_grant_scope_invalid')),
    );
  });

  test('UI observe and action are separate and revision bound', () async {
    final frontend = await _connect(
      relay,
      signer,
      now,
      subject: 'frontend',
      role: ParticipantRole.frontend,
      tokenId: 'frontend-token',
      capabilities: const {SessionCapability.frontend},
    );
    final observer = await _connect(
      relay,
      signer,
      now,
      subject: 'agent-observe',
      role: ParticipantRole.agent,
      tokenId: 'observe-token',
      capabilities: const {SessionCapability.uiObserve},
    );
    final actor = await _connect(
      relay,
      signer,
      now,
      subject: 'agent-act',
      role: ParticipantRole.agent,
      tokenId: 'act-token',
      capabilities: const {
        SessionCapability.uiObserve,
        SessionCapability.uiAct,
      },
    );
    final observed = <SessionFrame>[];
    observer.frames.listen(observed.add);

    await frontend.send(
      const SessionFrame(
        type: 'ui.state',
        id: 'state-1',
        payload: {
          'revision': 4,
          'route': '/workspace/session-1',
          'nodes': [
            {'id': 'run-tests', 'role': 'button', 'label': 'Run tests'},
          ],
        },
      ),
    );
    expect(observed.where((frame) => frame.type == 'ui.state'), hasLength(1));
    await expectLater(
      observer.send(
        const SessionFrame(
          type: 'ui.action',
          id: 'observe-cannot-act',
          payload: {
            'action': 'activate',
            'target': 'run-tests',
            'expectedRevision': 4,
          },
        ),
      ),
      throwsA(_protocolCode('capability_denied')),
    );
    await expectLater(
      actor.send(
        const SessionFrame(
          type: 'ui.action',
          id: 'stale-action',
          payload: {
            'action': 'activate',
            'target': 'run-tests',
            'expectedRevision': 3,
          },
        ),
      ),
      throwsA(_protocolCode('ui_revision_stale')),
    );
    await actor.send(
      const SessionFrame(
        type: 'ui.action',
        id: 'valid-action',
        payload: {
          'action': 'activate',
          'target': 'run-tests',
          'expectedRevision': 4,
        },
      ),
    );
  });

  test('relay enforces the aggregate screenshot byte ceiling', () async {
    final frontend = await _connect(
      relay,
      signer,
      now,
      subject: 'frontend',
      role: ParticipantRole.frontend,
      tokenId: 'frontend-token',
      capabilities: const {SessionCapability.frontend},
    );
    await frontend.send(
      const SessionFrame(
        type: 'ui.state',
        id: 'state-1',
        payload: {'revision': 1, 'route': '/session-1', 'nodes': <Object?>[]},
      ),
    );
    final chunk = Uint8List(44 * 1024);
    for (var index = 0; index < 23; index++) {
      await frontend.send(
        SessionFrame(
          type: 'ui.screenshot.chunk',
          id: 'screenshot-$index',
          payload: {
            'screenshotId': 'screenshot-1',
            'revision': 1,
            'mimeType': 'image/png',
            'redacted': false,
            'index': index,
            'count': 25,
            ...terminalBytes(chunk),
          },
        ),
      );
    }
    await expectLater(
      frontend.send(
        SessionFrame(
          type: 'ui.screenshot.chunk',
          id: 'screenshot-23',
          payload: {
            'screenshotId': 'screenshot-1',
            'revision': 1,
            'mimeType': 'image/png',
            'redacted': false,
            'index': 23,
            'count': 25,
            ...terminalBytes(chunk),
          },
        ),
      ),
      throwsA(_protocolCode('ui_screenshot_too_large')),
    );
  });
}

Future<SessionConnection> _connect(
  FakeSessionRelay relay,
  SessionGrantSigner signer,
  DateTime now, {
  required String subject,
  required ParticipantRole role,
  required String tokenId,
  required Set<SessionCapability> capabilities,
}) => relay.connect(
  relayUri: Uri.parse('wss://relay.test/sessions/session-1'),
  grant: _token(
    signer,
    now,
    subject: subject,
    role: role,
    tokenId: tokenId,
    capabilities: {SessionCapability.sessionJoin, ...capabilities},
  ),
  acknowledgedSequence: 0,
);

String _token(
  SessionGrantSigner signer,
  DateTime now, {
  required String subject,
  required ParticipantRole role,
  required String tokenId,
  required Set<SessionCapability> capabilities,
  String jobId = '',
  String leaseId = '',
}) => signer.mint(
  SessionGrantClaims(
    audience: 'ii-session-relay',
    sessionId: 'session-1',
    organizationId: 'org-1',
    workspaceId: 'workspace-1',
    subject: subject,
    role: role,
    capabilities: {SessionCapability.sessionJoin, ...capabilities},
    generation: 1,
    policyRevision: 1,
    tokenId: tokenId,
    issuedAt: now,
    expiresAt: now.add(const Duration(minutes: 5)),
    jobId: jobId,
    leaseId: leaseId,
  ),
);

Matcher _protocolCode(String code) =>
    isA<SessionProtocolException>().having((error) => error.code, 'code', code);
