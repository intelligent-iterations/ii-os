import 'package:ii_os_functions/src/agent_repository_health.dart';
import 'package:ii_os_functions/src/api_error.dart';
import 'package:test/test.dart';

void main() {
  const repository = 'acme-co/example-app';
  final checkedAt = DateTime.utc(2026, 7, 27, 12);

  test('a satisfied live check set permits dispatch', () {
    final health = resolveAgentRepositoryHealth(
      repository: repository,
      checkedAt: checkedAt,
      sourceSha: 'a' * 40,
      sourceRef: 'ii-os-agent-v4-${'a' * 40}',
      checks: [
        _check('github_installation', 'passed'),
        _check('permission_profile', 'passed'),
        _check('codex_auth_secret', 'passed'),
      ],
    );

    expect(health.status, AgentRepositoryHealthStatus.healthy);
    expect(health.dispatchAllowed, isTrue);
    expect(health.blockers, isEmpty);
  });

  test('a warning is advisory and does not block dispatch', () {
    final health = resolveAgentRepositoryHealth(
      repository: repository,
      checkedAt: checkedAt,
      sourceSha: 'a' * 40,
      sourceRef: 'ii-os-agent-v4-${'a' * 40}',
      checks: [
        _check('github_installation', 'passed'),
        _check('github_app_deployments', 'warning'),
      ],
    );

    expect(health.status, AgentRepositoryHealthStatus.healthy);
    expect(health.dispatchAllowed, isTrue);
    expect(health.blockers, isEmpty);
    expect(health.advisories.single['id'], 'github_app_deployments');
  });

  test('a stored but unverified Codex credential blocks normal tickets', () {
    final health = resolveAgentRepositoryHealth(
      repository: repository,
      checkedAt: checkedAt,
      checks: [
        _check('permission_profile', 'passed'),
        _check('codex_auth_secret', 'securely_stored'),
      ],
    );

    expect(health.status, AgentRepositoryHealthStatus.verificationRequired);
    expect(health.dispatchAllowed, isFalse);
    expect(health.blockers.single['id'], 'codex_auth_secret');
    expect(
      () => requireHealthyAgentRepository(health),
      throwsA(
        isA<ApiError>()
            .having((error) => error.status, 'status', 409)
            .having(
              (error) => error.code,
              'code',
              'agent_repository_not_healthy',
            )
            .having(
              (error) => error.details,
              'details',
              isA<Map<String, Object?>>(),
            ),
      ),
    );
  });

  test('known configuration failures outrank an unavailable remote check', () {
    final health = resolveAgentRepositoryHealth(
      repository: repository,
      checkedAt: checkedAt,
      checks: [
        _check('permission_profile', 'action_required'),
        _check('github_remote_checks', 'unable_to_verify'),
      ],
    );

    expect(health.status, AgentRepositoryHealthStatus.actionRequired);
    expect(health.dispatchAllowed, isFalse);
  });

  test('an unavailable live check outranks an unverified credential', () {
    final health = resolveAgentRepositoryHealth(
      repository: 'acme-co/example-app',
      checkedAt: DateTime.utc(2026, 7, 27),
      checks: [
        _check('codex_auth_secret', 'securely_stored'),
        _check('github_remote_checks', 'unable_to_verify'),
      ],
    );

    expect(health.status, AgentRepositoryHealthStatus.unavailable);
    expect(health.dispatchAllowed, isFalse);
  });
}

Map<String, Object?> _check(String id, String status) => {
  'id': id,
  'label': id,
  'status': status,
  'detail': '',
  'repository': 'acme-co/example-app',
};
