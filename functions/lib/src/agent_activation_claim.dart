part of 'agent_activation_store.dart';

final class AgentActivationClaim {
  const AgentActivationClaim({
    required this.profile,
    required this.trustedSourceSha,
    required this.trustedSourceRef,
  });

  final AgentPermissionProfile profile;
  final String trustedSourceSha;
  final String trustedSourceRef;

  bool hasSameAuthority(AgentActivationClaim other) =>
      trustedSourceSha == other.trustedSourceSha &&
      trustedSourceRef == other.trustedSourceRef &&
      profile.id == other.profile.id &&
      profile.version == other.profile.version &&
      agentPermissionProfileDigest(profile) ==
          agentPermissionProfileDigest(other.profile);
}

/// Resolves execution authority only from the immutable human approval.
///
/// The mutable `dev` branch can advance after the click. That must neither
/// widen the approval nor make the approved pass ambiguous.
AgentActivationClaim? approvedAgentActivationClaim(
  Map<String, Object?> data, {
  required String projectId,
  required AgentQueueTicket ticket,
  AgentEngineCatalog engines = AgentEngineCatalog.codexOnly,
}) {
  final snapshotValue = data['permissionProfileSnapshot'];
  final snapshot = snapshotValue is Map
      ? snapshotValue.cast<String, Object?>()
      : null;
  AgentPermissionProfile? profile;
  try {
    profile = snapshot == null
        ? null
        : AgentPermissionProfile.parse(snapshot, engines: engines);
  } on ApiError {
    return null;
  }
  final trustedSourceSha = data['trustedSourceSha'];
  final trustedSourceRef = data['trustedSourceRef'];
  if (profile == null ||
      !_matchesActivationTicket(data, projectId, ticket) ||
      data['permissionVersion'] != profile.version ||
      data['permissionDigest'] != agentPermissionProfileDigest(profile) ||
      data['workflowFile'] != profile.workflow.file ||
      profile.workflow.file != iiOsAgentTaskWorkflow ||
      profile.workflow.ref != ticket.permissionRef ||
      trustedSourceSha is! String ||
      !RegExp(r'^[0-9a-f]{40}$').hasMatch(trustedSourceSha) ||
      trustedSourceRef != 'ii-os-agent-v4-$trustedSourceSha') {
    return null;
  }
  return AgentActivationClaim(
    profile: profile,
    trustedSourceSha: trustedSourceSha,
    trustedSourceRef: trustedSourceRef as String,
  );
}
