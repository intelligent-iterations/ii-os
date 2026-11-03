import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ii_os_functions/src/github_client.dart';
import 'package:test/test.dart';

Map<String, Object?> recording() =>
    jsonDecode(
          File(
            'test/fixtures/runtime_workflow_security_projection.json',
          ).readAsStringSync(),
        )
        as Map<String, Object?>;

Map<String, Object?> dispatch(Map<String, Object?> value) =>
    (((value['workTicket'] as Map)['jobs'] as Map)['dispatch'] as Map)
        .cast<String, Object?>();

List<dynamic> steps(Map<String, Object?> value) =>
    dispatch(value)['steps']! as List<dynamic>;

Map<String, dynamic> step(Map<String, Object?> value, String id) => steps(
  value,
).cast<Map<String, dynamic>>().singleWhere((item) => item['id'] == id);

Map<String, Object?> check(Map<String, Object?> value) =>
    agentWorkflowEnvironmentCheck(
      jsonEncode(value['gateway']),
      workTicketSource: jsonEncode(value['workTicket']),
      repository: 'example-org/project',
    );

void main() {
  test('recorded runtime workflow satisfies the broker security boundary', () {
    final value = recording();
    final provenance = value['provenance']! as Map<String, dynamic>;
    expect(provenance['kind'], 'recorded-workflow-security-projection');
    for (final source
        in (provenance['sourceFiles'] as Map).values
            .cast<Map<String, dynamic>>()) {
      expect(source['sha256'], matches(RegExp(r'^[a-f0-9]{64}$')));
      expect(source['gitBlob'], matches(RegExp(r'^[a-f0-9]{40}$')));
    }
    expect(check(value)['status'], 'passed');
  });

  final reviewedDirectory =
      Platform.environment['II_OS_REVIEWED_WORKFLOW_DIRECTORY'];
  if (reviewedDirectory != null) {
    test('actual reviewed producer matches its recording and is ready', () {
      final directory = Directory(reviewedDirectory).absolute;
      final gateway = File('${directory.path}/ii-os-agent-task.yml');
      final workTicket = File('${directory.path}/ii-os-agent-work-ticket.yml');
      final sources = {'gateway': gateway, 'workTicket': workTicket};
      final provenance = recording()['provenance']! as Map<String, dynamic>;
      final recordedSources = provenance['sourceFiles'] as Map;
      for (final source in sources.entries) {
        expect(
          sha256.convert(source.value.readAsBytesSync()).toString(),
          (recordedSources[source.key] as Map)['sha256'],
          reason: 'Refresh the recorded projection when its producer changes.',
        );
      }
      expect(
        agentWorkflowEnvironmentCheck(
          gateway.readAsStringSync(),
          workTicketSource: workTicket.readAsStringSync(),
          repository: 'example-org/project',
        )['status'],
        'passed',
      );
    });
  }

  test('runtime guard formatting preserves readiness', () {
    final value = recording();
    for (final id in [
      'runtime-cleanup',
      'publication-authorization',
      'publication',
      'finalization',
    ]) {
      final selected = step(value, id);
      selected['if'] = (selected['if'] as String).replaceAll(' && ', '\n && ');
    }
    expect(check(value)['status'], 'passed');
  });

  final refused = <String, void Function(Map<String, Object?>)>{
    'a second execution backend': (value) {
      steps(value).add({'id': 'fleet', 'env': <String, Object?>{}});
    },
    'a runtime command replaced with another launcher': (value) {
      step(value, 'runtime')['run'] = 'python3 another_launcher.py';
    },
    'write authority before cleanup': (value) {
      (step(value, 'api-token')['with'] as Map)['permission-contents'] =
          'write';
    },
    'a mounted publisher credential': (value) {
      (step(value, 'runtime')['env'] as Map)['GITHUB_PUSH_TOKEN'] = 'writer';
    },
    'a cleanup observer after staged credentials are removed': (value) {
      final observer = step(value, 'runtime-cleanup');
      steps(value).remove(observer);
      final cleanup = steps(value).indexOf(step(value, 'token-cleanup'));
      steps(value).insert(cleanup + 1, observer);
    },
    'cleanup replaying execute': (value) {
      step(value, 'runtime-cleanup')['run'] =
          'python3 -m providers.runtime_ticket';
    },
    'cleanup without the interruption guard': (value) {
      step(value, 'runtime-cleanup')['if'] = r'${{ always() }}';
    },
    'a publication guard bypass': (value) {
      final authorization = step(value, 'publication-authorization');
      authorization['if'] = (authorization['if'] as String).replaceFirst(
        ' }}',
        ' || true }}',
      );
    },
    'a whitespace value substituted for an empty bundle': (value) {
      final authorization = step(value, 'publication-authorization');
      authorization['if'] = (authorization['if'] as String).replaceFirst(
        "agent_bundle_artifact_b64 != ''",
        "agent_bundle_artifact_b64 != ' '",
      );
    },
    'publication without usage delivery': (value) {
      final authorization = step(value, 'publication-authorization');
      authorization['if'] = (authorization['if'] as String).replaceFirst(
        " && steps.runtime.outputs.runtime_usage_proven == 'true'",
        '',
      );
    },
    'recovery bundle publication': (value) {
      (step(value, 'publication')['env'] as Map)['AGENT_BUNDLE_ARTIFACT_B64'] =
          r'${{ steps.runtime-cleanup.outputs.agent_bundle_artifact_b64 }}';
    },
    'recovery result finalization': (value) {
      (step(value, 'finalization')['env'] as Map)['AGENT_RESULT_B64'] =
          r'${{ steps.runtime-cleanup.outputs.agent_result_b64 }}';
    },
    'finalization without cleanup': (value) {
      final finalizer = step(value, 'finalization');
      finalizer['if'] = (finalizer['if'] as String).replaceFirst(
        "steps.runtime.outputs.runtime_cleanup_proven == 'true' && ",
        '',
      );
    },
    'an unproved usage exemption': (value) {
      final finalizer = step(value, 'finalization');
      finalizer['if'] = (finalizer['if'] as String).replaceAll(
        'runtime_execution_never_started',
        'unverified_execution_status',
      );
    },
    'a finalization guard bypass': (value) {
      final finalizer = step(value, 'finalization');
      finalizer['if'] = (finalizer['if'] as String).replaceFirst(
        ' }}',
        ' || true }}',
      );
    },
  };
  for (final mutation in refused.entries) {
    test('runtime readiness refuses ${mutation.key}', () {
      final value = recording();
      mutation.value(value);
      expect(check(value)['status'], 'action_required');
    });
  }
}
