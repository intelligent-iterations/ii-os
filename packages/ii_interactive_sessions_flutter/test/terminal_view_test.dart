import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_interactive_sessions/ii_interactive_sessions.dart';
import 'package:ii_interactive_sessions_flutter/ii_interactive_sessions_flutter.dart';

void main() {
  testWidgets('renders presence and enforces input ownership', (tester) async {
    final now = DateTime.utc(2026, 8, 25, 12);
    final signer = SessionGrantSigner(utf8.encode('f' * 32));
    final relay = FakeSessionRelay(signer: signer, clock: () => now)
      ..register(
        InteractiveSessionDescriptor(
          id: 'session-1',
          organizationId: 'org-1',
          workspaceId: 'workspace-1',
          ownerSubject: 'owner',
          runnerResourceId: 'runner-1',
          poolId: 'personal-owner',
          jobId: 'ii-session:session-1',
          image: 'terminal@sha256:${'a' * 64}',
          lifecycle: SessionLifecycle.joinable,
          policyRevision: 1,
          createdAt: now,
          expiresAt: now.add(const Duration(hours: 1)),
        ),
      );
    final ownerClient = _client(
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
    final supervisor = await relay.connect(
      relayUri: Uri.parse('wss://relay.test/sessions/session-1'),
      grant: _grant(
        signer,
        now,
        subject: 'supervisor',
        role: ParticipantRole.supervisor,
        tokenId: 'supervisor-token',
        capabilities: const {SessionCapability.supervisor},
      ),
      acknowledgedSequence: 0,
    );
    final collaborator = await relay.connect(
      relayUri: Uri.parse('wss://relay.test/sessions/session-1'),
      grant: _grant(
        signer,
        now,
        subject: 'collaborator',
        role: ParticipantRole.collaborator,
        tokenId: 'collaborator-token',
        capabilities: const {
          SessionCapability.terminalObserve,
          SessionCapability.terminalWrite,
        },
      ),
      acknowledgedSequence: 0,
    );
    final controller = InteractiveTerminalController(
      client: ownerClient,
      subject: 'owner',
      canManageSession: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: InteractiveTerminalView(controller: controller)),
      ),
    );
    await controller.connect();
    await tester.pump(const Duration(milliseconds: 1));

    expect(
      controller.participants.map((item) => item.subject),
      contains('owner'),
    );
    expect(find.text('owner'), findsWidgets);
    expect(find.text('supervisor'), findsWidgets);
    expect(controller.canWrite, isTrue);
    expect(find.text('Request input'), findsNothing);

    await supervisor.send(
      SessionFrame(
        type: 'terminal.output',
        id: 'output-1',
        payload: terminalBytes(
          Uint8List.fromList(utf8.encode(r'$ npm --version\r\n10.8.2\r\n')),
        ),
      ),
    );
    await tester.pump();
    expect(controller.client.acknowledgedSequence, 1);

    await collaborator.send(
      const SessionFrame(
        type: 'terminal.input.request',
        id: 'request-input-1',
        payload: {},
      ),
    );
    await tester.pump();
    expect(controller.inputRequester, 'collaborator');
    expect(find.byTooltip('Grant requested input'), findsOneWidget);
    await tester.tap(find.byTooltip('Grant requested input'));
    await tester.pump();
    expect(controller.canWrite, isFalse);
    expect(find.text('Take input'), findsOneWidget);
    await tester.tap(find.text('Take input'));
    await tester.pump();
    expect(controller.canWrite, isTrue);

    relay.end('session-1', reason: 'test_complete');
    relay.discard('session-1');
    controller.dispose();
  });
}

InteractiveSessionClient _client(
  FakeSessionRelay relay,
  SessionGrantSigner signer,
  DateTime now, {
  required String subject,
  required ParticipantRole role,
  required String tokenId,
  required Set<SessionCapability> capabilities,
}) => InteractiveSessionClient(
  relayUri: Uri.parse('wss://relay.test/sessions/session-1'),
  grant: _grant(
    signer,
    now,
    subject: subject,
    role: role,
    tokenId: tokenId,
    capabilities: {SessionCapability.sessionJoin, ...capabilities},
  ),
  transport: relay,
);

String _grant(
  SessionGrantSigner signer,
  DateTime now, {
  required String subject,
  required ParticipantRole role,
  required String tokenId,
  required Set<SessionCapability> capabilities,
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
  ),
);
