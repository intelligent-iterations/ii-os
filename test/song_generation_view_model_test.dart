import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/repositories/job_repository.dart';
import 'package:ii_os/repositories/workflow_template_repository.dart';
import 'package:ii_os/view_models/song_generation_view_model.dart';

import 'prompt_enhancement_stubs.dart';

final class _Templates implements WorkflowTemplateRepository {
  String? prefix;

  @override
  Future<List<WorkflowTemplateModel>> list(
    String workspaceId, {
    String? workflowIdPrefix,
  }) async {
    prefix = workflowIdPrefix;
    return [_songTemplate];
  }
}

final class _Jobs implements JobRepository {
  JobSubmission? submission;

  @override
  Future<JsonMap> submit(String workspaceId, JobSubmission submission) async {
    this.submission = submission;
    return const {'jobId': 'song_1', 'status': 'requested'};
  }

  @override
  Future<JobListing> list(String workspaceId) async => JobListing.empty;

  @override
  Future<JsonMap> detail(String workspaceId, String jobId) async => const {};
}

const _songTemplate = WorkflowTemplateModel(
  id: 'song-template',
  workflowId: 'song-create-acestep-xl-sft',
  version: '1',
  displayName: 'ACE-Step Song',
  model: 'ACE-Step 1.5',
  repository: 'acme/music',
  enabled: true,
  disabledReason: '',
  inputs: {},
  runtimeEstimates: [
    WorkflowRuntimeEstimateModel(
      selector: {'generation_profile': 'draft-120'},
      durationInput: '',
      baselineOutputSeconds: 0,
      baselineRuntimeSeconds: 61,
      hardware: '24 GB GPU',
      measuredAt: '2026-08-01',
    ),
    WorkflowRuntimeEstimateModel(
      selector: {'generation_profile': 'quality-60'},
      durationInput: '',
      baselineOutputSeconds: 0,
      baselineRuntimeSeconds: 100,
      hardware: '24 GB GPU',
      measuredAt: '2026-08-25',
    ),
  ],
);

SongGenerationViewModel _viewModel(_Templates templates, _Jobs jobs) =>
    SongGenerationViewModel(
      templates: templates,
      jobs: jobs,
      promptEnhancements: StubPromptEnhancements(),
      workspaceId: 'ws_test',
    );

void main() {
  test('estimate follows the selected song render profile', () async {
    final viewModel = _viewModel(_Templates(), _Jobs());
    await viewModel.load();

    expect(viewModel.runtimeEstimate?.estimatedSeconds, 61);

    viewModel.selectGenerationProfile('quality-60');

    expect(viewModel.runtimeEstimate?.estimatedSeconds, 100);
  });

  test('loads only the song workflow family', () async {
    final templates = _Templates();
    final viewModel = _viewModel(templates, _Jobs());

    await viewModel.load();

    expect(templates.prefix, 'song-create');
    expect(viewModel.canSubmit, isTrue);
  });

  test(
    'a default submission sends every workflow-safe model setting',
    () async {
      final jobs = _Jobs();
      final viewModel = _viewModel(_Templates(), jobs);
      await viewModel.load();

      await viewModel.submit(
        prompt: 'Luminous synth-pop with a rising chorus',
        lyrics: '[Chorus]\nBegin again',
        bpm: '',
        seed: '',
      );

      final input = jobs.submission!.input;
      expect(input['generation_profile'], 'draft-120');
      expect(input['duration_seconds'], 120);
      expect(input['instrumental'], isFalse);
      expect(input['vocal_language'], 'unknown');
      expect(input['key_scale'], '');
      expect(input['time_signature'], '');
    },
  );

  test(
    'instrumental submission strips lyrics and forces auto language',
    () async {
      final jobs = _Jobs();
      final viewModel = _viewModel(_Templates(), jobs);
      await viewModel.load();
      viewModel.setVocalLanguage('es');
      viewModel.setInstrumental(true);

      await viewModel.submit(
        prompt: 'Warm acoustic folk instrumental',
        lyrics: 'Do not send this',
        bpm: '90',
        seed: '42',
      );

      expect(jobs.submission!.input['lyrics'], '');
      expect(jobs.submission!.input['vocal_language'], 'unknown');
    },
  );

  test('rejects out-of-range tempo before reaching the repository', () async {
    final jobs = _Jobs();
    final viewModel = _viewModel(_Templates(), jobs);
    await viewModel.load();

    final result = await viewModel.submit(
      prompt: 'Fast song',
      lyrics: '',
      bpm: '301',
      seed: '',
    );

    expect(result, isNull);
    expect(jobs.submission, isNull);
    expect(viewModel.modelError.toString(), contains('30 and 300'));
  });
}
