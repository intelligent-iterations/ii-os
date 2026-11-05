import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/classification_decisions.dart';
import 'package:ii_os/models/classification_questions.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/repositories/classification_result_repository.dart';
import 'package:ii_os/repositories/job_repository.dart';
import 'package:ii_os/repositories/workflow_template_repository.dart';
import 'package:ii_os/services/api_client.dart';
import 'package:ii_os/view_models/classification_view_model.dart';
import 'package:ii_os/view_models/playground_view_model.dart';

WorkflowTemplateModel _template({
  bool enabled = true,
  WorkflowRuntimeStatus? runtime = WorkflowRuntimeStatus.available,
}) => WorkflowTemplateModel(
  id: 'acme/app#classification-open-jev-9b',
  workflowId: 'classification-open-jev-9b',
  version: '1',
  displayName: 'Open JEV 9B Classification',
  model: 'autotrust/JEV-9B',
  repository: 'acme/app',
  enabled: enabled,
  disabledReason: enabled ? '' : 'Waiting for the open JEV runtime image.',
  runtime: runtime == null ? null : WorkflowRuntimeRequirement(status: runtime),
);

final class _Templates implements WorkflowTemplateRepository {
  _Templates(this.templates, {this.fails = false});

  final List<WorkflowTemplateModel> templates;
  final bool fails;
  final prefixes = <String?>[];

  @override
  Future<List<WorkflowTemplateModel>> list(
    String workspaceId, {
    String? workflowIdPrefix,
  }) async {
    prefixes.add(workflowIdPrefix);
    if (fails) throw const ApiFailure('network', 'offline');
    return templates;
  }
}

final class _Jobs implements JobRepository {
  _Jobs(this.details, {this.submitted, this.submitFailure});

  final List<JsonMap> details;
  final JsonMap? submitted;
  final ApiFailure? submitFailure;
  final submissions = <JobSubmission>[];

  @override
  Future<JsonMap> submit(String workspaceId, JobSubmission submission) async {
    submissions.add(submission);
    if (submitFailure != null) throw submitFailure!;
    return submitted ?? {'jobId': 'job-1', 'status': 'dispatched'};
  }

  @override
  Future<JsonMap> detail(String workspaceId, String jobId) async => {
    'job': details.removeAt(0),
  };

  @override
  Future<JobListing> list(String workspaceId) async => JobListing.empty;
}

final class _Results implements ClassificationResultRepository {
  _Results({this.fails = false});

  final bool fails;
  final reads = <JsonMap>[];
  final consumed = <String>[];

  @override
  Future<ClassificationDecisions> readDecisions({
    required String workspaceId,
    required String jobId,
    required String expectedBucket,
    required JsonMap artifact,
  }) async {
    reads.add(artifact);
    if (fails) throw const FormatException('digest mismatch');
    return const ClassificationDecisions(
      answers: [ClassificationYesNoAnswer('q1', yes: 0.9)],
      run: ClassificationRunFacts(
        model: 'autotrust/JEV-9B',
        revision: '7ac669b8fb476ba926491e3d1c39f9330d68dbed',
        decideSeconds: 0.4,
        loadSeconds: 38,
        stateTokens: 12,
        stateTruncated: false,
        device: 'Example 24 GB GPU',
      ),
      inputTokens: 40,
    );
  }

  @override
  Future<void> consumeGhostJob({
    required String workspaceId,
    required String jobId,
  }) async => consumed.add(jobId);
}

const _artifact = {
  'path': 'workspaces/workspace-1/runs/job-1/open-jev/decisions.json',
  'content_type': 'application/json',
  'size_bytes': 512,
  'sha256': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'generation': '7',
};

ClassificationViewModel _viewModel({
  required _Templates templates,
  required _Jobs jobs,
  _Results? results,
  bool ghostMode = false,
  List<String>? finished,
}) => ClassificationViewModel(
  templates: templates,
  jobs: jobs,
  results: results ?? _Results(),
  workspaceId: 'workspace-1',
  expectedBucket: 'workspace-bucket',
  ghostMode: ghostMode,
  onFinished: () async => finished?.add('finished'),
);

