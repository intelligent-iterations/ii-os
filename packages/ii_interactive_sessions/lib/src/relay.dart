import 'frame.dart';
import 'grant.dart';

abstract interface class SessionConnection {
  Stream<SessionFrame> get frames;

  Future<void> send(SessionFrame frame);

  Future<void> close();
}

abstract interface class SessionTransport {
  Future<SessionConnection> connect({
    required Uri relayUri,
    required String grant,
    required int acknowledgedSequence,
  });
}

abstract interface class SessionGrantVerifier {
  SessionGrantClaims verify(
    String token, {
    required String audience,
    required DateTime now,
    String? sessionId,
  });
}

final class SessionProtocolException implements Exception {
  const SessionProtocolException(this.code, [this.message = '']);

  final String code;
  final String message;

  @override
  String toString() => message.isEmpty ? code : '$code: $message';
}
