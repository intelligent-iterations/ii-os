import 'dart:convert';

import 'package:ii_interactive_sessions/ii_interactive_sessions.dart';
import 'package:test/test.dart';

void main() {
  test('attach requires explicit session.join authority', () async {
    final now = DateTime.utc(2026, 8, 25, 12);
    final signer = SessionGrantSigner(utf8.encode('j' * 32));
    final relay = FakeSessionRelay(signer: signer, clock: () => now)
      ..register(
        InteractiveSessionDescriptor(
          id: 'session-1',
          organizationId: 'org-1',
          workspaceId: 'workspace-1',
          ownerSubject: 'owner',
          runnerResourceId: 'runner-1',
          poolId: 'pool-1',
          jobId: 'job-1',
          image: 'terminal@sha256:${'a' * 64}',
          lifecycle: SessionLifecycle.joinable,
          policyRevision: 1,
          createdAt: now,
          expiresAt: now.add(const Duration(hours: 1)),
        ),
      );
    final grant = signer.mint(
      SessionGrantClaims(
        audience: 'ii-session-relay',
        sessionId: 'session-1',
        organizationId: 'org-1',
        workspaceId: 'workspace-1',
        subject: 'viewer',
        role: ParticipantRole.viewer,
        capabilities: const {SessionCapability.terminalObserve},
        generation: 1,
        policyRevision: 1,
        tokenId: 'missing-join',
        issuedAt: now,
        expiresAt: now.add(const Duration(minutes: 5)),
      ),
    );

    await expectLater(
      relay.connect(
        relayUri: Uri.parse('wss://relay.test/session-1'),
        grant: grant,
        acknowledgedSequence: 0,
      ),
      throwsA(
        isA<SessionProtocolException>().having(
          (error) => error.code,
          'code',
          'session_join_denied',
        ),
      ),
    );
  });

  test(
    'generation rotation closes stale authority and permits the next grant',
    () async {
      final now = DateTime.utc(2026, 8, 25, 12);
      final signer = SessionGrantSigner(utf8.encode('r' * 32));
      final relay = FakeSessionRelay(signer: signer, clock: () => now)
        ..register(_descriptor(now));
      final stale = await relay.connect(
        relayUri: Uri.parse('wss://relay.test/session-1'),
        grant: _grant(signer, now, generation: 1, tokenId: 'generation-1'),
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

      relay.rotateSubject('session-1', 'viewer', 2);
      await revoked;
      final current = await relay.connect(
        relayUri: Uri.parse('wss://relay.test/session-1'),
        grant: _grant(signer, now, generation: 2, tokenId: 'generation-2'),
        acknowledgedSequence: 0,
      );
      relay.rotateSubject('session-1', 'viewer', 2);
      await current.close();
    },
  );
}

InteractiveSessionDescriptor _descriptor(DateTime now) =>
    InteractiveSessionDescriptor(
      id: 'session-1',
      organizationId: 'org-1',
      workspaceId: 'workspace-1',
      ownerSubject: 'owner',
      runnerResourceId: 'runner-1',
      poolId: 'pool-1',
      jobId: 'job-1',
      image: 'terminal@sha256:${'a' * 64}',
      lifecycle: SessionLifecycle.joinable,
      policyRevision: 1,
      createdAt: now,
      expiresAt: now.add(const Duration(hours: 1)),
    );

String _grant(
  SessionGrantSigner signer,
  DateTime now, {
  required int generation,
  required String tokenId,
}) => signer.mint(
  SessionGrantClaims(
    audience: 'ii-session-relay',
    sessionId: 'session-1',
    organizationId: 'org-1',
    workspaceId: 'workspace-1',
    subject: 'viewer',
    role: ParticipantRole.viewer,
    capabilities: const {
      SessionCapability.sessionJoin,
      SessionCapability.terminalObserve,
    },
    generation: generation,
    policyRevision: 1,
    tokenId: tokenId,
    issuedAt: now,
    expiresAt: now.add(const Duration(minutes: 5)),
  ),
);