void main() {
  group('ClassificationViewModel', () {
    test(
      'cannot submit until the runtime is installed and the form is valid',
      () async {
        final blocked = _viewModel(
          templates: _Templates([_template(enabled: false)]),
          jobs: _Jobs([]),
        );
        await blocked.load();
        blocked.setStateText('I was charged twice.');
        expect(blocked.showsUnavailableNotice, isTrue);
        expect(blocked.canSubmit, isFalse);

        final ready = _viewModel(
          templates: _Templates([_template()]),
          jobs: _Jobs([]),
        );
        await ready.load();
        expect(ready.availability, ClassificationAvailability.available);
        expect(ready.canSubmit, isFalse, reason: 'no text yet');
        ready.setStateText('I was charged twice.');
        expect(ready.canSubmit, isTrue);
      },
    );

    test('explains a disabled launch beside the control', () async {
      final blocked = _viewModel(
        templates: _Templates([_template(enabled: false)]),
        jobs: _Jobs([]),
      );
      expect(blocked.launchBlockedReason, isNull, reason: 'not loaded yet');
      await blocked.load();
      expect(
        blocked.launchBlockedReason,
        'Waiting for the open JEV runtime image.',
      );

      final ready = _viewModel(
        templates: _Templates([_template()]),
        jobs: _Jobs([]),
      );
      await ready.load();
      expect(ready.launchBlockedReason, 'Add the text to classify.');
      ready
        ..setStateText('text')
        ..renameQuestion('question-1', 'Bad Name');
      expect(
        ready.launchBlockedReason,
        'Fix the highlighted question before classifying.',
      );
      ready.renameQuestion('question-1', 'tone');
      expect(ready.launchBlockedReason, isNull);
    });

    test('submits, follows the job, and reads the verified result', () async {
      final jobs = _Jobs([
        {'jobId': 'job-1', 'status': 'running'},
        {
          'jobId': 'job-1',
          'status': 'completed',
          'artifacts': [_artifact],
        },
      ]);
      final results = _Results();
      final finished = <String>[];
      final viewModel = _viewModel(
        templates: _Templates([_template()]),
        jobs: jobs,
        results: results,
        finished: finished,
      );
      addTearDown(viewModel.dispose);
      await viewModel.load();
      viewModel
        ..setStateText('  I was charged twice.  ')
        ..setKind('question-1', ClassificationQuestionKind.yesNo)
        ..setInstructions('question-1', 'Is this about billing?');

      await viewModel.submit();
      expect(viewModel.phase, ClassificationRunPhase.running);
      final submission = jobs.submissions.single;
      expect(submission.workflowKey, 'acme/app#classification-open-jev-9b');
      expect(submission.pageSlug, 'playground');
      expect(submission.input['state'], 'I was charged twice.');
      expect(
        submission.input['questions'],
        '{"q1":{"type":"noul","instructions":"Is this about billing?"}}',
      );

      await viewModel.refreshJob();
      expect(viewModel.phase, ClassificationRunPhase.running);
      await viewModel.refreshJob();

      expect(viewModel.phase, ClassificationRunPhase.completed);
      expect(results.reads.single, _artifact);
      expect(viewModel.decisions!.answers.single.name, 'q1');
      expect(finished, ['finished']);
      expect(results.consumed, isEmpty, reason: 'not a Ghost-mode run');
    });

    test('stops watching after the active-operation ceiling and resumes on '
        'request', () async {
      var now = DateTime.utc(2026, 10, 31, 12);
      final jobs = _Jobs([
        {'jobId': 'job-1', 'status': 'queued'},
        {'jobId': 'job-1', 'status': 'queued'},
        {
          'jobId': 'job-1',
          'status': 'completed',
          'artifacts': [_artifact],
        },
      ]);
      final viewModel = ClassificationViewModel(
        templates: _Templates([_template()]),
        jobs: jobs,
        results: _Results(),
        workspaceId: 'workspace-1',
        expectedBucket: 'workspace-bucket',
        clock: () => now,
      );
      addTearDown(viewModel.dispose);
      await viewModel.load();
      viewModel.setStateText('text');
      await viewModel.submit();
      await viewModel.refreshJob();
      expect(jobs.details, hasLength(2));

      now = now.add(classificationWatchCeiling);
      await viewModel.refreshJob();
      expect(viewModel.phase, ClassificationRunPhase.paused);
      expect(viewModel.watching, isFalse);
      expect(jobs.details, hasLength(2), reason: 'no read after the ceiling');

      await viewModel.resumeWatching();
      expect(viewModel.phase, ClassificationRunPhase.running);
      expect(viewModel.watching, isTrue);
      await viewModel.refreshJob();
      expect(viewModel.phase, ClassificationRunPhase.completed);
    });

    test('a failed run shows a mapped message, never the raw code', () async {
      final viewModel = _viewModel(
        templates: _Templates([_template()]),
        jobs: _Jobs(
          [],
          submitted: {
            'jobId': 'job-1',
            'status': 'failed',
            'workflowResult': {
              'errorCode': 'classification_fleet_allocation_failed',
            },
          },
        ),
      );
      await viewModel.load();
      viewModel.setStateText('text');

      await viewModel.submit();

      expect(viewModel.phase, ClassificationRunPhase.failed);
      expect(viewModel.failureMessage, contains('No GPU host'));
      expect(viewModel.failureMessage, isNot(contains('classification_')));
    });

    test('a refused dispatch maps the server code', () async {
      final viewModel = _viewModel(
        templates: _Templates([_template()]),
        jobs: _Jobs(
          [],
          submitFailure: const ApiFailure(
            'classification_runtime_unavailable',
            'Waiting for the open JEV runtime image.',
            statusCode: 409,
          ),
        ),
      );
      await viewModel.load();
      viewModel.setStateText('text');

      await viewModel.submit();

      expect(viewModel.phase, ClassificationRunPhase.failed);
      expect(
        viewModel.failureMessage,
        'No runner has the classification model installed yet.',
      );
    });

    test('a run whose runner lacks the model says so', () async {
      final viewModel = _viewModel(
        templates: _Templates([
          _template(runtime: WorkflowRuntimeStatus.notReported),
        ]),
        jobs: _Jobs(
          [],
          submitted: {
            'jobId': 'job-1',
            'status': 'failed',
            'workflowResult': {'errorCode': 'classification_model_missing'},
          },
        ),
      );
      await viewModel.load();
      viewModel.setStateText('text');

      await viewModel.submit();

      expect(viewModel.phase, ClassificationRunPhase.failed);
      expect(viewModel.failureMessage, contains('not installed on your GPU'));
    });

    test('a deployment without capacity reports can launch and does not '
        'claim the runtime is installed', () async {
      final viewModel = _viewModel(
        templates: _Templates([
          _template(runtime: WorkflowRuntimeStatus.notReported),
        ]),
        jobs: _Jobs([]),
      );
      await viewModel.load();
      viewModel.setStateText('I was charged twice.');

      expect(viewModel.availability, ClassificationAvailability.checkedOnRun);
      expect(viewModel.showsUnavailableNotice, isFalse);
      expect(viewModel.canSubmit, isTrue);
    });

    test(
      'an unverifiable result fails and releases a Ghost-mode run',
      () async {
        final results = _Results(fails: true);
        final viewModel = _viewModel(
          templates: _Templates([_template()]),
          jobs: _Jobs(
            [],
            submitted: {
              'jobId': 'job-1',
              'status': 'completed',
              'ghostMode': true,
              'artifacts': [_artifact],
            },
          ),
          results: results,
          ghostMode: true,
        );
        await viewModel.load();
        viewModel.setStateText('text');

        await viewModel.submit();

        expect(viewModel.phase, ClassificationRunPhase.failed);
        expect(viewModel.failureMessage, contains('could not be verified'));
        expect(jobsGhost(viewModel), isTrue);
        expect(results.consumed, ['job-1']);
      },
    );

    test('edits questions without losing their identity', () async {
      final viewModel = _viewModel(
        templates: _Templates([_template()]),
        jobs: _Jobs([]),
      );
      viewModel
        ..addQuestion()
        ..renameQuestion('question-2', 'tone')
        ..addOption('question-2')
        ..setOptionName('question-2', 2, 'maybe')
        ..removeOption('question-2', 0)
        ..removeQuestion('question-1');

      expect(viewModel.questions.single.key, 'question-2');
      expect(viewModel.questions.single.name, 'tone');
      expect(viewModel.questions.single.options.map((option) => option.name), [
        'no',
        'maybe',
      ]);
      viewModel.removeQuestion('question-2');
      expect(viewModel.questions, hasLength(1), reason: 'keeps one question');
    });
  });

  group('PlaygroundViewModel', () {
    test(
      'reads availability once, narrowed to classification templates',
      () async {
        final templates = _Templates([_template()]);
        final viewModel = PlaygroundViewModel(
          templates: templates,
          workspaceId: 'workspace-1',
        );
        expect(viewModel.classification, ClassificationAvailability.checking);

        await viewModel.load();

        expect(viewModel.classification, ClassificationAvailability.available);
        expect(templates.prefixes, ['classification-']);
      },
    );

    test(
      'distinguishes not installed, unconfirmed, and not configured',
      () async {
        Future<ClassificationAvailability> of(_Templates templates) async {
          final viewModel = PlaygroundViewModel(
            templates: templates,
            workspaceId: 'w',
          );
          await viewModel.load();
          return viewModel.classification;
        }

        expect(
          await of(
            _Templates([_template(runtime: WorkflowRuntimeStatus.unavailable)]),
          ),
          ClassificationAvailability.notInstalled,
        );
        expect(
          await of(
            _Templates([_template(runtime: WorkflowRuntimeStatus.unknown)]),
          ),
          ClassificationAvailability.unconfirmed,
        );
        expect(
          await of(_Templates([_template(runtime: null)])),
          ClassificationAvailability.unconfirmed,
        );
        expect(
          await of(_Templates(const [])),
          ClassificationAvailability.notConfigured,
        );
        expect(
          await of(
            _Templates([_template(runtime: WorkflowRuntimeStatus.notReported)]),
          ),
          ClassificationAvailability.checkedOnRun,
        );
        expect(
          await of(_Templates(const [], fails: true)),
          ClassificationAvailability.unconfirmed,
        );
      },
    );
  });
}

bool jobsGhost(ClassificationViewModel viewModel) =>
    viewModel.job?['ghostMode'] == true;
