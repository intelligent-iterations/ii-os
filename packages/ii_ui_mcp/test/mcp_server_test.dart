import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ii_interactive_sessions/ii_interactive_sessions.dart';
import 'package:ii_ui_mcp/ii_ui_mcp.dart';
import 'package:test/test.dart';

void main() {
  test('presents observe, screenshot, and action over MCP', () async {
    final now = DateTime.utc(2026, 8, 25, 12);
    final signer = SessionGrantSigner(utf8.encode('m' * 32));
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
    await frontend.connect();
    final server = IiUiMcpServer(client: agent);
    await server.connect();
    addTearDown(frontend.dispose);
    addTearDown(server.dispose);
    var denyScreenshot = false;
    final frontendFrames = frontend.frames.listen((frame) async {
      if (frame.type == 'ui.action') {
        await frontend.sendFrame(
          SessionFrame(
            type: 'ui.action.result',
            id: frame.id,
            payload: {'status': 'applied', 'revision': 5},
          ),
        );
      } else if (frame.type == 'ui.screenshot.request') {
        if (denyScreenshot) {
          await frontend.sendFrame(
            SessionFrame(
              type: 'ui.action.result',
              id: frame.id,
              payload: const {'status': 'approval_denied', 'revision': 4},
            ),
          );
          return;
        }
        await frontend.publishScreenshot(
          UiScreenshot(
            revision: 4,
            mimeType: 'image/png',
            bytes: Uint8List.fromList(
              List<int>.generate(90000, (index) => index % 255),
            ),
            redacted: true,
          ),
        );
      }
    });
    addTearDown(frontendFrames.cancel);
    await Future<void>.delayed(const Duration(milliseconds: 1));
    await frontend.publishUiState(
      const UiSemanticSnapshot(
        revision: 4,
        route: '/workspaces/workspace-1/sessions/session-1',
        nodes: [
          UiSemanticNode(id: 'run-tests', role: 'button', label: 'Run tests'),
        ],
      ),
    );

    final initialized = await server.dispatch({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'initialize',
      'params': {'protocolVersion': '2025-06-18'},
    });
    expect(
      (initialized!['result']! as Map<String, Object?>)['protocolVersion'],
      '2025-06-18',
    );
    final tools = await server.dispatch({
      'jsonrpc': '2.0',
      'id': 2,
      'method': 'tools/list',
    });
    final listed =
        ((tools!['result']! as Map<String, Object?>)['tools']! as List<Object?>)
            .whereType<Map<String, Object?>>()
            .map((tool) => tool['name']);
    expect(
      listed,
      containsAll(['ii_ui_observe', 'ii_ui_screenshot', 'ii_ui_action']),
    );

    final observed = await _call(server, 3, 'ii_ui_observe', const {});
    expect(jsonEncode(observed), contains('run-tests'));
    final action = await _call(server, 4, 'ii_ui_action', const {
      'action': 'activate',
      'target': 'run-tests',
      'expectedRevision': 4,
    });
    expect(jsonEncode(action), contains('applied'));
    final screenshot = await _call(server, 5, 'ii_ui_screenshot', const {});
    final content = screenshot['content']! as List<Object?>;
    final image = content.whereType<Map<String, Object?>>().first;
    expect(image['type'], 'image');
    expect(base64Decode(image['data']! as String), hasLength(90000));

    denyScreenshot = true;
    final denied = await server.dispatch({
      'jsonrpc': '2.0',
      'id': 6,
      'method': 'tools/call',
      'params': {'name': 'ii_ui_screenshot', 'arguments': const {}},
    });
    expect(
      (denied!['error']! as Map<String, Object?>)['message'],
      'Screenshot request approval_denied',
    );

    await frontend.dispose();
    final unavailable = await server.dispatch({
      'jsonrpc': '2.0',
      'id': 7,
      'method': 'tools/call',
      'params': {'name': 'ii_ui_observe', 'arguments': const {}},
    });
    expect(
      (unavailable!['error']! as Map<String, Object?>)['message'],
      'Frontend surface is unavailable',
    );
  });
}

Future<Map<String, Object?>> _call(
  IiUiMcpServer server,
  int id,
  String name,
  Map<String, Object?> arguments,
) async {
  final response = await server.dispatch({
    'jsonrpc': '2.0',
    'id': id,
    'method': 'tools/call',
    'params': {'name': name, 'arguments': arguments},
  });
  expect(response, isNotNull);
  expect(response, isNot(contains('error')));
  return response!['result']! as Map<String, Object?>;
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
