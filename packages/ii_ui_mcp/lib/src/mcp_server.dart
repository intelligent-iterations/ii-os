import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ii_interactive_sessions/ii_interactive_sessions.dart';

final class IiUiMcpServer {
  IiUiMcpServer({
    required this.client,
    this.operationTimeout = const Duration(seconds: 15),
  });

  final InteractiveSessionClient client;
  final Duration operationTimeout;
  StreamSubscription<SessionFrame>? _frames;
  final _actionResults = StreamController<SessionFrame>.broadcast(sync: true);
  final _screenshotChunks = StreamController<SessionFrame>.broadcast(
    sync: true,
  );
  final _uiResponses = StreamController<SessionFrame>.broadcast(sync: true);
  int _nextActionId = 1;
  int _nextObserveId = 1;

  Future<void> connect() async {
    _frames ??= client.frames.listen(_onFrame);
    await client.connect();
  }

  Future<Map<String, Object?>?> dispatch(Map<String, Object?> message) async {
    final method = message['method'];
    final id = message['id'];
    if (method == 'notifications/initialized') return null;
    if (method is! String) return _failure(id, -32600, 'Invalid request');
    try {
      final result = switch (method) {
        'initialize' => _initialize(message),
        'ping' => <String, Object?>{},
        'tools/list' => _toolList(),
        'tools/call' => await _callTool(_map(message['params'])),
        'prompts/list' => <String, Object?>{'prompts': const []},
        'resources/list' => <String, Object?>{'resources': const []},
        _ => throw const _McpError(-32601, 'Method not found'),
      };
      return {'jsonrpc': '2.0', 'id': id, 'result': result};
    } on _McpError catch (error) {
      return _failure(id, error.code, error.message);
    } on SessionProtocolException catch (error) {
      return _failure(id, -32001, error.code);
    } on TimeoutException {
      return _failure(id, -32002, 'Session operation timed out');
    } on Object {
      return _failure(id, -32603, 'Internal error');
    }
  }

  Map<String, Object?> _initialize(Map<String, Object?> message) {
    final params = _map(message['params']);
    return {
      'protocolVersion': params['protocolVersion'] is String
          ? params['protocolVersion']
          : '2025-06-18',
      'capabilities': {
        'tools': {'listChanged': false},
      },
      'serverInfo': {'name': 'ii-ui-mcp', 'version': '0.1.0'},
      'instructions':
          'This server controls only the explicitly granted ii-os frontend session. Observe semantic state before acting. Every action must use the latest revision and stable target id. Never guess coordinates or retry a stale or denied action. Screenshots are bounded, transient, and may be redacted. Sensitive actions require visible user approval in ii-os.',
    };
  }

  Map<String, Object?> _toolList() => {
    'tools': [
      {
        'name': 'ii_ui_observe',
        'description':
            'Read bounded semantic state for the granted ii-os session.',
        'inputSchema': {
          'type': 'object',
          'properties': <String, Object?>{},
          'additionalProperties': false,
        },
        'annotations': {
          'readOnlyHint': true,
          'destructiveHint': false,
          'openWorldHint': false,
        },
      },
      {
        'name': 'ii_ui_screenshot',
        'description': 'Capture the bounded, visibly shared ii-os app surface.',
        'inputSchema': {
          'type': 'object',
          'properties': <String, Object?>{},
          'additionalProperties': false,
        },
        'annotations': {
          'readOnlyHint': true,
          'destructiveHint': false,
          'openWorldHint': false,
        },
      },
      {
        'name': 'ii_ui_action',
        'description':
            'Request one revision-bound semantic action in the granted session.',
        'inputSchema': {
          'type': 'object',
          'required': ['action', 'target', 'expectedRevision'],
          'properties': {
            'action': {
              'type': 'string',
              'enum': [
                'activate',
                'type',
                'select',
                'scroll',
                'navigate',
                'wait_for',
              ],
            },
            'target': {'type': 'string', 'maxLength': 128},
            'expectedRevision': {'type': 'integer', 'minimum': 1},
            'value': {'type': 'string', 'maxLength': 4096},
          },
          'additionalProperties': false,
        },
        'annotations': {
          'readOnlyHint': false,
          'destructiveHint': true,
          'openWorldHint': false,
        },
      },
    ],
  };

  Future<Map<String, Object?>> _callTool(Map<String, Object?> params) async {
    final name = params['name'];
    final arguments = _map(params['arguments']);
    return switch (name) {
      'ii_ui_observe' => await _observe(),
      'ii_ui_screenshot' => await _screenshot(),
      'ii_ui_action' => await _action(arguments),
      _ => throw const _McpError(-32602, 'Unknown tool'),
    };
  }

  Future<Map<String, Object?>> _observe() async {
    final id = 'mcp-observe-${_nextObserveId++}';
    final response = _uiResponses.stream
        .firstWhere((frame) => frame.id == id)
        .timeout(operationTimeout);
    await client.sendFrame(
      SessionFrame(type: 'ui.observe', id: id, payload: const {}),
    );
    final frame = await response;
    if (frame.type == 'ui.unavailable') {
      throw const _McpError(-32004, 'Frontend surface is unavailable');
    }
    late final UiSemanticSnapshot state;
    try {
      state = UiSemanticSnapshot.fromJson(frame.payload);
    } on FormatException {
      throw const _McpError(-32005, 'Frontend state was invalid');
    }
    return _text(jsonEncode(state.toJson()));
  }

