import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/github_client.dart';
import 'package:test/test.dart';

void main() {
  const sha = '0123456789abcdef0123456789abcdef01234567';
  final pull = <String, Object?>{
    'state': 'open',
    'draft': false,
    'merged': false,
    'baseRef': 'dev',
    'headRef': 'ii-os-agent/0123456789abcdef0123456789abcdef',
    'headSha': sha,
  };

  test('deployment evidence requests keep the reviewed timeout ceiling', () {
    expect(qaDeploymentRequestTimeout, const Duration(seconds: 4));
    expect(qaDeploymentCandidateLimit, 1);
    expect(qaDeploymentStatusLimit, 10);
  });

  test('agent PR title describes the immutable source ticket', () {
    expect(
      agentPullRequestTitle(
        '  Ensure agent PRs\ninclude   meaningful titles  ',
        1121,
      ),
      'Ensure agent PRs include meaningful titles (#1121)',
    );

    final longTitle = '🚀' * 300;
    final bounded = agentPullRequestTitle(longTitle, 1121);
    expect(bounded.runes.length, 256);
    expect(bounded, endsWith(' (#1121)'));

    expect(agentPullRequestTitle('修复：代理生成的 PR 标题', 42), '修复：代理生成的 PR 标题 (#42)');
    expect(
      agentPullRequestTitle(
        'Explain auth/token refresh \u2014 don\'t mask 401s',
        7,
      ),
      'Explain auth/token refresh \u2014 don\'t mask 401s (#7)',
    );
  });

  test('agent PR body names the agent runtime that produced the work', () {
    final body = agentPullRequestBody(772);
    expect(body, startsWith('Automated repository work for #772.\n\n'));
    expect(body, contains('exact agent runtime was cleaned'));
    expect(body, contains('Human QA is required before completion.'));
    expect(body, isNot(contains('Fleet')));
  });

  test('merge authorization is bound to the exact agent head and dev', () {
    expect(
      () => requireMergeableAgentPullRequest(pull, expectedHeadSha: sha),
      returnsNormally,
    );
    for (final changed in [
      {...pull, 'headSha': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'},
      {...pull, 'headRef': 'feature/untrusted'},
      {...pull, 'baseRef': 'main'},
      {...pull, 'draft': true},
      {...pull, 'state': 'closed'},
    ]) {
      expect(
        () => requireMergeableAgentPullRequest(changed, expectedHeadSha: sha),
        throwsA(
          isA<ApiError>().having(
            (error) => error.code,
            'code',
            'pull_request_changed',
          ),
        ),
      );
    }
  });

  test('uses repository merge settings without inventing a fallback', () {
    expect(
      preferredPullRequestMergeMethod({'allow_merge_commit': true}),
      'merge',
    );
    expect(
      preferredPullRequestMergeMethod({'allow_squash_merge': true}),
      'squash',
    );
    expect(
      preferredPullRequestMergeMethod({'allow_rebase_merge': true}),
      'rebase',
    );
    expect(preferredPullRequestMergeMethod(const {}), isNull);
  });

  test('a merged agent PR survives GitHub head-repository cleanup', () {
    const mergeSha = '89abcdef0123456789abcdef0123456789abcdef';
    final normalized = normalizePullRequestResponse(
      _cleanedHeadResponse(),
      repository: 'acme-co/example-app',
      number: 123,
    );

    expect(normalized['merged'], isTrue);
    expect(normalized['mergeCommitSha'], mergeSha);
    expect(normalized['headRef'], startsWith('ii-os-agent/'));
  });

  test('a merged App REST response may resolve its merge SHA via GraphQL', () {
    const mergeSha = '89abcdef0123456789abcdef0123456789abcdef';
    final normalized = normalizePullRequestResponse(
      {..._cleanedHeadResponse(), 'merge_commit_sha': null},
      repository: 'acme-co/example-app',
      number: 123,
      resolvedMergeCommitSha: mergeCommitShaFromPullRequestGraphql(
        {
          'repository': {
            'nameWithOwner': 'acme-co/example-app',
            'pullRequest': {
              'number': 123,
              'url': 'https://github.com/acme-co/example-app/pull/123',
              'merged': true,
              'mergeCommit': {'oid': mergeSha},
            },
          },
        },
        repository: 'acme-co/example-app',
        number: 123,
      ),
    );

    expect(normalized['mergeCommitSha'], mergeSha);
  });

  test('the merge-SHA fallback remains bound to the exact pull request', () {
    const mergeSha = '89abcdef0123456789abcdef0123456789abcdef';
    for (final data in [
      {
        'repository': {
          'nameWithOwner': 'other/example-app',
          'pullRequest': {
            'number': 123,
            'url': 'https://github.com/acme-co/example-app/pull/123',
            'merged': true,
            'mergeCommit': {'oid': mergeSha},
          },
        },
      },
      {
        'repository': {
          'nameWithOwner': 'acme-co/example-app',
          'pullRequest': {
            'number': 669,
            'url': 'https://github.com/acme-co/example-app/pull/123',
            'merged': true,
            'mergeCommit': {'oid': mergeSha},
          },
        },
      },
    ]) {
      expect(
        () => mergeCommitShaFromPullRequestGraphql(
          data,
          repository: 'acme-co/example-app',
          number: 123,
        ),
        throwsA(
          isA<ApiError>().having(
            (error) => error.code,
            'code',
            'github_response_invalid',
          ),
        ),
      );
    }
  });

  test('head cleanup never relaxes open or non-agent PR identity', () {
    for (final response in [
      _cleanedHeadResponse(merged: false),
      _cleanedHeadResponse(headRef: 'feature/manual'),
    ]) {
      expect(
        () => normalizePullRequestResponse(
          response,
          repository: 'acme-co/example-app',
          number: 123,
        ),
        throwsA(
          isA<ApiError>().having(
            (error) => error.code,
            'code',
            'github_response_invalid',
          ),
        ),
      );
    }
  });

  test('QA handoff requires an actually merged agent pull request', () {
    expect(
      () => requireMergedAgentPullRequest({
        ...pull,
        'state': 'closed',
        'merged': true,
      }),
      returnsNormally,
    );
    for (final changed in [
      pull,
      {...pull, 'state': 'closed', 'merged': true, 'baseRef': 'main'},
      {...pull, 'state': 'closed', 'merged': true, 'headRef': 'feature/manual'},
    ]) {
      expect(
        () => requireMergedAgentPullRequest(changed),
        throwsA(
          isA<ApiError>().having(
            (error) => error.code,
            'code',
            'pull_request_not_merged',
          ),
        ),
      );
    }
  });

  test('QA handoff accepts a successful dev deployment covering the merge', () {
    const mergeSha = '89abcdef0123456789abcdef0123456789abcdef';
    const deployedSha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final deployed = {
      ...pull,
      'state': 'closed',
      'merged': true,
      'mergeCommitSha': mergeSha,
      'qaDeployment': {
        'deploymentId': 42,
        'environment': 'dev',
        'sha': deployedSha,
        'coversSha': mergeSha,
        'coverage': 'ancestor',
        'state': 'success',
        'succeeded': true,
      },
    };

    expect(() => requireSuccessfulQaDeployment(deployed), returnsNormally);
    for (final changed in [
      {...deployed, 'qaDeployment': null},
      {
        ...deployed,
        'qaDeployment': {
          ...(deployed['qaDeployment']! as Map<String, Object?>),
          'state': 'in_progress',
          'succeeded': false,
        },
      },
      {
        ...deployed,
        'qaDeployment': {
          ...(deployed['qaDeployment']! as Map<String, Object?>),
          'environment': 'production',
        },
      },
      {
        ...deployed,
        'qaDeployment': {
          ...(deployed['qaDeployment']! as Map<String, Object?>),
          'coversSha': sha,
        },
      },
    ]) {
      expect(
        () => requireSuccessfulQaDeployment(changed),
        throwsA(
          isA<ApiError>().having(
            (error) => error.code,
            'code',
            'qa_deployment_not_successful',
          ),
        ),
      );
    }
  });

  test('deployment coverage accepts only an exact commit or descendant', () {
    const mergeSha = '89abcdef0123456789abcdef0123456789abcdef';
    const deployedSha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

    expect(
      deploymentCoversMergeCommit(
        mergeSha: mergeSha,
        deployedSha: mergeSha,
        comparison: null,
      ),
      isTrue,
    );
    expect(
      deploymentCoversMergeCommit(
        mergeSha: mergeSha,
        deployedSha: deployedSha,
        comparison: const {
          'status': 'ahead',
          'ahead_by': 3,
          'behind_by': 0,
          'merge_base_commit': {'sha': mergeSha},
        },
      ),
      isTrue,
    );
    for (final comparison in const [
      {
        'status': 'diverged',
        'ahead_by': 2,
        'behind_by': 1,
        'merge_base_commit': {'sha': sha},
      },
      {
        'status': 'behind',
        'ahead_by': 0,
        'behind_by': 1,
        'merge_base_commit': {'sha': deployedSha},
      },
    ]) {
      expect(
        deploymentCoversMergeCommit(
          mergeSha: mergeSha,
          deployedSha: deployedSha,
          comparison: comparison,
        ),
        isFalse,
      );
    }
  });

  test('normalizes the latest SHA-bound deployment and its status history', () {
    const mergeSha = '89abcdef0123456789abcdef0123456789abcdef';
    final deployment = selectQaDeployment(
      repository: 'acme-co/example-app',
      sha: mergeSha,
      environment: 'dev',
      values: [
        {
          'id': 41,
          'sha': mergeSha,
          'environment': 'dev',
          'created_at': '2026-08-24T10:00:00Z',
        },
        {
          'id': 42,
          'sha': mergeSha,
          'environment': 'dev',
          'created_at': '2026-08-24T10:01:00Z',
        },
      ],
    );
    final proof = normalizeQaDeploymentProof(
      deployment: deployment,
      statuses: const [
        {
          'id': 100,
          'state': 'success',
          'environment': 'dev',
          'log_url': 'https://github.com/acme-co/example-app/actions/runs/99',
          'environment_url': 'https://dev.example.com',
          'created_at': '2026-08-24T10:03:00Z',
        },
        {
          'id': 101,
          'state': 'inactive',
          'environment': 'dev',
          'log_url': 'https://github.com/acme-co/example-app/actions/runs/99',
          'environment_url': 'https://dev.example.com',
          'created_at': '2026-08-24T10:04:00Z',
        },
      ],
    );

    expect(deployment?['id'], 42);
    expect(proof['state'], 'inactive');
    expect(proof['succeeded'], isTrue);
    expect(proof['sha'], mergeSha);
    expect(proof['coversSha'], mergeSha);
    expect(proof['coverage'], 'exact');
    expect(proof['environment'], 'dev');
    expect(proof['environmentUrl'], 'https://dev.example.com');

    final failedAfterSuccess = normalizeQaDeploymentProof(
      deployment: deployment,
      statuses: const [
        {
          'id': 102,
          'state': 'failure',
          'environment': 'dev',
          'created_at': '2026-08-24T10:05:00Z',
        },
        {
          'id': 100,
          'state': 'success',
          'environment': 'dev',
          'created_at': '2026-08-24T10:03:00Z',
        },
      ],
    );
    expect(failedAfterSuccess['succeeded'], isFalse);
  });

  test('selects one bounded latest environment deployment', () {
    const deployedSha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    expect(
      selectLatestQaDeployment(
        repository: 'acme-co/example-app',
        environment: 'dev',
        values: const [
          {
            'id': 42,
            'sha': deployedSha,
            'environment': 'dev',
            'created_at': '2026-08-26T12:00:00Z',
          },
        ],
      ),
      containsPair('sha', deployedSha),
    );
    expect(
      selectLatestQaDeployment(
        repository: 'acme-co/example-app',
        environment: 'dev',
        values: const [],
      ),
      isNull,
    );
    expect(
      () => selectLatestQaDeployment(
        repository: 'acme-co/example-app',
        environment: 'dev',
        values: const <Map<String, Object?>>[{}, {}],
      ),
      throwsA(isA<ApiError>()),
    );
  });
}

Map<String, Object?> _cleanedHeadResponse({
  bool merged = true,
  String headRef = 'ii-os-agent/0123456789abcdef0123456789abcdef',
}) => {
  'number': 123,
  'title': 'Expose the workflow URL',
  'html_url': 'https://github.com/acme-co/example-app/pull/123',
  'state': merged ? 'closed' : 'open',
  'draft': false,
  'merged': merged,
  'merge_commit_sha': merged
      ? '89abcdef0123456789abcdef0123456789abcdef'
      : null,
  'mergeable': null,
  'mergeable_state': 'unknown',
  'head': {
    'ref': headRef,
    'sha': '0123456789abcdef0123456789abcdef01234567',
    'repo': null,
  },
  'base': {
    'ref': 'dev',
    'sha': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    'repo': {'full_name': 'acme-co/example-app'},
  },
};
