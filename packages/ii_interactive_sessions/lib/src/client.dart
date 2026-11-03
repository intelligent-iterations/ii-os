import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'frame.dart';
import 'relay.dart';
import 'ui.dart';

enum SessionConnectionState { disconnected, connecting, connected, failed }

final class InteractiveSessionClient {
  InteractiveSessionClient({
    required this.relayUri,
    required this.grant,
    required this.transport,
  });

  final Uri relayUri;
  final String grant;
  final SessionTransport transport;
  final _frames = StreamController<SessionFrame>.broadcast(sync: true);
  final _states = StreamController<SessionConnectionState>.broadcast(
    sync: true,
  );
  SessionConnection? _connection;
  StreamSubscription<SessionFrame>? _subscription;
  Future<void>? _disposal;
  int _acknowledgedSequence = 0;
  int _nextId = 1;

  Stream<SessionFrame> get frames => _frames.stream;
  Stream<SessionConnectionState> get states => _states.stream;
  int get acknowledgedSequence => _acknowledgedSequence;

  Future<void> connect() async {
    await _subscription?.cancel();
    await _connection?.close();
    _states.add(SessionConnectionState.connecting);
    try {
      final connection = await transport.connect(
        relayUri: relayUri,
        grant: grant,
        acknowledgedSequence: _acknowledgedSequence,
      );
      _connection = connection;
      _subscription = connection.frames.listen(
        (frame) {
          final sequence = frame.sequence;
          if (sequence != null && sequence > _acknowledgedSequence) {
            _acknowledgedSequence = sequence;
          }
          _frames.add(frame);
        },
        onError: (Object error, StackTrace stack) {
          _states.add(SessionConnectionState.failed);
          _frames.addError(error, stack);
        },
        onDone: () => _states.add(SessionConnectionState.disconnected),
      );
      _states.add(SessionConnectionState.connected);
    } on Object {
      _states.add(SessionConnectionState.failed);
      rethrow;
    }
  }

  Future<void> write(Uint8List bytes, {required int leaseRevision}) => _send(
    'terminal.input',
    {...terminalBytes(bytes), 'leaseRevision': leaseRevision},
  );

  Future<void> writeText(String value, {required int leaseRevision}) => write(
    Uint8List.fromList(utf8.encode(value)),
    leaseRevision: leaseRevision,
  );

  Future<void> resize({
    required int columns,
    required int rows,
    required int leaseRevision,
  }) => _send('terminal.resize', {
    'columns': columns,
    'rows': rows,
    'leaseRevision': leaseRevision,
  });

  Future<void> requestInput() => _send('terminal.input.request', const {});

  Future<void> stop() => _send('session.stop', const {});

  Future<void> signal(String signal, {required int leaseRevision}) {
    if (!const {'interrupt', 'terminate', 'hangup'}.contains(signal)) {
      throw const SessionProtocolException('terminal_signal_invalid');
    }
    return _send('terminal.signal', {
      'signal': signal,
      'leaseRevision': leaseRevision,
    });
  }

  Future<void> installAgentGrant(String grant) {
    if (grant.isEmpty || grant.length > 8192) {
      throw const SessionProtocolException('agent_grant_invalid');
    }
    return _send('agent.grant.install', {'grant': grant});
  }

  Future<void> grantInput(String subject, {required int expectedRevision}) =>
      _send('terminal.input.grant', {
        'subject': subject,
        'expectedRevision': expectedRevision,
      });

  Future<void> observeUi() => _send('ui.observe', const {});

  Future<void> publishUiState(UiSemanticSnapshot snapshot) =>
      _send('ui.state', snapshot.toJson());

  Future<void> requestScreenshot() => _send('ui.screenshot.request', const {});

  Future<void> publishScreenshot(UiScreenshot screenshot) async {
    const chunkBytes = 44 * 1024;
    final count = (screenshot.bytes.length / chunkBytes).ceil();
    if (count < 1 || count > 32) {
      throw const SessionProtocolException('screenshot_too_large');
    }
    final screenshotId = 'screenshot-${_nextId++}';
    for (var index = 0; index < count; index++) {
      final start = index * chunkBytes;
      final end = (start + chunkBytes).clamp(0, screenshot.bytes.length);
      await sendFrame(
        SessionFrame(
          type: 'ui.screenshot.chunk',
          id: '$screenshotId-$index',
          payload: {
            'screenshotId': screenshotId,
            'revision': screenshot.revision,
            'mimeType': screenshot.mimeType,
            'redacted': screenshot.redacted,
            'index': index,
            'count': count,
            ...terminalBytes(screenshot.bytes.sublist(start, end)),
          },
        ),
      );
    }
  }

  Future<void> actOnUi({
    required String action,
    required String target,
    required int expectedRevision,
    String value = '',
  }) => _send('ui.action', {
    'action': action,
    'target': target,
    'expectedRevision': expectedRevision,
    if (value.isNotEmpty) 'value': value,
  });

  Future<void> sendFrame(SessionFrame frame) async {
    final connection = _connection;
    if (connection == null) {
      throw const SessionProtocolException('session_not_connected');
    }
    await connection.send(frame);
  }

  Future<void> _send(String type, Map<String, Object?> payload) async {
    final connection = _connection;
    if (connection == null) {
      throw const SessionProtocolException('session_not_connected');
    }
    await connection.send(
      SessionFrame(type: type, id: 'client-${_nextId++}', payload: payload),
    );
  }

  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    await _connection?.close();
    _connection = null;
    if (!_states.isClosed) {
      _states.add(SessionConnectionState.disconnected);
    }
  }

  Future<void> dispose() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    await close();
    final framesHadListeners = _frames.hasListener;
    final framesClosed = _frames.close();
    if (framesHadListeners) await framesClosed;
    final statesHadListeners = _states.hasListener;
    final statesClosed = _states.close();
    if (statesHadListeners) await statesClosed;
  }
}
