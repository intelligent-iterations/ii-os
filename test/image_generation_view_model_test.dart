import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/image_workflow_capabilities.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/repositories/job_repository.dart';
import 'package:ii_os/repositories/prompt_enhancement_repository.dart';
import 'package:ii_os/repositories/source_asset_repository.dart';
import 'package:ii_os/repositories/workflow_template_repository.dart';
import 'package:ii_os/services/api_client.dart';
import 'package:ii_os/view_models/image_generation_view_model.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';

import 'prompt_enhancement_stubs.dart';

final _png = Uint8List.fromList(const [
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
]);

/// Stands in for the network at the repository seam. The wire format itself
/// is covered by `parseWorkflowTemplates` below.
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

final class _StubSourceAssets implements SourceAssetRepository {
  final List<String> filenames = [];

  @override
  Future<String> upload({
    required String workspaceId,
    required String filename,
    required Uint8List bytes,
    required String contentType,
    required String expectedBucket,
    bool ghostMode = false,
  }) async {
    filenames.add(filename);
    return 'asset-${filenames.length}';
  }
}

WorkflowTemplateModel _template(
  String id, {
  bool enabled = true,
  String workflowId = 'image-create-flux2-klein',
  String disabledReason = '',
  Map<String, WorkflowInputModel> inputs = const {
    'model': WorkflowInputModel(type: 'string', required: true),
    'prompt': WorkflowInputModel(type: 'string', required: true),
    'aspect_ratio': WorkflowInputModel(type: 'string', required: true),
    'seed': WorkflowInputModel(type: 'number', required: false),
  },
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
  inputs: inputs,
  runtimeEstimates: runtimeEstimates,
);

ImageGenerationViewModel _viewModel({
  required WorkflowTemplateRepository templates,
  required JobRepository jobs,
  SourceAssetRepository? sourceAssets,
  PromptEnhancementRepository? promptEnhancements,
  bool ghostMode = false,
  ImageGenerationMode initialMode = ImageGenerationMode.prompt,
  String? initialTemplateId,
  Future<void> Function()? onSubmitted,
}) => ImageGenerationViewModel(
  templates: templates,
  jobs: jobs,
  sourceAssets: sourceAssets ?? _StubSourceAssets(),
  promptEnhancements: promptEnhancements ?? StubPromptEnhancements(),
  workspaceId: 'ws_test',
  expectedBucket: 'workspace-bucket',
  ghostMode: ghostMode,
  initialMode: initialMode,
  initialTemplateId: initialTemplateId,
  onSubmitted: onSubmitted,
);

void main() {
  test('exposes the selected image workflow runtime estimate', () async {
    final viewModel = _viewModel(
      templates: _StubTemplates(
        templates: [
          _template(
            'image-a',
            runtimeEstimates: const [
              WorkflowRuntimeEstimateModel(
                selector: {},
                durationInput: '',
                baselineOutputSeconds: 0,
                baselineRuntimeSeconds: 45,
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

    expect(viewModel.runtimeEstimate?.estimatedSeconds, 45);
  });

  group('load', () {
    test('asks the repository for the image-create family only', () async {
      final templates = _StubTemplates(templates: [_template('image-a')]);
      final viewModel = _viewModel(templates: templates, jobs: _StubJobs());

      await viewModel.load();

      expect(templates.lastPrefix, 'image-create');
      expect(viewModel.loadingTemplates, isFalse);
      expect(viewModel.hasError, isFalse);
    });

    test('selects the first enabled template when none is chosen', () async {
      final viewModel = _viewModel(
        templates: _StubTemplates(
          templates: [
            _template('disabled', enabled: false),
            _template('enabled'),
          ],
        ),
        jobs: _StubJobs(),
      );

      await viewModel.load();

      expect(viewModel.selectedTemplate?.id, 'enabled');
      expect(viewModel.canSubmit, isTrue);
      expect(viewModel.showsUnavailableNotice, isFalse);
    });

    test('an explicit choice wins over the first enabled template', () async {
      final viewModel = _viewModel(
        templates: _StubTemplates(
          templates: [_template('first'), _template('second')],
        ),
        jobs: _StubJobs(),
      );
      await viewModel.load();

      viewModel.selectTemplate('second');

      expect(viewModel.selectedTemplate?.id, 'second');
    });

    test('shows only workflows for the selected creation mode', () async {
      final text = _template('text');
      final reference = _template(
        'reference',
        workflowId: 'image-create-reference-qwen-2511',
        inputs: const {
          'source_asset_id': WorkflowInputModel(type: 'string', required: true),
        },
      );
      final viewModel = _viewModel(
        templates: _StubTemplates(templates: [text, reference]),
        jobs: _StubJobs(),
      );

      await viewModel.load();
      expect(viewModel.templates, [text]);

      viewModel.setMode(ImageGenerationMode.references);
      expect(viewModel.templates, [reference]);
      expect(viewModel.selectedTemplate, reference);
    });

    test(
      'reference creation becomes actionable after image A is added',
      () async {
        final viewModel = _viewModel(
          templates: _StubTemplates(
            templates: [
              _template(
                'reference',
                inputs: const {
                  'source_asset_id': WorkflowInputModel(
                    type: 'string',
                    required: true,
                  ),
                },
              ),
            ],
          ),
          jobs: _StubJobs(),
          initialMode: ImageGenerationMode.references,
        );
        await viewModel.load();

        expect(viewModel.canSubmit, isFalse);
        viewModel.setReference(0, filename: 'main.png', bytes: _png);
        expect(viewModel.canSubmit, isTrue);
      },
    );

    test('surfaces the reason when nothing is runnable', () async {
      final viewModel = _viewModel(
        templates: _StubTemplates(
          templates: [
            _template(
              'blocked',
              enabled: false,
              disabledReason: 'Waiting for the workflow to land on dev',
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
        'Waiting for the workflow to land on dev',
      );
    });

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
    Future<(ImageGenerationViewModel, _StubJobs)> ready({
      List<WorkflowTemplateModel>? templates,
      ImageGenerationMode mode = ImageGenerationMode.prompt,
    }) async {
      final jobs = _StubJobs();
      final viewModel = _viewModel(
        templates: _StubTemplates(
          templates: templates ?? [_template('image-a')],
        ),
        jobs: jobs,
        initialMode: mode,
      );
      await viewModel.load();
      return (viewModel, jobs);
    }

    test('posts the prompt, ratio, seed, model input, and deep link', () async {
      final (viewModel, jobs) = await ready();

      final job = await viewModel.submit(
        prompt: '  a calm control room  ',
        aspectRatio: '16:9',
        seed: '42',
      );

      expect(job, isNotNull);
      expect(jobs.submitted, hasLength(1));
      final posted = jobs.submitted.single;
      expect(posted['workflowKey'], 'image-a');
      expect(posted['notificationDeepLink'], '/workspaces/ws_test/images');
      final input = posted['input']! as JsonMap;
      expect(input['prompt'], 'a calm control room');
      expect(input['aspect_ratio'], '16:9');
      expect(input['seed'], 42);
      expect(input['model'], 'flux2-klein');
    });

    test('uploads and submits ordered reference images', () async {
      final jobs = _StubJobs();
      final sourceAssets = _StubSourceAssets();
      final viewModel = _viewModel(
        templates: _StubTemplates(
          templates: [
            _template(
              'reference',
              workflowId: 'image-create-reference-qwen-2511',
              inputs: const {
                'mode': WorkflowInputModel(type: 'string', required: true),
                'source_asset_id': WorkflowInputModel(
                  type: 'string',
                  required: true,
                ),
                'source_asset_id_2': WorkflowInputModel(
                  type: 'string',
                  required: false,
                ),
                'source_asset_id_3': WorkflowInputModel(
                  type: 'string',
                  required: false,
                ),
                'prompt': WorkflowInputModel(type: 'string', required: true),
                'seed': WorkflowInputModel(type: 'number', required: false),
              },
            ),
          ],
        ),
        jobs: jobs,
        sourceAssets: sourceAssets,
        initialMode: ImageGenerationMode.references,
      );
      await viewModel.load();
      for (var index = 0; index < 3; index++) {
        expect(
          viewModel.setReference(
            index,
            filename: 'reference-$index.png',
            bytes: _png,
          ),
          isTrue,
        );
      }

      await viewModel.submit(
        prompt: 'Put the subject from image A in the setting from image B',
        aspectRatio: '1:1',
        seed: '42',
      );

      expect(sourceAssets.filenames, [
        'reference-0.png',
        'reference-1.png',
        'reference-2.png',
      ]);
      final input = jobs.submitted.single['input']! as JsonMap;
      expect(input['mode'], 'edit');
      expect(input['source_asset_id'], 'asset-1');
      expect(input['source_asset_id_2'], 'asset-2');
      expect(input['source_asset_id_3'], 'asset-3');
      expect(input, isNot(contains('aspect_ratio')));
    });

    test('reference generation requires image A', () async {
      final (viewModel, jobs) = await ready(
        templates: [
          _template(
            'reference',
            workflowId: 'image-create-reference-qwen-2511',
            inputs: const {
              'source_asset_id': WorkflowInputModel(
                type: 'string',
                required: true,
              ),
              'prompt': WorkflowInputModel(type: 'string', required: true),
            },
          ),
        ],
        mode: ImageGenerationMode.references,
      );

      final job = await viewModel.submit(
        prompt: 'A new portrait',
        aspectRatio: '1:1',
        seed: '',
      );

      expect(job, isNull);
      expect(jobs.submitted, isEmpty);
      expect(viewModel.modelError, isA<FormatException>());
    });

    test('omits the seed when it is blank', () async {
      final (viewModel, jobs) = await ready();

      await viewModel.submit(prompt: 'sky', aspectRatio: '1:1', seed: '   ');

      final input = jobs.submitted.single['input']! as JsonMap;
      expect(input.containsKey('seed'), isFalse);
    });

    test('omits the model input for workflows that take none', () async {
      final (viewModel, jobs) = await ready(
        templates: [
          _template(
            'plain',
            workflowId: 'image-create-plain',
            inputs: const {},
          ),
        ],
      );

      await viewModel.submit(prompt: 'sky', aspectRatio: '1:1', seed: '');

      final input = jobs.submitted.single['input']! as JsonMap;
      expect(input.containsKey('model'), isFalse);
    });

    test('omits a mapped model when the catalog does not declare it', () async {
      final (viewModel, jobs) = await ready(
        templates: [
          _template('z-image', workflowId: 'image-create', inputs: const {}),
        ],
      );

      await viewModel.submit(prompt: 'sky', aspectRatio: '1:1', seed: '');

      final input = jobs.submitted.single['input']! as JsonMap;
      expect(input.containsKey('model'), isFalse);
    });

    test('marks a Ghost submission for ephemeral delivery', () async {
      final jobs = _StubJobs();
      final viewModel = _viewModel(
        templates: _StubTemplates(templates: [_template('image-a')]),
        jobs: jobs,
        ghostMode: true,
      );
      await viewModel.load();

      await viewModel.submit(prompt: 'draft', aspectRatio: '1:1', seed: '');

      expect(jobs.submitted.single['ghostMode'], isTrue);
      expect(
        jobs.submitted.single.containsKey('notificationDeepLink'),
        isFalse,
      );
    });

    test('rejects an empty prompt before calling the repository', () async {
      final (viewModel, jobs) = await ready();

      final job = await viewModel.submit(
        prompt: '   ',
        aspectRatio: '1:1',
        seed: '',
      );

      expect(job, isNull);
      expect(jobs.submitted, isEmpty);
      expect(viewModel.modelError, isA<FormatException>());
    });

    test('rejects a non-numeric seed before calling the repository', () async {
      final (viewModel, jobs) = await ready();

      final job = await viewModel.submit(
        prompt: 'sky',
        aspectRatio: '1:1',
        seed: 'twelve',
      );

      expect(job, isNull);
      expect(jobs.submitted, isEmpty);
      expect(viewModel.modelError, isA<FormatException>());
    });

    test('refuses to submit when no template is enabled', () async {
      final (viewModel, jobs) = await ready(
        templates: [_template('blocked', enabled: false)],
      );

      final job = await viewModel.submit(
        prompt: 'sky',
        aspectRatio: '1:1',
        seed: '',
      );

      expect(job, isNull);
      expect(jobs.submitted, isEmpty);
    });

    test('records a submission failure and clears busy', () async {
      final viewModel = _viewModel(
        templates: _StubTemplates(templates: [_template('image-a')]),
        jobs: _StubJobs(
          failWith: const ApiFailure('boom', 'The runner is offline.'),
        ),
      );
      await viewModel.load();

      final job = await viewModel.submit(
        prompt: 'sky',
        aspectRatio: '1:1',
        seed: '',
      );

      expect(job, isNull);
      expect(viewModel.hasError, isTrue);
      expect(viewModel.submitting, isFalse);
    });

    test('notifies the caller after a successful submission', () async {
      var refreshes = 0;
      final viewModel = _viewModel(
        templates: _StubTemplates(templates: [_template('image-a')]),
        jobs: _StubJobs(),
        onSubmitted: () async => refreshes++,
      );
      await viewModel.load();

      await viewModel.submit(prompt: 'sky', aspectRatio: '1:1', seed: '');

      expect(refreshes, 1);
      expect(viewModel.submitting, isFalse);
      expect(viewModel.submittedJob, isNotNull);
    });
  });

  group('parseWorkflowTemplates', () {
    test('narrows to the requested workflow family', () {
      final templates = parseWorkflowTemplates(const {
        'templates': [
          {
            'id': 'a',
            'workflowId': 'image-create-flux2-klein',
            'enabled': true,
          },
          {'id': 'b', 'workflowId': 'video-create-wan', 'enabled': true},
        ],
      }, workflowIdPrefix: 'image-create');

      expect(templates.map((template) => template.id), ['a']);
    });

    test('an absent or malformed templates key yields an empty list', () {
      expect(parseWorkflowTemplates(const {}), isEmpty);
      expect(parseWorkflowTemplates(const {'templates': 'nope'}), isEmpty);
    });

    test('falls back to displayName for a missing model', () {
      final templates = parseWorkflowTemplates(const {
        'templates': [
          {'id': 'a', 'workflowId': 'image-create-x', 'displayName': 'Flux'},
        ],
      });

      expect(templates.single.model, 'Flux');
      expect(templates.single.enabled, isFalse);
    });
  });

  group('resolveSelectedTemplate', () {
    test('falls back through explicit, enabled, then first', () {
      final disabled = _template('a', enabled: false);
      final enabled = _template('b');
      expect(
        resolveSelectedTemplate([disabled, enabled], selectedId: 'a')?.id,
        'a',
      );
      expect(resolveSelectedTemplate([disabled, enabled])?.id, 'b');
      expect(resolveSelectedTemplate([disabled])?.id, 'a');
      expect(resolveSelectedTemplate(const []), isNull);
    });
  });

  test('imageModelInput maps only the workflows that need it', () {
    expect(imageModelInput('image-create'), 'z-image-turbo');
    expect(imageModelInput('image-create-flux2-klein'), 'flux2-klein');
    expect(imageModelInput('image-create-qwen-2512'), 'qwen-image-2512');
    expect(imageModelInput('image-create-other'), isNull);
  });

  group('prompt enhancement', () {
    Future<ImageGenerationViewModel> loaded(
      StubPromptEnhancements enhancements,
    ) async {
      final viewModel = _viewModel(
        templates: _StubTemplates(
          templates: [
            _template(
              'Z-Image Turbo',
              workflowId: 'image-create',
              inputs: const {
                'prompt': WorkflowInputModel(
                  type: 'string',
                  required: true,
                  maxLength: 60000,
                ),
              },
            ),
          ],
        ),
        jobs: _StubJobs(),
        promptEnhancements: enhancements,
      );
      await viewModel.load();
      viewModel.selectTemplate('Z-Image Turbo');
      return viewModel;
    }

    test('asks against the selected workflow, field, and budget', () async {
      final enhancements = StubPromptEnhancements();
      final viewModel = await loaded(enhancements);

      final rewritten = await viewModel.promptBinding!.onEnhance(
        'a quiet street',
      );

      expect(rewritten, 'Rewritten: a quiet street');
      expect(enhancements.lastRequest.workflowId, 'image-create');
      expect(enhancements.lastRequest.targetModel, 'Z-Image Turbo');
      expect(enhancements.lastRequest.field, 'prompt');
      expect(enhancements.lastRequest.maxLength, 60000);
      expect(viewModel.promptBinding!.outcome, PromptEnhanceOutcome.rewritten);
      expect(viewModel.promptBinding!.message, 'Rewritten for Z-Image Turbo.');
      expect(viewModel.promptBinding!.canUndo, isTrue);
      expect(
        viewModel.promptBinding!.guideSource.toString(),
        'https://tongyi-mai.github.io/Z-Image-blog/',
      );
    });

    test('hands back exactly what was typed when undone', () async {
      final viewModel = await loaded(StubPromptEnhancements());

      await viewModel.promptBinding!.onEnhance('a quiet street');

      expect(viewModel.promptBinding!.onUndo(), 'a quiet street');
      expect(viewModel.promptBinding!.canUndo, isFalse);
      expect(viewModel.promptBinding!.outcome, PromptEnhanceOutcome.idle);
      expect(viewModel.promptBinding!.message, isNull);
    });

    test('a second rewrite still undoes to what the person typed', () async {
      final viewModel = await loaded(StubPromptEnhancements());

      final first = await viewModel.promptBinding!.onEnhance('a quiet street');
      await viewModel.promptBinding!.onEnhance(first!);

      expect(viewModel.promptBinding!.onUndo(), 'a quiet street');
    });

    test('says what happened when the text comes back unchanged', () async {
      final viewModel = await loaded(
        StubPromptEnhancements(
          result: unchangedResult(fallbackReason: 'key_unavailable'),
        ),
      );

      expect(
        await viewModel.promptBinding!.onEnhance('a quiet street'),
        isNull,
      );
      expect(viewModel.promptBinding!.outcome, PromptEnhanceOutcome.unchanged);
      expect(viewModel.promptBinding!.message, contains('unchanged'));
      expect(viewModel.promptBinding!.message, contains('Settings'));
      expect(viewModel.promptBinding!.canUndo, isFalse);
    });

    test('keeps the text and explains when the request fails', () async {
      final viewModel = await loaded(
        StubPromptEnhancements(failWith: StateError('offline')),
      );

      expect(
        await viewModel.promptBinding!.onEnhance('a quiet street'),
        isNull,
      );
      expect(viewModel.promptBinding!.outcome, PromptEnhanceOutcome.unchanged);
      expect(viewModel.promptBinding!.message, contains('unchanged'));
    });

    test('an empty field is never sent to the rewriter', () async {
      final enhancements = StubPromptEnhancements();
      final viewModel = await loaded(enhancements);

      expect(await viewModel.promptBinding!.onEnhance('   '), isNull);
      expect(enhancements.requests, isEmpty);
    });

    test('a kept rewrite tells dispatch not to rewrite it again', () async {
      final jobs = _StubJobs();
      final viewModel = _viewModel(
        templates: _StubTemplates(
          templates: [_template('Z-Image Turbo', workflowId: 'image-create')],
        ),
        jobs: jobs,
      );
      await viewModel.load();
      viewModel.selectTemplate('Z-Image Turbo');
      await viewModel.promptBinding!.onEnhance('a quiet street');

      await viewModel.submit(
        prompt: 'Rewritten: a quiet street',
        aspectRatio: '1:1',
        seed: '',
      );

      expect(jobs.submitted.single['promptEnhancementBypass'], 'user_enhanced');
    });

    test('a job with no rewrite carries no bypass', () async {
      final jobs = _StubJobs();
      final viewModel = _viewModel(
        templates: _StubTemplates(
          templates: [_template('Z-Image Turbo', workflowId: 'image-create')],
        ),
        jobs: jobs,
      );
      await viewModel.load();
      viewModel.selectTemplate('Z-Image Turbo');

      await viewModel.submit(
        prompt: 'a quiet street',
        aspectRatio: '1:1',
        seed: '',
      );

      expect(
        jobs.submitted.single.containsKey('promptEnhancementBypass'),
        isFalse,
      );
    });
  });
}
