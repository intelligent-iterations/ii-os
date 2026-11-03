import 'models.dart';

final class InteractiveSessionModel {
  const InteractiveSessionModel({
    required this.id,
    required this.workspaceId,
    required this.ownerSubject,
    required this.runnerResourceId,
    required this.poolId,
    required this.lifecycle,
    required this.createdAt,
    required this.expiresAt,
    required this.participants,
  });

  factory InteractiveSessionModel.fromJson(JsonMap json) =>
      InteractiveSessionModel(
        id: json['id']?.toString() ?? '',
        workspaceId: json['workspaceId']?.toString() ?? '',
        ownerSubject: json['ownerSubject']?.toString() ?? '',
        runnerResourceId: json['runnerResourceId']?.toString() ?? '',
        poolId: json['poolId']?.toString() ?? '',
        lifecycle: json['lifecycle']?.toString() ?? 'requested',
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
        expiresAt: DateTime.tryParse(json['expiresAt']?.toString() ?? ''),
        participants: switch (json['participants']) {
          final List<Object?> items =>
            items
                .map(asJsonMap)
                .where((item) => item.isNotEmpty && item['revoked'] != true)
                .map(InteractiveSessionParticipantModel.fromJson)
                .toList(),
          _ => const [],
        },
      );

  final String id;
  final String workspaceId;
  final String ownerSubject;
  final String runnerResourceId;
  final String poolId;
  final String lifecycle;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final List<InteractiveSessionParticipantModel> participants;

  bool get terminal =>
      const {'ending', 'cleaning', 'cleaned', 'failed'}.contains(lifecycle);
}

final class InteractiveSessionParticipantModel {
  const InteractiveSessionParticipantModel({
    required this.subject,
    required this.role,
  });

  factory InteractiveSessionParticipantModel.fromJson(JsonMap json) =>
      InteractiveSessionParticipantModel(
        subject: json['subject']?.toString() ?? '',
        role: json['role']?.toString() ?? 'viewer',
      );

  final String subject;
  final String role;
}

final class InteractiveRunnerPoolOption {
  const InteractiveRunnerPoolOption({
    required this.resourceId,
    required this.name,
    required this.providerPoolId,
    required this.primary,
    required this.maxConcurrent,
  });

  factory InteractiveRunnerPoolOption.fromJson(JsonMap json) =>
      InteractiveRunnerPoolOption(
        resourceId: json['resourceId']?.toString() ?? '',
        name: json['name']?.toString() ?? 'Runner pool',
        providerPoolId: json['providerPoolId']?.toString() ?? '',
        primary: json['primary'] == true,
        maxConcurrent: (json['maxConcurrent'] as num?)?.toInt() ?? 1,
      );

  final String resourceId;
  final String name;
  final String providerPoolId;
  final bool primary;
  final int maxConcurrent;
}

final class InteractiveSessionAttachment {
  const InteractiveSessionAttachment({
    required this.relayUri,
    required this.grant,
    required this.subject,
    required this.role,
  });

  factory InteractiveSessionAttachment.fromJson(JsonMap json) =>
      InteractiveSessionAttachment(
        relayUri: Uri.parse(json['relayUri']! as String),
        grant: json['grant']! as String,
        subject: json['subject']! as String,
        role: json['role']! as String,
      );

  final Uri relayUri;
  final String grant;
  final String subject;
  final String role;
}

final class InteractiveUiAccessGrant {
  const InteractiveUiAccessGrant({
    required this.relayUri,
    required this.frontendGrant,
    required this.agentGrant,
    required this.allowAct,
  });

  factory InteractiveUiAccessGrant.fromJson(JsonMap json) =>
      InteractiveUiAccessGrant(
        relayUri: Uri.parse(json['relayUri']! as String),
        frontendGrant: json['frontendGrant']! as String,
        agentGrant: json['agentGrant']! as String,
        allowAct: json['allowAct'] == true,
      );

  final Uri relayUri;
  final String frontendGrant;
  final String agentGrant;
  final bool allowAct;
}
