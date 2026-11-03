import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'frame.dart';
import 'relay.dart';

final class WebSocketSessionTransport implements SessionTransport {
  const WebSocketSessionTransport({
    this.connectTimeout = const Duration(seconds: 10),
    this.maxFrameBytes = 64 * 1024,
  });

  final Duration connectTimeout;
  final int maxFrameBytes;

  @override
  Future<SessionConnection> connect({
    required Uri relayUri,
    required String grant,
    required int acknowledgedSequence,
  }) async {
    if (relayUri.scheme != 'wss' && relayUri.scheme != 'ws') {
      throw const SessionProtocolException('relay_uri_invalid');
    }
    final channel = WebSocketChannel.connect(relayUri);
    await channel.ready.timeout(connectTimeout);
    channel.sink.add(
      SessionFrame(
        type: 'session.attach',
        id: 'attach',
        payload: {'grant': grant, 'acknowledgedSequence': acknowledgedSequence},
      ).encode(),
    );
    return _WebSocketSessionConnection(channel, maxFrameBytes);
  }
}

final class _WebSocketSessionConnection implements SessionConnection {
  _WebSocketSessionConnection(this._channel, int maxFrameBytes)
    : frames = _channel.stream.map((message) {
        if (message is! String) {
          throw const SessionProtocolException('binary_frame_not_allowed');
        }
        return SessionFrame.decode(message, maxBytes: maxFrameBytes);
      }).asBroadcastStream();

  final WebSocketChannel _channel;

  @override
  final Stream<SessionFrame> frames;

  @override
  Future<void> send(SessionFrame frame) async =>
      _channel.sink.add(frame.encode());

  @override
  Future<void> close() async => _channel.sink.close(1000, 'client closed');
}
