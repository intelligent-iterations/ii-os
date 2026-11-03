import 'dart:convert';

import 'package:ii_interactive_sessions/ii_interactive_sessions.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 25, 12);
  final signer = SessionGrantSigner(utf8.encode('k' * 32));

  test('round trips an audience- and session-bound grant', () {
    final token = signer.mint(_claims(now));

    final claims = signer.verify(
      token,
      audience: 'ii-session-relay',
      sessionId: 'session-1',
      now: now,
    );

    expect(claims.subject, 'owner-1');
    expect(claims.capabilities, contains(SessionCapability.terminalWrite));
  });

  test('verifies the deterministic Fleet Go supervisor grant fixture', () {
    const token =
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IklJU0cifQ.eyJ2IjoxLCJhdWQiOiJpaS1zZXNzaW9uLXJlbGF5Iiwic2lkIjoic2Vzc2lvb'
        'i0xIiwib3JnIjoib3JnLTEiLCJ3b3Jrc3BhY2UiOiJ3b3Jrc3BhY2UtMSIsInN1YiI6InN1cGVydmlzb3I6bGVhc2UtMSIsInJvb'
        'GUiOiJzdXBlcnZpc29yIiwiY2FwYWJpbGl0aWVzIjpbInNlc3Npb24uam9pbiIsInN1cGVydmlzb3IiXSwiZ2VuZXJhdGlvbiI6M'
        'SwicG9saWN5UmV2aXNpb24iOjEsImp0aSI6ImNuSnljbkp5Y25KeWNuSnljbkp5Y25KeSIsImlhdCI6MTc4NzY1OTIwMCwiZXhwI'
        'joxNzg3NjU5ODAwLCJqb2IiOiJpaS1vczppbnRlcmFjdGl2ZTp3b3Jrc3BhY2UtMTpzZXNzaW9uLTEiLCJsZWFzZSI6ImxlYXNlL'
        'TEifQ.gnw0QBkClDzW2UP4IALpGvZXFWg-Y58fr3M-7VZqa-w';

    final claims = signer.verify(
      token,
      audience: 'ii-session-relay',
      sessionId: 'session-1',
      now: now,
    );

    expect(claims.subject, 'supervisor:lease-1');
    expect(claims.jobId, 'ii-os:interactive:workspace-1:session-1');
    expect(claims.leaseId, 'lease-1');
    expect(claims.capabilities, {
      SessionCapability.sessionJoin,
      SessionCapability.supervisor,
    });
  });

  test('refuses tampering, wrong audience, and expiry', () {
    final token = signer.mint(_claims(now));
    final parts = token.split('.');
    parts[2] = '${parts[2][0] == 'a' ? 'b' : 'a'}${parts[2].substring(1)}';
    final tampered = parts.join('.');

    expect(
      () => signer.verify(tampered, audience: 'ii-session-relay', now: now),
      throwsA(
        isA<SessionGrantException>().having(
          (error) => error.code,
          'code',
          'grant_signature_invalid',
        ),
      ),
    );
    expect(
      () => signer.verify(token, audience: 'another-relay', now: now),
      throwsA(isA<SessionGrantException>()),
    );
    expect(
      () => signer.verify(
        token,
        audience: 'ii-session-relay',
        now: now.add(const Duration(minutes: 6)),
      ),
      throwsA(
        isA<SessionGrantException>().having(
          (error) => error.code,
          'code',
          'grant_expired',
        ),
      ),
    );
  });
}

SessionGrantClaims _claims(DateTime now) => SessionGrantClaims(
  audience: 'ii-session-relay',
  sessionId: 'session-1',
  organizationId: 'org-1',
  workspaceId: 'workspace-1',
  subject: 'owner-1',
  role: ParticipantRole.owner,
  capabilities: const {
    SessionCapability.sessionJoin,
    SessionCapability.sessionManage,
    SessionCapability.terminalObserve,
    SessionCapability.terminalWrite,
  },
  generation: 1,
  policyRevision: 1,
  tokenId: 'token-1',
  issuedAt: now,
  expiresAt: now.add(const Duration(minutes: 5)),
);
