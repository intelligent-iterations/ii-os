import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ii_interactive_sessions/ii_interactive_sessions.dart';
import 'package:ii_ui_mcp/ii_ui_mcp.dart';
import 'package:test/test.dart';

void main() {
  test('local broker carries MCP without exposing its relay grant', () async {
    final now = DateTime.utc(2026, 8, 25, 12);
    final signer = SessionGrantSigner(utf8.encode('b' * 32));
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
        subject: 'agent:codex',
        role: ParticipantRole.agent,
        capabilities: const {
          SessionCapability.sessionJoin,
          SessionCapability.uiObserve,
        },
        generation: 1,
        policyRevision: 1,
        tokenId: 'broker-token',
        issuedAt: now,
        expiresAt: now.add(const Duration(minutes: 5)),
      ),
    );
    final directory = await Directory.systemTemp.createTemp('ii-ui-broker-');
    addTearDown(() => directory.delete(recursive: true));
    final socketPath = '${directory.path}/mcp.sock';
    final stop = Completer<void>();
    final broker = serveIiUiMcpBroker(
      socketPath: socketPath,
      server: IiUiMcpServer(
        client: InteractiveSessionClient(
          relayUri: Uri.parse('wss://relay.test/session-1'),
          grant: grant,
          transport: relay,
        ),
      ),
      shutdown: stop.future,
    );
    await _waitForSocket(socketPath);
    final peer = await Socket.connect(
      InternetAddress(socketPath, type: InternetAddressType.unix),
      0,
    );
    final response = peer
        .map<List<int>>((bytes) => bytes)
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first;
    peer.writeln(jsonEncode({'jsonrpc': '2.0', 'id': 1, 'method': 'ping'}));
    expect(jsonDecode(await response), {
      'jsonrpc': '2.0',
      'id': 1,
      'result': <String, Object?>{},
    });
    expect(
      File(socketPath).readAsString(),
      throwsA(isA<FileSystemException>()),
    );
    peer.destroy();
    stop.complete();
    await broker;
    relay.discard('session-1');
  });
}

Future<void> _waitForSocket(String path) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (await FileSystemEntity.type(path, followLinks: false) ==
        FileSystemEntityType.unixDomainSock) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw TimeoutException('local broker socket was not created');
}
