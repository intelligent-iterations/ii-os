// Fleet execution adapter: converts a provider-neutral session intent into an
// exact, immutable JobRequest. It never receives a relay credential.
final _safe = RegExp(r'^[A-Za-z0-9._:-]{1,120}$');
final _pool = RegExp(r'^[a-z0-9][a-z0-9._-]{0,62}$');
final _pinnedImage = RegExp(r'^.+@sha256:[a-f0-9]{64}$');

Map<String, Object?> buildInteractiveCoderRequest({
  required String organizationId,
  required String workspaceId,
  required String actorUid,
  required String sessionId,
  required String runnerResourceId,
  required String poolId,
  required String relayUrl,
  required String image,
  required DateTime submittedAt,
}) {
  if (!_safe.hasMatch(organizationId) ||
      !_safe.hasMatch(workspaceId) ||
      !_safe.hasMatch(actorUid) ||
      !_safe.hasMatch(sessionId) ||
      !_safe.hasMatch(runnerResourceId) ||
      !_pool.hasMatch(poolId)) {
    throw const FormatException('Interactive session identity is invalid.');
  }
  final relay = Uri.tryParse(relayUrl);
  if (relay == null ||
      !const {'wss', 'ws'}.contains(relay.scheme) ||
      relay.host.isEmpty ||
      (relay.scheme == 'ws' &&
          !const {'localhost', '127.0.0.1'}.contains(relay.host))) {
    throw const FormatException('Interactive session relay must use WSS.');
  }
  if (!_pinnedImage.hasMatch(image)) {
    throw const FormatException(
      'Interactive session image must use an immutable sha256 digest.',
    );
  }
  final jobId = 'ii-os:interactive:$workspaceId:$sessionId';
  return {
    'job_id': jobId,
    'profile': 'ii-os-interactive-coder',
    'pool': poolId,
    'resources': {'ram_mb': 2048, 'cpu': 2, 'disk_gb': 20, 'timeout_s': 7200},
    'capabilities': ['runtime-docker', 'interactive-pty'],
    'image': image,
    'runtime': {'kind': 'docker'},
    'tags': {
      'workspace_id': workspaceId,
      'organization_id': organizationId,
      'actor_uid': actorUid,
      'request_id': sessionId,
      'session_id': sessionId,
      'runner_resource_id': runnerResourceId,
      'interactive': 'true',
    },
    'runner': {
      'kind': 'interactive-session',
      'registration': {
        'session_id': sessionId,
        'organization_id': organizationId,
        'workspace_id': workspaceId,
        'policy_revision': '1',
        'session_expires_at': submittedAt
            .toUtc()
            .add(const Duration(hours: 2))
            .toIso8601String(),
        'relay_url': relayUrl,
      },
    },
    'submitted_by': 'ii-os:$actorUid',
    'submitted_at': submittedAt.toUtc().toIso8601String(),
  };
}
