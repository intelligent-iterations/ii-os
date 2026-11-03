import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/repositories/job_repository.dart';
import 'package:ii_os/repositories/workflow_template_repository.dart';
import 'package:ii_os/services/api_client.dart';
import 'package:ii_os/view_models/narration_generation_view_model.dart';

import 'prompt_enhancement_stubs.dart';

final class _StubTemplates implements WorkflowTemplateRepository {
  _StubTemplates({this.templates = const [], this.failWith});

  final List<WorkflowTemplateModel> templates;
  final Object? failWith;

  String? lastPrefix;

  @override
  Future<List<WorkflowTemplateModel>> list(
    String workspaceId, {
    String? workflowIdPrefix,
  }) async {
    if (failWith != null) throw failWith!;
    lastPrefix = workflowIdPrefix;
    return templates;
  }
}

final class _StubJobs implements JobRepository {
  @override
  Future<JobListing> list(String workspaceId) async => JobListing.empty;

  @override
  Future<JsonMap> detail(String workspaceId, String jobId) async => const {};

  _StubJobs({this.failWith});

  final Object? failWith;
  final List<JsonMap> submitted = [];

  @override
  Future<JsonMap> submit(String workspaceId, JobSubmission submission) async {
    if (failWith != null) throw failWith!;
    submitted.add(submission.body(workspaceId));
    return const {'jobId': 'job_1', 'status': 'requested'};
  }
}

WorkflowTemplateModel _template(
  String id, {
  bool enabled = true,
  String workflowId = 'narration-create-chatterbox-tts',
  String disabledReason = '',
  List<WorkflowRuntimeEstimateModel> runtimeEstimates = const [],
}) => WorkflowTemplateModel(
  id: id,
  workflowId: workflowId,
  version: '1',
  displayName: id,
  model: id,
  repository: 'acme/example',
  enabled: enabled,
  disabledReason: disabledReason,
  runtimeEstimates: runtimeEstimates,
);

NarrationGenerationViewModel _viewModel({
  required WorkflowTemplateRepository templates,
  required JobRepository jobs,
  bool ghostMode = false,
  Future<void> Function()? onSubmitted,
}) => NarrationGenerationViewModel(
  promptEnhancements: StubPromptEnhancements(),
  templates: templates,
  jobs: jobs,
  workspaceId: 'ws_test',
  ghostMode: ghostMode,
  onSubmitted: onSubmitted,
);

