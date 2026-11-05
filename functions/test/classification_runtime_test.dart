import 'dart:async';

import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/classification_runtime.dart';
import 'package:ii_os_functions/src/domain.dart';
import 'package:ii_os_functions/src/github_workflow_coordinator.dart';
import 'package:ii_os_functions/src/workflow_catalog.dart';
import 'package:test/test.dart';

const _catalogYaml = '''
schema_version: 1
workflows:
  - id: image-create
    name: Z-Image Turbo
    model: Z-Image Turbo
    contract_version: 1
    dispatch_workflow: .github/workflows/z-image-turbo-text-to-image.yml
    inputs:
      prompt:
        type: string
        required: true
        max_length: 60000
    outputs:
      - kind: image
        content_types: [image/png]
        max_bytes: 52428800
  - id: classification-open-jev-9b
    name: Open JEV 9B Classification
    model: autotrust/JEV-9B
    contract_version: 1
    dispatch_workflow: .github/workflows/open-jev-classification.yml
    inputs:
      state:
        type: string
        required: true
        max_length: 8000
      questions:
        type: string
        required: true
        max_length: 32000
    outputs:
      - kind: decisions
        content_types: [application/json]
        max_bytes: 1048576
''';

WorkflowCatalog _catalog() => WorkflowCatalog.parse(
  repository: 'acme-co/example-app',
  repositoryId: 1,
  ref: 'dev',
  sha: 'abc123',
  content: _catalogYaml,
);

Workspace _workspace(List<String> workflows) => Workspace(
  id: 'workspace-1',
  name: 'Example',
  organizationId: 'org-1',
  environment: 'dev',
  githubInstallationId: 12,
  repositories: const ['acme-co/example-app'],
  projects: const [],
  workflows: workflows,
  artifactStorage: null,
);

Map<String, Object?> _host({
  String id = 'gpu-host-1',
  String health = 'ok',
  bool drain = false,
  List<String> capabilities = const ['runtime-docker', 'open-jev-9b'],
}) => {
  'id': id,
  'health': health,
  'drain': drain,
  'capabilities': capabilities,
};

Map<String, Object?> _snapshot({
  bool stale = false,
  Object? hosts = const <Object?>[],
}) => {'stale': stale, 'hosts': hosts};

