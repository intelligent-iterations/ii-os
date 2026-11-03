import 'package:ii_os_functions/src/providers/fleet/interactive_session_execution.dart';
import 'package:test/test.dart';

void main() {
  test('builds a disposable 2GB interactive coder Fleet request', () {
    final request = buildInteractiveCoderRequest(
      organizationId: 'org-1',
      workspaceId: 'workspace-1',
      actorUid: 'user-1',
      sessionId: 'run-1',
      runnerResourceId: 'runner-personal',
      poolId: 'personal-alice',
      relayUrl: 'wss://relay.example/v1/connect/run-1',
      image:
          'registry.example/session@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      submittedAt: DateTime.utc(2026, 8, 25),
    );
    expect(request['resources'], containsPair('ram_mb', 2048));
    expect(request['runtime'], containsPair('kind', 'docker'));
    expect(request['tags'], containsPair('interactive', 'true'));
    expect(request['pool'], 'personal-alice');
    expect(request['runner'], containsPair('kind', 'interactive-session'));
    final runner = request['runner']! as Map<String, Object?>;
    final registration = runner['registration']! as Map<String, Object?>;
    expect(registration, isNot(contains('grant')));
  });

  test('rejects unsafe relay URLs and identities', () {
    expect(
      () => buildInteractiveCoderRequest(
        organizationId: 'org-1',
        workspaceId: 'workspace/escape',
        actorUid: 'u',
        sessionId: 'r',
        runnerResourceId: 'runner',
        poolId: 'personal',
        relayUrl: 'http://relay',
        image:
            'registry.example/session@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        submittedAt: DateTime.utc(2026),
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
