import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_interactive_sessions/ii_interactive_sessions.dart';
import 'package:ii_interactive_sessions_flutter/ii_interactive_sessions_flutter.dart';

void main() {
  test(
    'serializes semantic actions, approvals, and screenshot chunks',
    () async {
      final now = DateTime.utc(2026, 8, 25, 12);
      final signer = SessionGrantSigner(utf8.encode('u' * 32));
      final relay = FakeSessionRelay(signer: signer, clock: () => now)
        ..register(_descriptor(now));
      final frontend = _client(
        relay,
        signer,
        now,
        subject: 'frontend',
        tokenId: 'frontend-token',
        role: ParticipantRole.frontend,
        capabilities: const {SessionCapability.frontend},
      );
      final agent = _client(
        relay,
        signer,
        now,
        subject: 'agent',
        tokenId: 'agent-token',
        role: ParticipantRole.agent,
        capabilities: const {
          SessionCapability.uiObserve,
          SessionCapability.uiAct,
        },
      );
      addTearDown(frontend.dispose);
      addTearDown(agent.dispose);
      await frontend.connect();
      await agent.connect();
      await Future<void>.delayed(const Duration(milliseconds: 1));
      var activations = 0;
      var allowScreenshot = true;
      final bridge = InteractiveUiBridgeController(
        client: frontend,
        route: () => '/workspaces/workspace-1/sessions/session-1',
        approveSensitiveAction: (_, _) async => false,
        captureScreenshot: (revision) async {
          if (!allowScreenshot) throw StateError('approval denied');
          return UiScreenshot(
            revision: revision,
            mimeType: 'image/png',
            bytes: Uint8List.fromList(
              List<int>.generate(100000, (index) => index % 255),
            ),
            redacted: true,
          );
        },
      );
      addTearDown(bridge.dispose);
      bridge.register(
        UiElementBinding(
          node: const UiSemanticNode(
            id: 'run-tests',
            role: 'button',
            label: 'Run tests',
          ),
          onAction: (_) => activations++,
        ),
      );
      bridge.register(
        UiElementBinding(
          node: const UiSemanticNode(
            id: 'deploy',
            role: 'button',
            label: 'Deploy',
            sensitive: true,
          ),
          onAction: (_) => throw StateError('approval should stop action'),
        ),
      );
      await bridge.enable();

      final applied = agent.frames.firstWhere(
        (frame) =>
            frame.type == 'ui.action.result' && frame.id == 'activate-tests',
      );
      await agent.sendFrame(
        SessionFrame(
          type: 'ui.action',
          id: 'activate-tests',
          payload: {
            'action': 'activate',
            'target': 'run-tests',
            'expectedRevision': bridge.revision,
          },
        ),
      );
      expect((await applied).payload['status'], 'applied');
      expect(activations, 1);

      final denied = agent.frames.firstWhere(
        (frame) => frame.type == 'ui.action.result' && frame.id == 'deploy-now',
      );
      await agent.sendFrame(
        SessionFrame(
          type: 'ui.action',
          id: 'deploy-now',
          payload: {
            'action': 'activate',
            'target': 'deploy',
            'expectedRevision': bridge.revision,
          },
        ),
      );
      expect((await denied).payload['status'], 'approval_denied');

      final chunks = <SessionFrame>[];
      final subscription = agent.frames
          .where((frame) => frame.type == 'ui.screenshot.chunk')
          .listen(chunks.add);
      addTearDown(subscription.cancel);
      await agent.requestScreenshot();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(chunks, hasLength(3));
      expect(chunks.first.payload['redacted'], isTrue);
      expect(chunks.map((item) => item.payload['index']), [0, 1, 2]);

      allowScreenshot = false;
      final screenshotDenied = agent.frames.firstWhere(
        (frame) =>
            frame.type == 'ui.action.result' && frame.id == 'screenshot-denied',
      );
      await agent.sendFrame(
        const SessionFrame(
          type: 'ui.screenshot.request',
          id: 'screenshot-denied',
          payload: {},
        ),
      );
      expect((await screenshotDenied).payload['status'], 'approval_denied');
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
      poolId: 'personal-owner',
      jobId: 'ii-session:session-1',
      image: 'terminal@sha256:${'a' * 64}',
      lifecycle: SessionLifecycle.joinable,
      policyRevision: 1,
      createdAt: now,
      expiresAt: now.add(const Duration(hours: 1)),
    );

InteractiveSessionClient _client(
  FakeSessionRelay relay,
  SessionGrantSigner signer,
  DateTime now, {
  required String subject,
  required String tokenId,
  required ParticipantRole role,
  required Set<SessionCapability> capabilities,
}) => InteractiveSessionClient(
  relayUri: Uri.parse('wss://relay.test/session-1'),
  grant: signer.mint(
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
  ),
  transport: relay,
);
