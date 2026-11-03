import 'package:ii_os_functions/src/agent_permission_approval_store.dart';
import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/github_client.dart';
import 'package:test/test.dart';

void main() {
  test(
    'a callback must carry every value the installer is allowed to send',
    () {
      final callback = parseAgentPermissionCallback(_body());

      expect(callback.workspaceId, 'workspace-1');
      expect(callback.dispatchFence, 3);
      expect(callback.profileDigest, 'a' * 64);
    },
  );

  test('a callback outside the installer contract is refused', () {
    for (final body in <Map<String, Object?>>[
      {..._body(), 'dispatch_fence': 0},
      {..._body(), 'dispatch_fence': -1},
      {..._body(), 'dispatch_fence': '3'},
      // The workflow itself enforces 20 characters minimum.
      {..._body(), 'dispatch_id': 'short'},
      {..._body(), 'profile_digest': 'A' * 64},
      {..._body(), 'profile_digest': 'a' * 63},
      {..._body(), 'workspace_id': 'workspace/1'},
      {..._body(), 'profile_id': '.leading-dot'},
      {..._body(), 'profile_json': 1},
      {..._body()}..remove('workspace_id'),
    ]) {
      expect(
        () => parseAgentPermissionCallback(body),
        throwsA(isA<ApiError>()),
        reason: 'accepted $body',
      );
    }
  });

  test('an approval authorizes only the exact install it recorded', () {
    final approval = <String, Object?>{
      'workspaceId': 'workspace-1',
      'dispatchId': 'd' * 24,
      'dispatchFence': 3,
      'profileId': 'ii-os-agent-maintainer',
      'profileVersion': '4',
      'profileDigest': 'a' * 64,
      'profileJson': '{"id":"ii-os-agent-maintainer"}',
    };
    final callback = parseAgentPermissionCallback(_body());

    expect(agentPermissionApprovalMatches(approval, callback), isTrue);

    for (final field in approval.keys) {
      final tampered = {...approval, field: 'tampered'};
      expect(
        agentPermissionApprovalMatches(tampered, callback),
        isFalse,
        reason: 'a changed $field still matched the approval',
      );
    }
  });

  test(
    'the installer may only be dispatched on an immutable bootstrap tag',
    () {
      expect(
        () => requireAgentPermissionDispatchRef(
          'ii-os-agent-v4-bootstrap-${'a' * 40}',
        ),
        returnsNormally,
      );
      for (final ref in [
        'dev',
        'a' * 40,
        'ii-os-agent-v4-${'a' * 40}',
        'ii-os-agent-v4-bootstrap-${'a' * 39}',
        'refs/tags/ii-os-agent-v4-bootstrap-${'a' * 40}',
      ]) {
        expect(
          () => requireAgentPermissionDispatchRef(ref),
          throwsA(isA<ApiError>()),
          reason: 'accepted $ref',
        );
      }
    },
  );
}

Map<String, Object?> _body() => {
  'workspace_id': 'workspace-1',
  'dispatch_id': 'd' * 24,
  'dispatch_fence': 3,
  'profile_id': 'ii-os-agent-maintainer',
  'profile_version': '4',
  'profile_digest': 'a' * 64,
  'profile_json': '{"id":"ii-os-agent-maintainer"}',
};
