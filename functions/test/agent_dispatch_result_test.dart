import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:ii_os_functions/src/agent_dispatch_result.dart';
import 'package:ii_os_functions/src/api_error.dart';
import 'package:test/test.dart';

void main() {
  test('accepts only a bounded exact-ticket broker result', () {
    final result = AgentDispatchResult.parse(_result());

    expect(result.outcome, 'ready_for_qa');
    expect(result.projectStatus, 'ready_for_qa');
    expect(result.comments, ['Live verification passed.']);
    expect(result.repositoryId, 123456789);
    expect(result.pullRequest?.base, 'dev');
    expect(result.pullRequest?.repository, 'acme-co/ui-app');
    expect(result.pullRequest?.repositoryId, 987654321);
    expect(result.automationFailure, isNull);
    expect(result.hasPublishableChange, isTrue);
    expect(result.canonicalJson.keys, {
      'automation_failure',
      'comments',
      'dispatch_id',
      'issue_number',
      'outcome',
      'project_item_id',
      'pull_request',
      'repository',
      'repository_id',
      'status',
    });
  });

  test('accepts a bounded automation-owned Todo result', () {
    final result = AgentDispatchResult.parse(
      (jsonDecode(
                jsonEncode({
                  ..._result(),
                  'outcome': 'not_ready',
                  'status': 'todo',
                  'pull_request': null,
                  'automation_failure': {
                    'code': 'agent_worker_setup_failed',
                    'detail': 'The permission profile could not start.',
                  },
                }),
              )
              as Map<String, dynamic>)
          .cast<String, Object?>(),
    );

    expect(result.projectStatus, 'todo');
    expect(result.automationFailure?.code, 'agent_worker_setup_failed');
    expect(result.hasPublishableChange, isFalse);
    expect(result.canonicalJson['automation_failure'], {
      'code': 'agent_worker_setup_failed',
      'detail': 'The permission profile could not start.',
    });
  });

  test('publishes bounded changes before human review', () {
    final result = AgentDispatchResult.parse({
      ..._result(),
      'outcome': 'not_ready',
      'status': 'needs_human_input',
      'comments': ['Review and merge the broker-created pull request.'],
    });

    expect(result.projectStatus, 'needs_human_input');
    expect(result.pullRequest, isNotNull);
    expect(result.automationFailure, isNull);
    expect(result.hasPublishableChange, isTrue);
  });

  test(
    'rejects status escalation, extra authority, and unbounded comments',
    () {
      final mutations = <Map<String, Object?> Function()>[
        () => {..._result(), 'status': 'done'},
        () => {..._result(), 'outcome': 'not_ready'},
        () => {
          ..._result(),
          'automation_failure': {
            'code': 'agent_worker_setup_failed',
            'detail': 'Failure cannot accompany Ready for QA.',
          },
        },
        () => {
          ..._result(),
          'outcome': 'not_ready',
          'status': 'todo',
          'pull_request': null,
          'automation_failure': {
            'code': 'INVALID-CODE',
            'detail': 'Invalid failure code.',
          },
        },
        () => {..._result(), 'create_issue': true},
        () => {..._result(), 'repository_id': 0},
        () => {..._result(), 'comments': List.filled(9, 'comment')},
        () => {
          ..._result(),
          'comments': ['x' * 8001],
        },
        () => {..._result(), 'project_item_id': 'different/item'},
        () => {
          ..._result(),
          'pull_request': {'head': 'ii-os-agent/${'0' * 32}', 'base': 'dev'},
        },
        () => {
          ..._result(),
          'pull_request': {..._pullRequest(), 'head_sha': '0' * 39},
        },
        () => {
          ..._result(),
          'pull_request': {..._pullRequest(), 'title': 'Untrusted title'},
        },
      ];
      for (final candidate in mutations) {
        expect(
          () => AgentDispatchResult.parse(candidate()),
          throwsA(isA<ApiError>()),
        );
      }
    },
  );
}

Map<String, Object?> _result() => {
  'dispatch_id': 'human:item-1',
  'repository': 'acme-co/example-app',
  'repository_id': 123456789,
  'issue_number': 42,
  'project_item_id': 'PVTI_item_1',
  'outcome': 'ready_for_qa',
  'status': 'ready_for_qa',
  'comments': ['Live verification passed.'],
  'pull_request': _pullRequest(),
  'automation_failure': null,
};

Map<String, Object?> _pullRequest() {
  const dispatchId = 'human:item-1';
  final key = sha256
      .convert(utf8.encode(dispatchId))
      .toString()
      .substring(0, 32);
  return {
    'repository': 'acme-co/ui-app',
    'repository_id': 987654321,
    'head': 'ii-os-agent/$key',
    'base': 'dev',
    'head_sha': '1' * 40,
    'base_sha': '2' * 40,
    'expected_old_head_sha': null,
  };
}
