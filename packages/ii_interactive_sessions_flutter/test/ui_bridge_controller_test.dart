import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_interactive_sessions/ii_interactive_sessions.dart';
import 'package:ii_interactive_sessions_flutter/ii_interactive_sessions_flutter.dart';

void main() {
  for (final change in ['disable', 'dispose', 'unregister', 'reenable']) {
    test('pending action loses authority on $change', () async {
      final (frontend, agent) = await _connectedPair();
      final started = Completer<void>();
      final approval = Completer<bool>();
      var activations = 0;
      final bridge = InteractiveUiBridgeController(
        client: frontend,
        route: () => '/example',
        approveSensitiveAction: (_, _) {
          started.complete();
          return approval.future;
        },
      );
      if (change != 'dispose') addTearDown(bridge.dispose);
      bridge.register(
        UiElementBinding(
          node: const UiSemanticNode(
            id: 'sensitive',
            role: 'button',
            label: 'Apply',
            sensitive: true,
          ),
          onAction: (_) => activations++,
        ),
      );
      await bridge.enable();
      await agent.sendFrame(
        SessionFrame(
          type: 'ui.action',
          id: 'pending',
          payload: {
            'action': 'activate',
            'target': 'sensitive',
            'expectedRevision': bridge.revision,
          },
        ),
      );
      await started.future;
      switch (change) {
        case 'dispose':
          bridge.dispose();
        case 'unregister':
          bridge.unregister('sensitive');
        default:
          await bridge.disable();
          if (change == 'reenable') await bridge.enable();
      }
      approval.complete(true);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(activations, 0);
    });
  }

  for (final change in ['disable', 'dispose', 'reenable']) {
    test('pending screenshot loses authority on $change', () async {
      final (frontend, agent) = await _connectedPair();
      final started = Completer<int>();
      final capture = Completer<UiScreenshot>();
      final chunks = <SessionFrame>[];
      final subscription = agent.frames
          .where((frame) => frame.type == 'ui.screenshot.chunk')
          .listen(chunks.add);
      addTearDown(subscription.cancel);
      final bridge = InteractiveUiBridgeController(
        client: frontend,
        route: () => '/example',
        approveSensitiveAction: (_, _) async => false,
        captureScreenshot: (revision) {
          started.complete(revision);
          return capture.future;
        },
      );
      if (change != 'dispose') addTearDown(bridge.dispose);
      await bridge.enable();
      await agent.requestScreenshot();
      final revision = await started.future;
      if (change == 'dispose') {
        bridge.dispose();
      } else {
        await bridge.disable();
        if (change == 'reenable') await bridge.enable();
      }
      capture.complete(
        UiScreenshot(
          revision: revision,
          mimeType: 'image/png',
          bytes: Uint8List.fromList([1, 2, 3]),
          redacted: true,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(chunks, isEmpty);
    });
  }
  for (final change in ['disable', 'dispose', 'reenable']) {
    test('remaining screenshot chunks lose authority on $change', () async {
      final connection = _BlockingScreenshotConnection();
      final client = InteractiveSessionClient(
        relayUri: Uri.parse('wss://relay.example/session'),
        grant: 'synthetic-frontend-grant',
        transport: _BlockingScreenshotTransport(connection),
      );
      addTearDown(client.dispose);
      await client.connect();
      final bridge = InteractiveUiBridgeController(
        client: client,
        route: () => '/example',
        approveSensitiveAction: (_, _) async => false,
        captureScreenshot: (revision) async => UiScreenshot(
          revision: revision,
          mimeType: 'image/png',
          bytes: Uint8List(100000),
          redacted: true,
        ),
      );
      if (change != 'dispose') addTearDown(bridge.dispose);
      await bridge.enable();
      connection.inbound.add(
        const SessionFrame(
          type: 'ui.screenshot.request',
          id: 'chunked-capture',
          payload: {},
        ),
      );
      await connection.firstChunkStarted.future;
      if (change == 'dispose') {
        bridge.dispose();
      } else {
        await bridge.disable();
        if (change == 'reenable') await bridge.enable();
      }
      connection.releaseFirstChunk.complete();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      // Bytes already handed to the transport cannot be retracted. Later
      // chunks must not be sent under a revoked sharing revision.
      expect(connection.chunks, hasLength(1));
    });
  }

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

Future<(InteractiveSessionClient, InteractiveSessionClient)>
_connectedPair() async {
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
    capabilities: const {SessionCapability.uiObserve, SessionCapability.uiAct},
  );
  addTearDown(frontend.dispose);
  addTearDown(agent.dispose);
  await frontend.connect();
  await agent.connect();
  await Future<void>.delayed(const Duration(milliseconds: 1));
  return (frontend, agent);
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

final class _BlockingScreenshotTransport implements SessionTransport {
  const _BlockingScreenshotTransport(this.connection);
  final SessionConnection connection;
  @override
  Future<SessionConnection> connect({
    required Uri relayUri,
    required String grant,
    required int acknowledgedSequence,
  }) async => connection;
}

final class _BlockingScreenshotConnection implements SessionConnection {
  final inbound = StreamController<SessionFrame>.broadcast();
  final firstChunkStarted = Completer<void>();
  final releaseFirstChunk = Completer<void>();
  final chunks = <SessionFrame>[];
  @override
  Stream<SessionFrame> get frames => inbound.stream;
  @override
  Future<void> send(SessionFrame frame) async {
    if (frame.type != 'ui.screenshot.chunk') return;
    chunks.add(frame);
    if (chunks.length == 1) {
      firstChunkStarted.complete();
      await releaseFirstChunk.future;
    }
  }

  @override
  Future<void> close() async => inbound.close();
}
