import 'package:ii_interactive_sessions/ii_interactive_sessions.dart';

/// Provider-neutral control port for the ephemeral session relay.
abstract interface class SessionRelayControl {
  Uri connectUri(String sessionId);

  Future<void> register(InteractiveSessionDescriptor descriptor);

  /// Signals that the session and its Fleet request are durably committed.
  Future<void> ready(String sessionId);

  Future<void> discard(String sessionId);

  Future<void> update(InteractiveSessionDescriptor descriptor);

  Future<void> rotateParticipant(
    String sessionId,
    String subject,
    int generation,
  );

  Future<void> end(String sessionId);
}
