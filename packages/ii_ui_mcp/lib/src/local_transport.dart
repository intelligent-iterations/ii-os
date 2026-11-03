import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'mcp_server.dart';

const _maxMcpLineBytes = 1024 * 1024;

/// Runs the trusted relay client behind a local Unix socket. The relay grant
/// remains only in this broker process; untrusted shell children receive no
/// bearer value, URL credential, environment secret, or credential file.
Future<void> serveIiUiMcpBroker({
  required String socketPath,
  required IiUiMcpServer server,
  Future<void>? shutdown,
}) async {
  _validateSocketPath(socketPath);
  final existing = await FileSystemEntity.type(socketPath, followLinks: false);
  if (existing == FileSystemEntityType.unixDomainSock) {
    await File(socketPath).delete();
  } else if (existing != FileSystemEntityType.notFound) {
    throw StateError('The local MCP socket destination is unsafe.');
  }
  await server.connect();
  final listener = await ServerSocket.bind(
    InternetAddress(socketPath, type: InternetAddressType.unix),
    0,
    shared: false,
  );
  if (shutdown != null) {
    unawaited(shutdown.whenComplete(listener.close));
  }
  try {
    await for (final peer in listener) {
      unawaited(_servePeer(peer, server));
    }
  } finally {
    await listener.close();
    await server.dispose();
    if (await FileSystemEntity.type(socketPath, followLinks: false) ==
        FileSystemEntityType.unixDomainSock) {
      await File(socketPath).delete();
    }
  }
}

/// Stdio proxy launched by Codex. It carries MCP JSON-RPC only and never sees
/// the relay grant held by the root-owned broker.
Future<void> proxyIiUiMcp(String socketPath) async {
  _validateSocketPath(socketPath);
  final peer = await Socket.connect(
    InternetAddress(socketPath, type: InternetAddressType.unix),
    0,
  ).timeout(const Duration(seconds: 10));
  final input = stdin.listen(
    peer.add,
    onError: peer.addError,
    onDone: peer.close,
    cancelOnError: true,
  );
  try {
    await stdout.addStream(peer);
  } finally {
    await input.cancel();
    peer.destroy();
  }
}

Future<void> _servePeer(Socket peer, IiUiMcpServer server) async {
  try {
    await for (final line
        in peer
            .map<List<int>>((bytes) => bytes)
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      if (line.trim().isEmpty || utf8.encode(line).length > _maxMcpLineBytes) {
        continue;
      }
      Object? decoded;
      try {
        decoded = jsonDecode(line);
      } on FormatException {
        peer.writeln(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': null,
            'error': {'code': -32700, 'message': 'Parse error'},
          }),
        );
        continue;
      }
      if (decoded is! Map) continue;
      final response = await server.dispatch(decoded.cast<String, Object?>());
      if (response != null) peer.writeln(jsonEncode(response));
    }
  } on Object {
    // A malformed or abruptly closed local peer does not terminate the
    // session-scoped broker or its relay authority.
  } finally {
    await peer.close();
  }
}

void _validateSocketPath(String value) {
  if (!value.startsWith('/') ||
      value.length > 200 ||
      value.contains(RegExp(r'[\u0000\r\n]'))) {
    throw ArgumentError.value(value, 'socketPath', 'must be an absolute path');
  }
}
