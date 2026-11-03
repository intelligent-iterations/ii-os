const interactiveSessionProtocolVersion = 1;

enum SessionLifecycle {
  requested,
  placing,
  starting,
  joinable,
  active,
  ending,
  cleaning,
  cleaned,
  failed,
}

enum ParticipantRole {
  owner,
  collaborator,
  viewer,
  agent,
  supervisor,
  frontend,
}

enum SessionCapability {
  sessionJoin('session.join'),
  sessionManage('session.manage'),
  terminalObserve('terminal.observe'),
  terminalWrite('terminal.write'),
  terminalSignal('terminal.signal'),
  uiObserve('ui.observe'),
  uiAct('ui.act'),
  supervisor('supervisor'),
  frontend('frontend');

  const SessionCapability(this.wireName);

  final String wireName;

  static SessionCapability parse(String value) => values.firstWhere(
    (item) => item.wireName == value,
    orElse: () => throw FormatException('Unknown session capability: $value'),
  );
}

final class InteractiveSessionLimits {
  const InteractiveSessionLimits({
    this.maxParticipants = 8,
    this.maxLifetime = const Duration(hours: 2),
    this.reconnectGrace = const Duration(minutes: 2),
    this.maxReplayBytes = 1024 * 1024,
    this.maxFrameBytes = 64 * 1024,
    this.maxScreenshotBytes = 1024 * 1024,
    this.maxSemanticNodes = 500,
  });

  final int maxParticipants;
  final Duration maxLifetime;
  final Duration reconnectGrace;
  final int maxReplayBytes;
  final int maxFrameBytes;
  final int maxScreenshotBytes;
  final int maxSemanticNodes;

  void validate() {
    if (maxParticipants < 1 ||
        maxParticipants > 32 ||
        maxLifetime <= Duration.zero ||
        maxLifetime > const Duration(hours: 8) ||
        reconnectGrace < Duration.zero ||
        reconnectGrace > const Duration(minutes: 10) ||
        maxReplayBytes < 4096 ||
        maxReplayBytes > 8 * 1024 * 1024 ||
        maxFrameBytes < 1024 ||
        maxFrameBytes > 256 * 1024 ||
        maxScreenshotBytes < 4096 ||
        maxScreenshotBytes > 4 * 1024 * 1024 ||
        maxSemanticNodes < 1 ||
        maxSemanticNodes > 2000) {
      throw const FormatException('Interactive session limits are invalid.');
    }
  }
}

final class InteractiveSessionDescriptor {
  const InteractiveSessionDescriptor({
    required this.id,
    required this.organizationId,
    required this.workspaceId,
    required this.ownerSubject,
    required this.runnerResourceId,
    required this.poolId,
    required this.jobId,
    required this.image,
    required this.lifecycle,
    required this.policyRevision,
    required this.createdAt,
    required this.expiresAt,
    this.leaseId = '',
    this.runtimeIdentity = '',
  });

  factory InteractiveSessionDescriptor.fromJson(Map<String, Object?> json) =>
      InteractiveSessionDescriptor(
        id: _required(json, 'id'),
        organizationId: _required(json, 'organizationId'),
        workspaceId: _required(json, 'workspaceId'),
        ownerSubject: _required(json, 'ownerSubject'),
        runnerResourceId: _required(json, 'runnerResourceId'),
        poolId: _required(json, 'poolId'),
        jobId: _required(json, 'jobId'),
        image: _required(json, 'image'),
        lifecycle: SessionLifecycle.values.byName(_required(json, 'lifecycle')),
        policyRevision: (json['policyRevision'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(_required(json, 'createdAt')).toUtc(),
        expiresAt: DateTime.parse(_required(json, 'expiresAt')).toUtc(),
        leaseId: json['leaseId']?.toString() ?? '',
        runtimeIdentity: json['runtimeIdentity']?.toString() ?? '',
      );

  final String id;
  final String organizationId;
  final String workspaceId;
  final String ownerSubject;
  final String runnerResourceId;
  final String poolId;
  final String jobId;
  final String image;
  final SessionLifecycle lifecycle;
  final int policyRevision;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String leaseId;
  final String runtimeIdentity;

  Map<String, Object?> toJson() => {
    'protocolVersion': interactiveSessionProtocolVersion,
    'id': id,
    'organizationId': organizationId,
    'workspaceId': workspaceId,
    'ownerSubject': ownerSubject,
    'runnerResourceId': runnerResourceId,
    'poolId': poolId,
    'jobId': jobId,
    'image': image,
    'lifecycle': lifecycle.name,
    'policyRevision': policyRevision,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    if (leaseId.isNotEmpty) 'leaseId': leaseId,
    if (runtimeIdentity.isNotEmpty) 'runtimeIdentity': runtimeIdentity,
  };
}

String _required(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key is required');
  }
  return value.trim();
}
