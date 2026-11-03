import 'package:ii_os_functions/src/agent_repository_topology.dart';
import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/github_actions_oidc.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 7, 27, 16);
  final agentRepositories = AgentRepositoryTopology.fromConfiguration(
    coordinatorRepository: 'acme-co/coordinator',
    publicationTargets: 'acme-co/public-project',
  );

  test(
    'accepts claims bound to the immutable dev wrapper and reusable workflow',
    () {
      final principal = githubActionsPrincipalFromClaims(
        _claims(now),
        now: now,
        agentRepositories: agentRepositories,
      );

      expect(principal.repository, 'acme-co/example-app');
      expect(principal.repositoryId, 123);
      expect(principal.runId, 456);
      expect(principal.runAttempt, 2);
      expect(principal.jobUses('ii-os-codex-auth.yml'), isTrue);
    },
  );

  test('does not treat the task caller itself as a work-ticket job', () {
    final claims = _claims(now)..remove('job_workflow_ref');
    final principal = githubActionsPrincipalFromClaims(
      claims,
      now: now,
      agentRepositories: agentRepositories,
    );

    expect(principal.jobUses('ii-os-agent-task.yml'), isFalse);
    expect(principal.jobUses('ii-os-codex-auth.yml'), isFalse);
  });

  test('accepts the exact reusable work-ticket body for the task caller', () {
    final tag = 'refs/tags/ii-os-agent-v4-${'a' * 40}';
    final claims = {
      ..._claims(now),
      'job_workflow_ref':
          'acme-co/example-app/.github/workflows/'
          'ii-os-agent-work-ticket.yml@$tag',
    };
    final principal = githubActionsPrincipalFromClaims(
      claims,
      now: now,
      agentRepositories: agentRepositories,
    );

    expect(principal.jobUses('ii-os-agent-task.yml'), isTrue);
    expect(principal.jobUses('ii-os-codex-auth.yml'), isFalse);
  });

  test('rejects a different reusable body for the task caller', () {
    final principal = githubActionsPrincipalFromClaims(
      _claims(now),
      now: now,
      agentRepositories: agentRepositories,
    );

    expect(principal.jobUses('ii-os-agent-task.yml'), isFalse);
    expect(principal.jobUses('ii-os-codex-auth.yml'), isTrue);
  });

  test('rejects a different ref, wrapper, repository, or stale identity', () {
    for (final claims in [
      {..._claims(now), 'ref': 'refs/heads/dev'},
      {
        ..._claims(now),
        'workflow_ref':
            'acme-co/example-app/.github/workflows/other.yml@refs/tags/ii-os-agent-v4-${'a' * 40}',
      },
      {..._claims(now), 'repository_id': '0'},
      {..._claims(now), 'environment': 'unprotected'},
      {..._claims(now), 'sub': 'repo:acme-co/example-app:ref:refs/heads/dev'},
      {
        ..._claims(now),
        'iat':
            now.subtract(const Duration(minutes: 11)).millisecondsSinceEpoch ~/
            1000,
      },
      {
        ..._claims(now),
        'exp':
            now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch ~/
            1000,
      },
    ]) {
      expect(
        () => githubActionsPrincipalFromClaims(
          claims,
          now: now,
          agentRepositories: agentRepositories,
        ),
        throwsA(isA<ApiError>()),
      );
    }
  });

  test('accepts the permission installer on its own bootstrap identity', () {
    final principal = githubActionsPrincipalFromClaims(
      _bootstrapClaims(now),
      now: now,
      agentRepositories: agentRepositories,
    );

    expect(principal.repository, 'acme-co/example-app');
    expect(principal.environment, 'ii-os-agent-bootstrap');
    expect(principal.jobUses('ii-os-agent-permissions.yml'), isTrue);
  });

  test('the installer must run the pinned coordinator implementation', () {
    const impl =
        'acme-co/coordinator/.github/workflows/'
        'ii-os-agent-permissions-impl.yml';
    final tag = 'refs/tags/ii-os-agent-v4-bootstrap-${'a' * 40}';
    final rejected = <String?>[
      // No reusable call at all: a direct dispatch of the implementation.
      null,
      // The caller's own ref form, which Fleet also refuses.
      'acme-co/example-app/.github/workflows/ii-os-agent-permissions.yml@$tag',
      '$impl@$tag',
      // A mutable ref rather than an exact commit.
      '$impl@refs/heads/dev',
      '$impl@dev',
      // Right shape, wrong body or wrong repository.
      'acme-co/coordinator/.github/workflows/'
          'ii-os-agent-task.yml@${'b' * 40}',
      'acme-co/example-app/.github/workflows/'
          'ii-os-agent-permissions-impl.yml@${'b' * 40}',
      // Truncated and over-long revisions.
      '$impl@${'b' * 39}',
      '$impl@${'b' * 41}',
    ];
    for (final jobWorkflowRef in rejected) {
      final claims = {..._bootstrapClaims(now)};
      if (jobWorkflowRef == null) {
        claims.remove('job_workflow_ref');
      } else {
        claims['job_workflow_ref'] = jobWorkflowRef;
      }
      expect(
        () => githubActionsPrincipalFromClaims(
          claims,
          now: now,
          agentRepositories: agentRepositories,
        ),
        throwsA(isA<ApiError>()),
        reason: 'accepted job_workflow_ref ${jobWorkflowRef ?? '<absent>'}',
      );
    }
  });

  test('neither workflow may borrow the other identity', () {
    final sha = 'a' * 40;
    for (final claims in [
      // Bootstrap environment presented with the agent-task tag and workflow.
      {
        ..._bootstrapClaims(now),
        'ref': 'refs/tags/ii-os-agent-v4-$sha',
        'workflow_ref':
            'acme-co/example-app/.github/workflows/ii-os-agent-task.yml@refs/tags/ii-os-agent-v4-$sha',
      },
      // Maintainer environment presented with the bootstrap tag.
      {
        ..._claims(now),
        'ref': 'refs/tags/ii-os-agent-v4-bootstrap-$sha',
        'workflow_ref':
            'acme-co/example-app/.github/workflows/ii-os-agent-permissions.yml@refs/tags/ii-os-agent-v4-bootstrap-$sha',
      },
      // Bootstrap identity naming the agent-task workflow file.
      {
        ..._bootstrapClaims(now),
        'workflow_ref':
            'acme-co/example-app/.github/workflows/ii-os-agent-task.yml@refs/tags/ii-os-agent-v4-bootstrap-$sha',
      },
    ]) {
      expect(
        () => githubActionsPrincipalFromClaims(
          claims,
          now: now,
          agentRepositories: agentRepositories,
        ),
        throwsA(isA<ApiError>()),
      );
    }
  });
}