  Future<Map<String, Object?>> _action(Map<String, Object?> arguments) async {
    final action = arguments['action'];
    final target = arguments['target'];
    final revision = (arguments['expectedRevision'] as num?)?.toInt() ?? 0;
    final value = arguments['value']?.toString() ?? '';
    if (action is! String ||
        target is! String ||
        revision < 1 ||
        value.length > 4096) {
      throw const _McpError(-32602, 'Invalid UI action arguments');
    }
    UiActionKindWire.parse(action);
    final id = 'mcp-action-${_nextActionId++}';
    final result = _actionResults.stream
        .firstWhere((frame) => frame.id == id)
        .timeout(operationTimeout);
    await client.sendFrame(
      SessionFrame(
        type: 'ui.action',
        id: id,
        payload: {
          'action': action,
          'target': target,
          'expectedRevision': revision,
          if (value.isNotEmpty) 'value': value,
        },
      ),
    );
    return _text(jsonEncode((await result).payload));
  }

  Future<Map<String, Object?>> _screenshot() async {
    final chunks = <int, Uint8List>{};
    String? screenshotId;
    var count = 0;
    var revision = 0;
    var redacted = false;
    final complete = Completer<UiScreenshot>();
    final requestId = 'mcp-screenshot-${_nextActionId++}';
    final rejected = Completer<String>();
    final rejectionSubscription = _actionResults.stream.listen((frame) {
      if (frame.id == requestId && !rejected.isCompleted) {
        final status = frame.payload['status']?.toString() ?? 'failed';
        rejected.complete(status);
      }
    });
    late final StreamSubscription<SessionFrame> subscription;
    subscription = _screenshotChunks.stream.listen((frame) {
      final payload = frame.payload;
      final currentId = payload['screenshotId'];
      final currentCount = (payload['count'] as num?)?.toInt() ?? 0;
      final index = (payload['index'] as num?)?.toInt() ?? -1;
      if (currentId is! String || currentCount < 1 || index < 0) return;
      screenshotId ??= currentId;
      if (screenshotId != currentId || (count != 0 && count != currentCount)) {
        return;
      }
      count = currentCount;
      revision = (payload['revision'] as num?)?.toInt() ?? 0;
      redacted = payload['redacted'] == true;
      chunks[index] = parseTerminalBytes(payload, 44 * 1024);
      if (chunks.length == count && !complete.isCompleted) {
        final builder = BytesBuilder(copy: false);
        for (var part = 0; part < count; part++) {
          final bytes = chunks[part];
          if (bytes == null) return;
          builder.add(bytes);
        }
        complete.complete(
          UiScreenshot(
            revision: revision,
            mimeType: 'image/png',
            bytes: builder.takeBytes(),
            redacted: redacted,
          ),
        );
      }
    });
    try {
      final outcome = Future.any<Object>([
        complete.future,
        rejected.future,
      ]).timeout(operationTimeout);
      await client.sendFrame(
        SessionFrame(
          type: 'ui.screenshot.request',
          id: requestId,
          payload: const {},
        ),
      );
      final result = await outcome;
      if (result is String) {
        throw _McpError(-32003, 'Screenshot request $result');
      }
      final screenshot = result as UiScreenshot;
      return {
        'content': [
          {
            'type': 'image',
            'data': base64Encode(screenshot.bytes),
            'mimeType': screenshot.mimeType,
          },
          {
            'type': 'text',
            'text': jsonEncode({
              'revision': screenshot.revision,
              'redacted': screenshot.redacted,
            }),
          },
        ],
      };
    } finally {
      await subscription.cancel();
      await rejectionSubscription.cancel();
    }
  }

  void _onFrame(SessionFrame frame) {
    if (frame.type == 'ui.state') {
      try {
        UiSemanticSnapshot.fromJson(frame.payload);
      } on FormatException {
        return;
      }
      _uiResponses.add(frame);
    } else if (frame.type == 'ui.unavailable') {
      _uiResponses.add(frame);
    } else if (frame.type == 'ui.action.result') {
      _actionResults.add(frame);
    } else if (frame.type == 'ui.screenshot.chunk') {
      _screenshotChunks.add(frame);
    }
  }

  Future<void> dispose() async {
    await _frames?.cancel();
    await client.dispose();
    await _actionResults.close();
    await _screenshotChunks.close();
    await _uiResponses.close();
  }
}

Map<String, Object?> _text(String value) => {
  'content': [
    {'type': 'text', 'text': value},
  ],
};

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const {};

Map<String, Object?> _failure(Object? id, int code, String message) => {
  'jsonrpc': '2.0',
  'id': id,
  'error': {'code': code, 'message': message},
};

final class _McpError implements Exception {
  const _McpError(this.code, this.message);

  final int code;
  final String message;
}
