import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ii_interactive_sessions/ii_interactive_sessions.dart';
import 'package:ii_ui_mcp/ii_ui_mcp.dart';

Future<void> main(List<String> arguments) async {
  final socketPath = _value(
    arguments,
    '--socket',
    Platform.environment['II_UI_MCP_SOCKET'],
  );
  if (!arguments.contains('--broker')) {
    await proxyIiUiMcp(socketPath);
    return;
  }
  final relay = Uri.parse(
    _value(arguments, '--relay', Platform.environment['II_UI_MCP_RELAY_URL']),
  );
  if (relay.scheme != 'wss' &&
      !(relay.scheme == 'ws' &&
          const {'localhost', '127.0.0.1'}.contains(relay.host))) {
    throw ArgumentError('--relay must be WSS, except for a loopback test');
  }
  final grant = await stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .first
      .timeout(const Duration(seconds: 5));
  if (grant.length < 64 ||
      grant.length > 8192 ||
      grant.split('.').length != 3 ||
      grant.contains(RegExp(r'\s'))) {
    throw StateError('The session grant pipe was invalid.');
  }
  await serveIiUiMcpBroker(
    socketPath: socketPath,
    server: IiUiMcpServer(
      client: InteractiveSessionClient(
        relayUri: relay,
        grant: grant,
        transport: const WebSocketSessionTransport(),
      ),
    ),
  );
}

String _value(List<String> arguments, String name, String? inherited) {
  final index = arguments.indexOf(name);
  final value = index >= 0 && index + 1 < arguments.length
      ? arguments[index + 1].trim()
      : inherited?.trim() ?? '';
  if (value.isEmpty || value.length > 1024) {
    throw ArgumentError('$name is required');
  }
  return value;
}