Map<String, dynamic> _bootstrapClaims(DateTime now) {
  final tag = 'refs/tags/ii-os-agent-v4-bootstrap-${'a' * 40}';
  return {
    ..._claims(now),
    'ref': tag,
    'workflow_ref':
        'acme-co/example-app/.github/workflows/ii-os-agent-permissions.yml@$tag',
    // The dispatch surface is a thin caller, so the job body is the reviewed
    // implementation in the coordinator repository, pinned by commit.
    'job_workflow_ref':
        'acme-co/coordinator/.github/workflows/'
        'ii-os-agent-permissions-impl.yml@${'b' * 40}',
    'sub': 'repo:acme-co/example-app:environment:ii-os-agent-bootstrap',
    'environment': 'ii-os-agent-bootstrap',
  };
}

Map<String, dynamic> _claims(DateTime now) => {
  'repository': 'acme-co/example-app',
  'repository_id': '123',
  'run_id': '456',
  'run_attempt': '2',
  'sha': 'a' * 40,
  'ref': 'refs/tags/ii-os-agent-v4-${'a' * 40}',
  'workflow_ref':
      'acme-co/example-app/.github/workflows/ii-os-agent-task.yml@refs/tags/ii-os-agent-v4-${'a' * 40}',
  'job_workflow_ref':
      'acme-co/example-app/.github/workflows/ii-os-codex-auth.yml@refs/tags/ii-os-agent-v4-${'a' * 40}',
  'actor': 'example-user',
  'sub': 'repo:acme-co/example-app:environment:ii-os-agent-maintainer',
  'environment': 'ii-os-agent-maintainer',
  'event_name': 'workflow_dispatch',
  'iat': now.millisecondsSinceEpoch ~/ 1000,
  'exp': now.add(const Duration(minutes: 5)).millisecondsSinceEpoch ~/ 1000,
};
