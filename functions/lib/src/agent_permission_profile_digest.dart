part of 'agent_permission_profile.dart';

String agentPermissionProfileDigest(AgentPermissionProfile profile) => sha256
    .convert(utf8.encode(jsonEncode(_canonicalProfileJson(profile.toJson()))))
    .toString();

/// The most a snapshot may occupy on a receipt.
///
/// `AgentPermissionProfile.parse` already bounds every field, so this is a
/// backstop rather than the primary control: it fails the approval closed if a
/// future schema change makes a profile unexpectedly large, instead of writing
/// an unbounded document.
const agentPermissionSnapshotMaxBytes = 16384;

/// A frozen, self-contained record of what a profile permitted at approval
/// time, for storage on the immutable activation receipt.
///
/// The whole profile is kept rather than a summary. The question this answers
/// later -- "what was this agent allowed to do on that exact run" -- is not one
/// you can ask a summary, and the profile is already small and closed-key. It
/// holds no secret material: `secret_injection` names GitHub secrets and
/// capabilities, never values.
Map<String, Object?> boundedAgentPermissionSnapshot(
  AgentPermissionProfile profile,
) {
  final snapshot = _canonicalProfileJson(profile.toJson());
  final size = utf8.encode(jsonEncode(snapshot)).length;
  if (size > agentPermissionSnapshotMaxBytes) {
    throw ApiError(
      422,
      'agent_permission_snapshot_too_large',
      'This permission profile is too large to record on the approval '
          'receipt ($size bytes).',
    );
  }
  return snapshot! as Map<String, Object?>;
}

Object? _canonicalProfileJson(Object? value) {
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort();
    return {for (final key in keys) key: _canonicalProfileJson(value[key])};
  }
  if (value is List<Object?>) {
    return value.map(_canonicalProfileJson).toList();
  }
  return value;
}
