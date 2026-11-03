import 'package:ii_interactive_sessions/ii_interactive_sessions.dart';

const interactiveSessionCollection = 'interactiveSessions';
const interactiveSessionCounterCollection = 'interactiveSessionCounters';
const interactiveSessionListLimit = 20;
const interactiveSessionLifetime = Duration(hours: 2);
const interactiveAttachGrantLifetime = Duration(minutes: 5);

final class InteractiveSessionParticipant {
  const InteractiveSessionParticipant({
    required this.subject,
    required this.role,
    required this.generation,
    this.revoked = false,
  });

  factory InteractiveSessionParticipant.fromJson(Map<String, Object?> json) {
    final subject = json['subject']?.toString().trim() ?? '';
    final generation = (json['generation'] as num?)?.toInt() ?? 0;
    if (subject.isEmpty || generation < 0) {
      throw const FormatException('Invalid session participant.');
    }
    return InteractiveSessionParticipant(
      subject: subject,
      role: ParticipantRole.values.byName(json['role']?.toString() ?? ''),
      generation: generation,
      revoked: json['revoked'] == true,
    );
  }

  final String subject;
  final ParticipantRole role;
  final int generation;
  final bool revoked;

  Map<String, Object?> toJson() => {
    'subject': subject,
    'role': role.name,
    'generation': generation,
    if (revoked) 'revoked': true,
  };
}

final class InteractiveSessionRecord {
  const InteractiveSessionRecord({
    required this.descriptor,
    required this.relayUri,
    required this.participants,
    this.stoppedAt,
  });

  final InteractiveSessionDescriptor descriptor;
  final Uri relayUri;
  final List<InteractiveSessionParticipant> participants;
  final DateTime? stoppedAt;

  InteractiveSessionParticipant? participant(String subject) =>
      participants.where((item) => item.subject == subject).firstOrNull;

  Map<String, Object?> toJson() => {
    ...descriptor.toJson(),
    'relayUri': relayUri.toString(),
    'participants': participants.map((item) => item.toJson()).toList(),
    if (stoppedAt != null) 'stoppedAt': stoppedAt!.toIso8601String(),
  };
}

abstract interface class InteractiveSessionRepository {
  Future<void> create({
    required InteractiveSessionRecord session,
    required Map<String, Object?> fleetRequest,
    required int maxConcurrent,
  });

  Future<InteractiveSessionRecord> get(String workspaceId, String sessionId);

  Future<List<InteractiveSessionRecord>> list(String workspaceId);

  Future<InteractiveSessionRecord> putParticipant({
    required String workspaceId,
    required String sessionId,
    required InteractiveSessionParticipant participant,
  });

  Future<InteractiveSessionRecord> revokeParticipant({
    required String workspaceId,
    required String sessionId,
    required String subject,
  });

  Future<InteractiveSessionRecord> stop({
    required String workspaceId,
    required String sessionId,
    required DateTime now,
  });
}