void main() {
  test('exposes the selected narration runtime estimate', () async {
    final viewModel = _viewModel(
      templates: _StubTemplates(
        templates: [
          _template(
            'narration-a',
            runtimeEstimates: const [
              WorkflowRuntimeEstimateModel(
                selector: {},
                durationInput: '',
                baselineOutputSeconds: 0,
                baselineRuntimeSeconds: 15,
                hardware: '24 GB GPU',
                measuredAt: '2026-08-24',
              ),
            ],
          ),
        ],
      ),
      jobs: _StubJobs(),
    );

    await viewModel.load();

    expect(viewModel.runtimeEstimate?.estimatedSeconds, 15);
  });

  group('load', () {
    test('asks the repository for narration workflows only', () async {
      final templates = _StubTemplates(templates: [_template('narration-a')]);
      final viewModel = _viewModel(templates: templates, jobs: _StubJobs());

      await viewModel.load();

      expect(templates.lastPrefix, 'narration-create');
      expect(viewModel.loadingTemplates, isFalse);
      expect(viewModel.hasError, isFalse);
    });

    test(
      'surfaces the reason when no narration workflow is runnable',
      () async {
        final viewModel = _viewModel(
          templates: _StubTemplates(
            templates: [
              _template(
                'blocked',
                enabled: false,
                disabledReason: 'Waiting for narration workflow on dev',
              ),
            ],
          ),
          jobs: _StubJobs(),
        );

        await viewModel.load();

        expect(viewModel.canSubmit, isFalse);
        expect(viewModel.showsUnavailableNotice, isTrue);
        expect(
          viewModel.selectedTemplate?.disabledReason,
          'Waiting for narration workflow on dev',
        );
      },
    );

    test('records a load failure without throwing', () async {
      final viewModel = _viewModel(
        templates: _StubTemplates(
          failWith: const ApiFailure('boom', 'Templates are offline.'),
        ),
        jobs: _StubJobs(),
      );

      await viewModel.load();

      expect(viewModel.hasError, isTrue);
      expect(viewModel.loadingTemplates, isFalse);
      expect(viewModel.templates, isEmpty);
    });
  });

  group('submit', () {
    Future<(NarrationGenerationViewModel, _StubJobs)> ready({
      List<WorkflowTemplateModel>? templates,
    }) async {
      final jobs = _StubJobs();
      final viewModel = _viewModel(
        templates: _StubTemplates(
          templates: templates ?? [_template('narration-a')],
        ),
        jobs: jobs,
      );
      await viewModel.load();
      return (viewModel, jobs);
    }

    test('posts text, voice model, language, seed, and deep link', () async {
      final (viewModel, jobs) = await ready();

      final job = await viewModel.submit(
        text: '  Read this cleanly.  ',
        voiceModel: 'chatterbox-turbo',
        language: 'English',
        seed: '42',
      );

      expect(job, isNotNull);
      expect(jobs.submitted, hasLength(1));
      final posted = jobs.submitted.single;
      expect(posted['workflowKey'], 'narration-a');
      expect(posted['notificationDeepLink'], '/workspaces/ws_test/narration');
      final input = posted['input']! as JsonMap;
      expect(input['text'], 'Read this cleanly.');
      expect(input['voice_model'], 'chatterbox-turbo');
      expect(input['language'], 'English');
      expect(input['seed'], 42);
    });

    test('uses narration defaults and omits a blank seed', () async {
      final (viewModel, jobs) = await ready();

      await viewModel.submit(
        text: 'hello',
        voiceModel: '',
        language: '',
        seed: '   ',
      );

      final input = jobs.submitted.single['input']! as JsonMap;
      expect(input['voice_model'], 'chatterbox-turbo');
      expect(input['language'], 'English');
      expect(input.containsKey('seed'), isFalse);
    });

    test('posts voice clone reference asset only with consent', () async {
      final (viewModel, jobs) = await ready();

      final job = await viewModel.submit(
        text: 'hello',
        voiceModel: 'chatterbox-turbo',
        language: 'English',
        seed: '',
        voiceReferenceAssetId: '123e4567-e89b-42d3-a456-426614174000',
        voiceCloneConsent: true,
      );

      expect(job, isNotNull);
      final input = jobs.submitted.single['input']! as JsonMap;
      expect(
        input['voice_reference_asset_id'],
        '123e4567-e89b-42d3-a456-426614174000',
      );
      expect(input['voice_clone_consent'], isTrue);
    });

    test('marks a Ghost narration for ephemeral delivery', () async {
      final jobs = _StubJobs();
      final viewModel = _viewModel(
        templates: _StubTemplates(templates: [_template('narration-a')]),
        jobs: jobs,
        ghostMode: true,
      );
      await viewModel.load();

      await viewModel.submit(
        text: 'private draft',
        voiceModel: 'chatterbox-turbo',
        language: 'English',
        seed: '',
      );

      expect(jobs.submitted.single['ghostMode'], isTrue);
      expect(
        jobs.submitted.single.containsKey('notificationDeepLink'),
        isFalse,
      );
    });

    test('rejects voice clone references without consent', () async {
      final (viewModel, jobs) = await ready();

      final job = await viewModel.submit(
        text: 'hello',
        voiceModel: 'chatterbox-turbo',
        language: 'English',
        seed: '',
        voiceReferenceAssetId: '123e4567-e89b-42d3-a456-426614174000',
      );

      expect(job, isNull);
      expect(jobs.submitted, isEmpty);
      expect(viewModel.modelError, isA<FormatException>());
    });

    test('rejects invalid input before calling the repository', () async {
      final (viewModel, jobs) = await ready();

      final job = await viewModel.submit(
        text: '   ',
        voiceModel: 'chatterbox-turbo',
        language: 'English',
        seed: '',
      );

      expect(job, isNull);
      expect(jobs.submitted, isEmpty);
      expect(viewModel.modelError, isA<FormatException>());
    });

    test('rejects unavailable voice model values', () async {
      final (viewModel, jobs) = await ready();

      final job = await viewModel.submit(
        text: 'hello',
        voiceModel: 'qwen3-tts',
        language: 'English',
        seed: '',
      );

      expect(job, isNull);
      expect(jobs.submitted, isEmpty);
      expect(viewModel.modelError, isA<FormatException>());
    });

    test('notifies the caller after successful submission', () async {
      var refreshes = 0;
      final viewModel = _viewModel(
        templates: _StubTemplates(templates: [_template('narration-a')]),
        jobs: _StubJobs(),
        onSubmitted: () async => refreshes++,
      );
      await viewModel.load();

      await viewModel.submit(
        text: 'hello',
        voiceModel: 'chatterbox-turbo',
        language: 'English',
        seed: '',
      );

      expect(refreshes, 1);
      expect(viewModel.submitting, isFalse);
      expect(viewModel.submittedJob, isNotNull);
    });

    test('records a submission failure and clears busy', () async {
      final viewModel = _viewModel(
        templates: _StubTemplates(templates: [_template('narration-a')]),
        jobs: _StubJobs(
          failWith: const ApiFailure('boom', 'The runner is offline.'),
        ),
      );
      await viewModel.load();

      final job = await viewModel.submit(
        text: 'hello',
        voiceModel: 'chatterbox-turbo',
        language: 'English',
        seed: '',
      );

      expect(job, isNull);
      expect(viewModel.hasError, isTrue);
      expect(viewModel.submitting, isFalse);
    });

    test('uploads voice references through workspace source assets', () async {
      final calls = <JsonMap>[];
      final viewModel = NarrationGenerationViewModel(
        promptEnhancements: StubPromptEnhancements(),
        templates: _StubTemplates(templates: [_template('narration-a')]),
        jobs: _StubJobs(),
        workspaceId: 'ws_test',
        expectedBucket: 'workspace-bucket',
        voiceReferenceUploader:
            ({
              required workspaceId,
              required expectedBucket,
              required filename,
              required bytes,
              required contentType,
              required ghostMode,
            }) async {
              calls.add({
                'workspaceId': workspaceId,
                'expectedBucket': expectedBucket,
                'filename': filename,
                'bytes': bytes,
                'contentType': contentType,
                'ghostMode': ghostMode,
              });
              return '123e4567-e89b-42d3-a456-426614174000';
            },
      );

      final assetId = await viewModel.uploadVoiceReference(
        filename: 'reference.wav',
        bytes: Uint8List.fromList([82, 73, 70, 70]),
        contentType: 'audio/wav',
      );

      expect(assetId, '123e4567-e89b-42d3-a456-426614174000');
      expect(calls, hasLength(1));
      expect(calls.single['workspaceId'], 'ws_test');
      expect(calls.single['expectedBucket'], 'workspace-bucket');
      expect(calls.single['filename'], 'reference.wav');
      expect(calls.single['contentType'], 'audio/wav');
      expect(calls.single['ghostMode'], isFalse);
    });
  });

  test('declares only the production-safe narration model for the UI', () {
    expect(narrationVoiceModels, {'chatterbox-turbo'});
  });
}
