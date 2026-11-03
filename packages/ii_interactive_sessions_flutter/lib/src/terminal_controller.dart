import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:ii_interactive_sessions/ii_interactive_sessions.dart';
import 'package:xterm/xterm.dart';

final class ParticipantPresence {
  const ParticipantPresence({required this.subject, required this.role});

  final String subject;
  final String role;
}

final class InteractiveTerminalController extends ChangeNotifier {
  InteractiveTerminalController({
    required this.client,
    required this.subject,
    this.disposeClient = true,
    this.canManageSession = false,
  }) : terminal = Terminal(maxLines: 5000) {
    terminal.onOutput = _write;
    terminal.onResize = _resize;
  }

  final InteractiveSessionClient client;
  final String subject;
  final bool disposeClient;
  final bool canManageSession;
  final Terminal terminal;
  StreamSubscription<SessionFrame>? _frames;
  StreamSubscription<SessionConnectionState>? _states;
  Future<void>? _shutdown;
  List<ParticipantPresence> _participants = const [];
  SessionConnectionState _connectionState = SessionConnectionState.disconnected;
  String _inputHolder = '';
  String _inputRequester = '';
  int _inputRevision = 0;

  List<ParticipantPresence> get participants => _participants;
  SessionConnectionState get connectionState => _connectionState;
  String get inputHolder => _inputHolder;
  String get inputRequester => _inputRequester;
  int get inputRevision => _inputRevision;
  bool get canWrite => subject == _inputHolder && _inputRevision > 0;

  Future<void> connect() async {
    _frames ??= client.frames.listen(_onFrame);
    _states ??= client.states.listen((state) {
      _connectionState = state;
      notifyListeners();
    });
    await client.connect();
  }

  Future<void> requestInput() => client.requestInput();

  Future<void> grantInput(String participant) =>
      client.grantInput(participant, expectedRevision: _inputRevision);

  Future<void> shutdown() => _shutdown ??= _shutdownNow();

  Future<void> _shutdownNow() async {
    await _frames?.cancel();
    _frames = null;
    await _states?.cancel();
    _states = null;
    if (disposeClient) await client.dispose();
  }

  void _write(String value) {
    if (canWrite) {
      unawaited(client.writeText(value, leaseRevision: _inputRevision));
    }
  }

  void _resize(int columns, int rows, int pixelWidth, int pixelHeight) {
    if (canWrite) {
      unawaited(
        client.resize(
          columns: columns,
          rows: rows,
          leaseRevision: _inputRevision,
        ),
      );
    }
  }

  void _onFrame(SessionFrame frame) {
    switch (frame.type) {
      case 'terminal.output':
        final bytes = parseTerminalBytes(frame.payload, 64 * 1024);
        terminal.write(utf8.decode(bytes, allowMalformed: true));
      case 'terminal.replay.truncated':
        terminal.write('\r\n[Earlier terminal output was truncated.]\r\n');
      case 'terminal.input.lease':
        _inputRequester = '';
        _applyPresence(frame.payload);
      case 'terminal.input.request':
        if (canManageSession) {
          _inputRequester = frame.payload['subject']?.toString() ?? '';
        }
      case 'presence':
        _applyPresence(frame.payload);
      default:
        return;
    }
    notifyListeners();
  }

  void _applyPresence(Map<String, Object?> payload) {
    final raw = payload['participants'];
    if (raw is List<Object?>) {
      _participants = raw
          .whereType<Map>()
          .map((value) {
            final item = value.cast<String, Object?>();
            return ParticipantPresence(
              subject: item['subject']?.toString() ?? '',
              role: item['role']?.toString() ?? 'viewer',
            );
          })
          .where((item) => item.subject.isNotEmpty)
          .toList();
    }
    _inputHolder =
        payload['subject']?.toString() ??
        payload['inputHolder']?.toString() ??
        _inputHolder;
    _inputRevision =
        (payload['revision'] as num?)?.toInt() ??
        (payload['inputRevision'] as num?)?.toInt() ??
        _inputRevision;
  }

  @override
  void dispose() {
    unawaited(shutdown());
    super.dispose();
  }
}