void main() {
  group('evaluateClassificationRuntime', () {
    test('is unknown before any fleet report exists', () {
      expect(
        evaluateClassificationRuntime(null),
        ClassificationRuntimeStatus.unknown,
      );
    });

    test('is unknown when the only report is stale, even if it once '
        'advertised the runtime', () {
      expect(
        evaluateClassificationRuntime(_snapshot(stale: true, hosts: [_host()])),
        ClassificationRuntimeStatus.unknown,
      );
    });

    test('is unknown when the report has no readable host list', () {
      expect(
        evaluateClassificationRuntime(_snapshot(hosts: 'not-a-list')),
        ClassificationRuntimeStatus.unknown,
      );
    });

    test('is available when a fresh healthy host advertises the runtime', () {
      expect(
        evaluateClassificationRuntime(
          _snapshot(
            hosts: [
              _host(id: 'host-1', capabilities: []),
              _host(),
            ],
          ),
        ),
        ClassificationRuntimeStatus.available,
      );
    });

    test('is unavailable when no fresh host advertises the runtime', () {
      expect(
        evaluateClassificationRuntime(
          _snapshot(
            hosts: [
              _host(capabilities: ['runtime-docker', 'nvidia-gpu']),
            ],
          ),
        ),
        ClassificationRuntimeStatus.unavailable,
      );
    });

    test('ignores drained and unhealthy hosts', () {
      for (final host in [
        _host(drain: true),
        _host(health: 'unhealthy'),
        _host(health: 'degraded'),
        _host(health: 'unknown'),
      ]) {
        expect(
          evaluateClassificationRuntime(_snapshot(hosts: [host])),
          ClassificationRuntimeStatus.unavailable,
          reason: '$host',
        );
      }
    });

    test('is unavailable for a fresh report with no hosts', () {
      expect(
        evaluateClassificationRuntime(_snapshot()),
        ClassificationRuntimeStatus.unavailable,
      );
    });
  });

  group('ClassificationRuntimeGate', () {
    test('reads one snapshot per organization within the TTL', () async {
      var now = DateTime.utc(2026, 10, 31, 12);
      final reads = <String>[];
      final gate = ClassificationRuntimeGate(
        reader: (organizationId) async {
          reads.add(organizationId);
          return _snapshot(hosts: [_host()]);
        },
        clock: () => now,
      );

      expect(await gate.status('org-1'), ClassificationRuntimeStatus.available);
      expect(await gate.status('org-1'), ClassificationRuntimeStatus.available);
      now = now.add(const Duration(seconds: 59));
      await gate.status('org-1');
      expect(reads, ['org-1']);

      now = now.add(const Duration(seconds: 1));
      await gate.status('org-1');
      await gate.status('org-2');
      expect(reads, ['org-1', 'org-1', 'org-2']);
    });

    test('shares one in-flight read between concurrent callers', () async {
      final pending = Completer<Map<String, Object?>?>();
      var reads = 0;
      final gate = ClassificationRuntimeGate(
        reader: (_) {
          reads++;
          return pending.future;
        },
      );

      final first = gate.status('org-1');
      final second = gate.status('org-1');
      pending.complete(_snapshot(hosts: [_host()]));

      expect(await first, ClassificationRuntimeStatus.available);
      expect(await second, ClassificationRuntimeStatus.available);
      expect(reads, 1);
    });

    test('a failed read is unknown, not unavailable', () async {
      final gate = ClassificationRuntimeGate(
        reader: (_) async => throw StateError('firestore unavailable'),
      );

      expect(await gate.status('org-1'), ClassificationRuntimeStatus.unknown);
    });

    test('does not read without an organization', () async {
      var reads = 0;
      final gate = ClassificationRuntimeGate(
        reader: (_) async {
          reads++;
          return _snapshot(hosts: [_host()]);
        },
      );

      expect(await gate.status(''), ClassificationRuntimeStatus.unknown);
      expect(reads, 0);
    });

    test('a deployment that receives no capacity reports is not reported, '
        'never unknown', () async {
      expect(
        await ClassificationRuntimeGate().status('org-1'),
        ClassificationRuntimeStatus.notReported,
      );
      expect(
        await ClassificationRuntimeGate().status(''),
        ClassificationRuntimeStatus.notReported,
      );
    });
  });

  group('runner capacity provider setting', () {
    test('parses the two supported providers', () {
      expect(
        parseRunnerCapacityProvider('fleet'),
        RunnerCapacityProvider.fleet,
      );
      expect(parseRunnerCapacityProvider('none'), RunnerCapacityProvider.none);
      expect(
        parseRunnerCapacityProvider(' none '),
        RunnerCapacityProvider.none,
      );
    });

    test('an unsupported value stops startup by naming the setting', () {
      for (final value in ['', 'Fleet', 'github', 'off']) {
        expect(
          () => parseRunnerCapacityProvider(value),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('II_OS_RUNNER_CAPACITY_PROVIDER'),
            ),
          ),
          reason: value,
        );
      }
    });

    test('fleet reads organization reports; none configures no reader', () {
      Future<Map<String, Object?>?> reports(String _) async => null;

      expect(
        classificationRuntimeGateFor(
          RunnerCapacityProvider.fleet,
          fleetReports: reports,
        ).reader,
        same(reports),
      );
      expect(
        classificationRuntimeGateFor(
          RunnerCapacityProvider.none,
          fleetReports: reports,
        ).reader,
        isNull,
      );
    });
  });

  group('classification dispatch admission', () {
    Future<void> admit(ClassificationRuntimeGate gate) async =>
        requireClassificationRuntime(await gate.status('org-1'));

    final refused = throwsA(
      isA<ApiError>()
          .having((error) => error.status, 'status', 409)
          .having(
            (error) => error.code,
            'code',
            'classification_runtime_unavailable',
          ),
    );

    test('a deployment without capacity reports can dispatch, and reads '
        'nothing', () async {
      await expectLater(
        admit(
          classificationRuntimeGateFor(
            RunnerCapacityProvider.none,
            fleetReports: (_) async => fail('no report may be read'),
          ),
        ),
        completes,
      );
    });

    test('a configured reader with no host advertising the model still '
        'refuses', () async {
      await expectLater(
        admit(
          ClassificationRuntimeGate(
            reader: (_) async => _snapshot(
              hosts: [
                _host(capabilities: ['runtime-docker']),
              ],
            ),
          ),
        ),
        refused,
      );
    });

    test('a configured reader whose organization never reported still '
        'refuses', () async {
      await expectLater(
        admit(ClassificationRuntimeGate(reader: (_) async => null)),
        refused,
      );
    });

    test('a capacity read error still refuses', () async {
      await expectLater(
        admit(
          ClassificationRuntimeGate(
            reader: (_) async => throw StateError('store unavailable'),
          ),
        ),
        refused,
      );
    });
  });

  group('classification templates', () {
    test('only classification- workflows carry a runtime requirement', () {
      expect(isClassificationWorkflow('classification-open-jev-9b'), isTrue);
      expect(isClassificationWorkflow('image-create'), isFalse);
      expect(isClassificationWorkflow('video-classification'), isFalse);
    });

    test('an available runtime keeps the workspace selection decision', () {
      final template = applyClassificationRuntime({
        'enabled': true,
        'disabledReason': '',
      }, ClassificationRuntimeStatus.available);

      expect(template['enabled'], isTrue);
      expect(template['disabledReason'], '');
      expect(template['runtime'], {
        'status': 'available',
        'requiredCapabilities': ['open-jev-9b'],
      });
    });

    test('a missing runtime disables a selected template with a pending '
        'reason', () {
      final unavailable = applyClassificationRuntime({
        'enabled': true,
        'disabledReason': '',
      }, ClassificationRuntimeStatus.unavailable);
      final unknown = applyClassificationRuntime({
        'enabled': true,
        'disabledReason': '',
      }, ClassificationRuntimeStatus.unknown);

      expect(unavailable['enabled'], isFalse);
      expect(
        unavailable['disabledReason'],
        'No runner has the classification model installed yet.',
      );
      expect((unavailable['runtime']! as Map)['status'], 'unavailable');
      expect(unknown['enabled'], isFalse);
      expect(
        unknown['disabledReason'],
        'Waiting for your runners to confirm the classification model is '
        'installed.',
      );
      expect((unknown['runtime']! as Map)['status'], 'unknown');
      for (final reason in [
        unavailable['disabledReason'],
        unknown['disabledReason'],
      ]) {
        expect(reason, isNot(contains('Fleet')));
      }
    });

    test('a deployment without capacity reports offers a selected template '
        'and leaves the model check to the run', () {
      final template = applyClassificationRuntime({
        'enabled': true,
        'disabledReason': '',
      }, ClassificationRuntimeStatus.notReported);

      expect(template['enabled'], isTrue);
      expect(template['disabledReason'], '');
      expect((template['runtime']! as Map)['status'], 'notReported');
    });

    test('the workspace selection reason wins over the runtime reason', () {
      final template = applyClassificationRuntime({
        'enabled': false,
        'disabledReason': 'Not enabled for this workspace.',
      }, ClassificationRuntimeStatus.unavailable);

      expect(template['enabled'], isFalse);
      expect(template['disabledReason'], 'Not enabled for this workspace.');
      expect((template['runtime']! as Map)['status'], 'unavailable');
    });

    test('dispatch is refused unless the runtime is available or capacity '
        'is not reported', () {
      requireClassificationRuntime(ClassificationRuntimeStatus.available);
      requireClassificationRuntime(ClassificationRuntimeStatus.notReported);
      for (final status in [
        ClassificationRuntimeStatus.unavailable,
        ClassificationRuntimeStatus.unknown,
      ]) {
        expect(
          () => requireClassificationRuntime(status),
          throwsA(
            isA<ApiError>()
                .having((error) => error.status, 'status', 409)
                .having(
                  (error) => error.code,
                  'code',
                  'classification_runtime_unavailable',
                ),
          ),
        );
      }
    });
  });

  group('buildWorkflowTemplates', () {
    test('the classification entry parses with the shipped catalog parser', () {
      final workflow = _catalog().find('classification-open-jev-9b')!;

      expect(workflow.inputs['state']!.maxLength, 8000);
      expect(workflow.inputs['questions']!.maxLength, 32000);
      expect(workflow.outputs.single.kind, 'decisions');
      expect(workflow.outputs.single.contentTypes, ['application/json']);
      expect(workflow.workType, JobWorkType.other);
    });

    test('narrows only classification templates by the runtime status', () {
      final templates = buildWorkflowTemplates(
        _workspace([
          'acme-co/example-app#image-create',
          'acme-co/example-app#classification-open-jev-9b',
        ]),
        [_catalog()],
        classificationRuntime: ClassificationRuntimeStatus.unavailable,
      );
      final byWorkflow = {
        for (final template in templates) template['workflowId']: template,
      };

      expect(byWorkflow['image-create']!['enabled'], isTrue);
      expect(byWorkflow['image-create']!.containsKey('runtime'), isFalse);
      final classification = byWorkflow['classification-open-jev-9b']!;
      expect(classification['enabled'], isFalse);
      expect(
        classification['disabledReason'],
        classificationRuntimeUnavailableReason,
      );
      expect(classification['runtime'], {
        'status': 'unavailable',
        'requiredCapabilities': ['open-jev-9b'],
      });
    });

    test('an installed runtime enables a selected classification template', () {
      final classification = buildWorkflowTemplates(
        _workspace(['acme-co/example-app#classification-open-jev-9b']),
        [_catalog()],
        classificationRuntime: ClassificationRuntimeStatus.available,
      ).singleWhere((t) => t['workflowId'] == 'classification-open-jev-9b');

      expect(classification['enabled'], isTrue);
      expect(classification['disabledReason'], '');
      expect((classification['runtime']! as Map)['status'], 'available');
    });

    test('a missing status is reported as unknown, never as available', () {
      final classification = buildWorkflowTemplates(
        _workspace(['acme-co/example-app#classification-open-jev-9b']),
        [_catalog()],
      ).singleWhere((t) => t['workflowId'] == 'classification-open-jev-9b');

      expect(classification['enabled'], isFalse);
      expect((classification['runtime']! as Map)['status'], 'unknown');
    });
  });
}
