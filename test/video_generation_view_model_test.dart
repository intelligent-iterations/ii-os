import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/generation_history.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/models/minimax_h3_generation_spec.dart';
import 'package:ii_os/repositories/generation_history_repository.dart';
import 'package:ii_os/screens/video_generation_settings.dart';
import 'package:ii_os/repositories/job_repository.dart';
import 'package:ii_os/repositories/media_repository.dart';
import 'package:ii_os/repositories/source_asset_repository.dart';
import 'package:ii_os/repositories/workflow_template_repository.dart';
import 'package:ii_os/services/artifact_read_url_cache.dart';
import 'package:ii_os/services/verified_artifact_media.dart';
import 'package:ii_os/view_models/video_generation_view_model.dart';

import 'prompt_enhancement_stubs.dart';

final class _StubTemplates implements WorkflowTemplateRepository {
  _StubTemplates(this.values);

  final List<WorkflowTemplateModel> values;
  String? lastPrefix;

  @override
  Future<List<WorkflowTemplateModel>> list(
    String workspaceId, {
    String? workflowIdPrefix,
  }) async {
    lastPrefix = workflowIdPrefix;
    return values;
  }
}

final class _StubJobs implements JobRepository {
  final List<JsonMap> submitted = [];

  @override
  Future<JsonMap> submit(String workspaceId, JobSubmission submission) async {
    submitted.add(submission.body(workspaceId));
    return const {'jobId': 'video-1', 'status': 'requested'};
  }

  @override
  Future<JobListing> list(String workspaceId) async => JobListing.empty;

  @override
  Future<JsonMap> detail(String workspaceId, String jobId) async => const {};
}

final class _StubSourceAssets implements SourceAssetRepository {
  int uploadCount = 0;
  bool? lastGhostMode;
  final List<({String filename, String contentType})> uploads = [];

  @override
  Future<String> upload({
    required String workspaceId,
    required String filename,
    required Uint8List bytes,
    required String contentType,
    required String expectedBucket,
    bool ghostMode = false,
  }) async {
    uploadCount += 1;
    lastGhostMode = ghostMode;
    expect(expectedBucket, 'workspace-bucket');
    uploads.add((filename: filename, contentType: contentType));
    return switch (uploadCount) {
      1 => '33449737-9e39-4d53-8040-f39d5f7bc3ce',
      _ => 'e4a443e5-ef0d-4f23-b977-2d89959a0812',
    };
  }
}

final class _StubMedia implements WorkspaceMediaRepository {
  _StubMedia({Uint8List? bytes})
    : bytes =
          bytes ??
          Uint8List.fromList(const [
            0x89,
            0x50,
            0x4e,
            0x47,
            0x0d,
            0x0a,
            0x1a,
            0x0a,
          ]),
      historyRepository = GenerationHistoryRepository.withLoader(
        loader: (_) async => const {'jobs': <Object?>[]},
        workspaceId: 'workspace-1',
        retentionDays: 30,
      );

  final Uint8List bytes;
  final GenerationHistoryRepository historyRepository;
  int readCount = 0;
  int sourceAssetReadCount = 0;
  String? lastSourceAssetId;
  String? lastSourceAssetBucket;
  Object? sourceAssetFailure;

  @override
  GenerationHistoryRepository history({
    required String workspaceId,
    required int retentionDays,
  }) => historyRepository;

  @override
  Future<VerifiedArtifactMedia> readVerifiedArtifact({
    required String workspaceId,
    required String jobId,
    required String expectedBucket,
    required JsonMap artifact,
    bool transient = false,
  }) async {
    readCount += 1;
    final objectName = artifact['path']! as String;
    return VerifiedArtifactMedia(
      identity: ArtifactAuthorizationIdentity(
        workspaceId: workspaceId,
        jobId: jobId,
        bucket: expectedBucket,
        objectName: objectName,
        generation: artifact['generation']! as String,
        sizeBytes: bytes.length,
        sha256: List.filled(64, 'a').join(),
        contentType: artifact['content_type']! as String,
      ),
      filename: objectName.split('/').last,
      detectedContentType: artifact['content_type']! as String,
      bytes: bytes,
    );
  }

  @override
  Future<VerifiedArtifactMedia> readVerifiedSourceAsset({
    required String workspaceId,
    required String assetId,
    required String expectedBucket,
  }) async {
    sourceAssetReadCount += 1;
    lastSourceAssetId = assetId;
    lastSourceAssetBucket = expectedBucket;
    final failure = sourceAssetFailure;
    if (failure != null) throw failure;
    final objectName =
        'workspaces/$workspaceId/source-assets/$assetId/reference.png';
    return VerifiedArtifactMedia(
      identity: ArtifactAuthorizationIdentity(
        workspaceId: workspaceId,
        jobId: 'source-asset:$assetId',
        bucket: expectedBucket,
        objectName: objectName,
        generation: '1',
        sizeBytes: bytes.length,
        sha256: List.filled(64, 'a').join(),
        contentType: 'image/png',
      ),
      filename: 'reference.png',
      detectedContentType: 'image/png',
      bytes: bytes,
    );
  }
}

WorkflowTemplateModel _template(
  String workflowId, {
  bool enabled = true,
  bool fullH3 = false,
}) => WorkflowTemplateModel(
  id: 'acme/media#$workflowId',
  workflowId: workflowId,
  version: '1',
  displayName: workflowId,
  model: workflowId == minimaxH3WorkflowId ? 'MiniMax H3' : 'LTX 2.3',
  repository: 'acme/media',
  enabled: enabled,
  disabledReason: enabled ? '' : 'Not enabled for this workspace.',
  inputs: {
    'duration_seconds': WorkflowInputModel(
      type: 'number',
      required: true,
      minimum: workflowId == minimaxH3WorkflowId ? 4 : 2,
      maximum: workflowId == minimaxH3WorkflowId ? 15 : 20,
      defaultNumber: workflowId == minimaxH3WorkflowId ? 15 : 5,
    ),
    if (workflowId == minimaxH3WorkflowId)
      minimaxH3PerformanceModeInput: const WorkflowInputModel(
        type: 'string',
        required: true,
      ),
    if (fullH3) ...{
      minimaxH3GenerationModeInput: const WorkflowInputModel(
        type: 'string',
        required: true,
      ),
      minimaxH3ReferenceManifestInput: const WorkflowInputModel(
        type: 'string',
        required: true,
      ),
      minimaxH3EditOperationInput: const WorkflowInputModel(
        type: 'string',
        required: false,
      ),
      minimaxH3ExtensionMethodInput: const WorkflowInputModel(
        type: 'string',
        required: false,
      ),
      minimaxH3IdentityConsentInput: const WorkflowInputModel(
        type: 'boolean',
        required: false,
      ),
    },
  },
  runtimeEstimates: workflowId == minimaxH3WorkflowId
      ? const [
          WorkflowRuntimeEstimateModel(
            selector: {'performance_mode': 'quality'},
            durationInput: 'duration_seconds',
            baselineOutputSeconds: 15,
            baselineRuntimeSeconds: 1953,
            hardware: '24 GB GPU',
            measuredAt: '2026-08-14',
          ),
          WorkflowRuntimeEstimateModel(
            selector: {'performance_mode': 'turbo'},
            durationInput: 'duration_seconds',
            baselineOutputSeconds: 15,
            baselineRuntimeSeconds: 900,
            hardware: '24 GB GPU',
            measuredAt: '2026-08-14',
          ),
        ]
      : const [],
);

VideoGenerationViewModel _viewModel({
  required List<WorkflowTemplateModel> templates,
  required _StubJobs jobs,
  required _StubSourceAssets sources,
  WorkspaceMediaRepository? media,
  bool ghostMode = false,
  MiniMaxH3GenerationMode? initialH3Mode,
  String? initialH3SourceAssetId,
  Future<void> Function()? onSubmitted,
}) => VideoGenerationViewModel(
  promptEnhancements: StubPromptEnhancements(),
  templates: _StubTemplates(templates),
  jobs: jobs,
  sourceAssets: sources,
  media: media ?? _StubMedia(),
  workspaceId: 'workspace-1',
  expectedBucket: 'workspace-bucket',
  ghostMode: ghostMode,
  initialH3Mode: initialH3Mode,
  initialH3SourceAssetId: initialH3SourceAssetId,
  onSubmitted: onSubmitted,
);

void main() {
  test('loads only the supported LTX, H3, and SeedVR2 templates', () async {
    final templates = _StubTemplates([
      _template(ltxImageToVideoWorkflowId),
      _template(minimaxH3WorkflowId),
      _template(seedVr2VideoUpscaleWorkflowId),
      _template('image-create'),
    ]);
    final viewModel = VideoGenerationViewModel(
      promptEnhancements: StubPromptEnhancements(),
      templates: templates,
      jobs: _StubJobs(),
      sourceAssets: _StubSourceAssets(),
      media: _StubMedia(),
      workspaceId: 'workspace-1',
      expectedBucket: 'workspace-bucket',
    );

    await viewModel.load();

    expect(templates.lastPrefix, isNull);
    expect(viewModel.templates.map((item) => item.workflowId), [
      ltxImageToVideoWorkflowId,
      minimaxH3WorkflowId,
      seedVr2VideoUpscaleWorkflowId,
    ]);
  });

  test(
    'SeedVR2 uploads one source video and submits safe server presets',
    () async {
      final jobs = _StubJobs();
      final sources = _StubSourceAssets();
      final viewModel = _viewModel(
        templates: [_template(seedVr2VideoUpscaleWorkflowId)],
        jobs: jobs,
        sources: sources,
      );
      await viewModel.load();
      final mp4 = Uint8List.fromList('0000ftyp0000'.codeUnits);

      expect(
        viewModel.setSourceVideo(filename: 'source.mp4', bytes: mp4),
        isTrue,
      );
      final job = await viewModel.submit(prompt: '');

      expect(job, isNotNull);
      expect(viewModel.isSeedVr2, isTrue);
      expect(viewModel.sourceVideoRequired, isTrue);
      expect(sources.uploads, [
        (filename: 'source.mp4', contentType: 'video/mp4'),
      ]);
      expect(jobs.submitted.single['input'], {
        'source_asset_id': '33449737-9e39-4d53-8040-f39d5f7bc3ce',
        'target_resolution': 1080,
        'quality_preset': 'quality',
        'preserve_audio': true,
        'seed': 42,
      });
    },
  );

  test('SeedVR2 rejects malformed source media before submission', () async {
    final jobs = _StubJobs();
    final viewModel = _viewModel(
      templates: [_template(seedVr2VideoUpscaleWorkflowId)],
      jobs: jobs,
      sources: _StubSourceAssets(),
    );
    await viewModel.load();

    expect(
      viewModel.setSourceVideo(
        filename: 'source.mp4',
        bytes: Uint8List.fromList('not-a-video'.codeUnits),
      ),
      isFalse,
    );
    expect(await viewModel.submit(prompt: ''), isNull);
    expect(jobs.submitted, isEmpty);
    expect(viewModel.modelError.toString(), contains('source video'));
  });

  test('SeedVR2 rejects media outside the MP4 and WebM contract', () async {
    final jobs = _StubJobs();
    final viewModel = _viewModel(
      templates: [_template(seedVr2VideoUpscaleWorkflowId)],
      jobs: jobs,
      sources: _StubSourceAssets(),
    );
    await viewModel.load();

    expect(
      viewModel.setSourceVideo(
        filename: 'source.mov',
        bytes: Uint8List.fromList('0000ftyp0000'.codeUnits),
      ),
      isFalse,
    );
    expect(await viewModel.submit(prompt: ''), isNull);
    expect(jobs.submitted, isEmpty);
  });

  test(
    'selecting H3 defaults to portrait while keeping shape selectable',
    () async {
      final viewModel = _viewModel(
        templates: [
          _template(ltxImageToVideoWorkflowId),
          _template(minimaxH3WorkflowId),
        ],
        jobs: _StubJobs(),
        sources: _StubSourceAssets(),
      );
      await viewModel.load();
      viewModel.setOrientation('portrait');
      viewModel.setFps(60);
      viewModel.setDuration(9);

      viewModel.selectTemplate('acme/media#$minimaxH3WorkflowId');

      expect(viewModel.isMiniMaxH3, isTrue);
      expect(viewModel.sourceImageRequired, isFalse);
      expect(viewModel.orientation, 'portrait');
      expect(viewModel.resolution, '720 × 1280');
      expect(viewModel.fps, 24);
      expect(viewModel.duration, 15);
      expect(viewModel.h3PerformanceMode, MiniMaxH3PerformanceMode.quality);
      viewModel.setOrientation('landscape');
      expect(viewModel.orientation, 'landscape');
      expect(viewModel.resolution, '1280 × 720');
      viewModel.setDuration(4);
      expect(viewModel.duration, 4);
      viewModel.setDuration(99);
      expect(viewModel.duration, 15);
    },
  );

  test('H3 intersects stale catalog bounds with model capabilities', () async {
    final staleTemplate = WorkflowTemplateModel(
      id: 'acme/media#$minimaxH3WorkflowId',
      workflowId: minimaxH3WorkflowId,
      version: '1',
      displayName: 'MiniMax H3',
      model: 'MiniMax H3',
      repository: 'acme/media',
      enabled: true,
      disabledReason: '',
      inputs: {
        'duration_seconds': const WorkflowInputModel(
          type: 'number',
          required: true,
          minimum: 2,
          maximum: 20,
          defaultNumber: 15,
        ),
      },
    );
    final viewModel = _viewModel(
      templates: [staleTemplate],
      jobs: _StubJobs(),
      sources: _StubSourceAssets(),
    );

    await viewModel.load();

    expect(viewModel.minimumDuration, 4);
    expect(viewModel.maximumDuration, 15);
  });

  test('H3 estimate follows the selected duration and render mode', () async {
    final viewModel = _viewModel(
      templates: [_template(minimaxH3WorkflowId)],
      jobs: _StubJobs(),
      sources: _StubSourceAssets(),
    );
    await viewModel.load();

    expect(viewModel.runtimeEstimate?.estimatedSeconds, 1953);
    expect(viewModel.runtimeEstimate?.durationLabel, '33 minutes');

    viewModel.setDuration(5);
    viewModel.setH3PerformanceMode(MiniMaxH3PerformanceMode.turbo);

    expect(viewModel.runtimeEstimate?.estimatedSeconds, 300);
    expect(viewModel.runtimeEstimate?.durationLabel, '5 minutes');
  });

  test(
    'H3 submits the selected performance mode without a source image',
    () async {
      final jobs = _StubJobs();
      final sources = _StubSourceAssets();
      var refreshed = false;
      final viewModel = _viewModel(
        templates: [_template(minimaxH3WorkflowId)],
        jobs: jobs,
        sources: sources,
        onSubmitted: () async => refreshed = true,
      );
      await viewModel.load();
      viewModel.setDuration(7);
      viewModel.setH3PerformanceMode(MiniMaxH3PerformanceMode.turbo);

      final job = await viewModel.submit(
        prompt: '  A chrome hummingbird wakes in a dark laboratory.  ',
      );

      expect(job, isNotNull);
      expect(sources.uploadCount, 0);
      expect(refreshed, isTrue);
      final posted = jobs.submitted.single;
      expect(posted['workflowKey'], 'acme/media#$minimaxH3WorkflowId');
      expect(
        posted['notificationDeepLink'],
        '/workspaces/workspace-1/video-generation',
      );
      expect(posted['input'], {
        'prompt': 'A chrome hummingbird wakes in a dark laboratory.',
        'duration_seconds': 7,
        'orientation': 'portrait',
        'fps': 24,
        minimaxH3PerformanceModeInput: 'turbo',
      });
    },
  );

  test('LTX uploads one source image and submits its asset identity', () async {
    final jobs = _StubJobs();
    final sources = _StubSourceAssets();
    final viewModel = _viewModel(
      templates: [_template(ltxImageToVideoWorkflowId)],
      jobs: jobs,
      sources: sources,
    );
    await viewModel.load();
    final png = Uint8List.fromList(const [
      0x89,
      0x50,
      0x4e,
      0x47,
      0x0d,
      0x0a,
      0x1a,
      0x0a,
    ]);
    expect(viewModel.setSource(filename: 'source.png', bytes: png), isTrue);
    viewModel.setOrientation('portrait');
    viewModel.setFps(30);
    viewModel.setDuration(8);

    await viewModel.submit(prompt: 'The subject turns toward the light.');

    expect(sources.uploadCount, 1);
    final input = jobs.submitted.single['input']! as JsonMap;
    expect(input['source_asset_id'], '33449737-9e39-4d53-8040-f39d5f7bc3ce');
    expect(input['orientation'], 'portrait');
    expect(input['fps'], 30);
    expect(input['duration_seconds'], 8);
  });

  test('Ghost LTX marks both source and output as temporary', () async {
    final jobs = _StubJobs();
    final sources = _StubSourceAssets();
    final viewModel = _viewModel(
      templates: [_template(ltxImageToVideoWorkflowId)],
      jobs: jobs,
      sources: sources,
      ghostMode: true,
    );
    await viewModel.load();
    final png = Uint8List.fromList(const [
      0x89,
      0x50,
      0x4e,
      0x47,
      0x0d,
      0x0a,
      0x1a,
      0x0a,
    ]);
    viewModel.setSource(filename: 'source.png', bytes: png);

    await viewModel.submit(prompt: 'A private motion test.');

    expect(sources.lastGhostMode, isTrue);
    expect(jobs.submitted.single['ghostMode'], isTrue);
  });

  test('manual retry reuses the uploaded source asset', () async {
    final jobs = _StubJobs();
    final sources = _StubSourceAssets();
    final viewModel = _viewModel(
      templates: [_template(ltxImageToVideoWorkflowId)],
      jobs: jobs,
      sources: sources,
    );
    await viewModel.load();
    final png = Uint8List.fromList(const [
      0x89,
      0x50,
      0x4e,
      0x47,
      0x0d,
      0x0a,
      0x1a,
      0x0a,
    ]);
    viewModel.setSource(filename: 'source.png', bytes: png);

    await viewModel.submit(prompt: 'The subject turns toward the light.');
    await viewModel.retryLastSubmission();

    expect(sources.uploadCount, 1);
    expect(jobs.submitted, hasLength(2));
    expect(jobs.submitted.last, equals(jobs.submitted.first));
    expect(
      (jobs.submitted.last['input']! as JsonMap)['source_asset_id'],
      '33449737-9e39-4d53-8040-f39d5f7bc3ce',
    );
  });

  test('rejects H3 prompts over the reported 7,000-character limit', () async {
    final jobs = _StubJobs();
    final viewModel = _viewModel(
      templates: [_template(minimaxH3WorkflowId)],
      jobs: jobs,
      sources: _StubSourceAssets(),
    );
    await viewModel.load();

    final result = await viewModel.submit(
      prompt: List.filled(7001, 'x').join(),
    );

    expect(result, isNull);
    expect(jobs.submitted, isEmpty);
    expect(viewModel.modelError.toString(), contains('7,000'));
  });

  test(
    'full H3 video edit uploads role-aware references and consent',
    () async {
      final jobs = _StubJobs();
      final sources = _StubSourceAssets();
      final viewModel = _viewModel(
        templates: [_template(minimaxH3WorkflowId, fullH3: true)],
        jobs: jobs,
        sources: sources,
      );
      await viewModel.load();
      expect(viewModel.supportsH3VideoEditing, isTrue);
      viewModel.setH3PerformanceMode(MiniMaxH3PerformanceMode.turbo);
      viewModel.setH3Mode(MiniMaxH3GenerationMode.videoEdit);
      expect(viewModel.h3PerformanceMode, MiniMaxH3PerformanceMode.quality);
      expect(
        viewModel.h3PerformanceModeEnabled(MiniMaxH3PerformanceMode.turbo),
        isFalse,
      );
      final mp4 = Uint8List.fromList('0000ftyp0000'.codeUnits);
      final png = Uint8List.fromList(const [
        0x89,
        0x50,
        0x4e,
        0x47,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
      ]);
      expect(
        viewModel.addH3Reference(
          kind: MiniMaxH3ReferenceKind.video,
          filename: 'source.mp4',
          bytes: mp4,
        ),
        isTrue,
      );
      expect(
        viewModel.addH3Reference(
          kind: MiniMaxH3ReferenceKind.image,
          filename: 'identity.png',
          bytes: png,
        ),
        isTrue,
      );
      viewModel.setH3EditOperation(MiniMaxH3EditOperation.characterReplacement);
      viewModel.setIdentityReplacementConsent(true);

      final result = await viewModel.submit(
        prompt: 'Replace the performer and preserve the original motion.',
      );

      expect(result, isNotNull);
      expect(sources.uploads, [
        (filename: 'source.mp4', contentType: 'video/mp4'),
        (filename: 'identity.png', contentType: 'image/png'),
      ]);
      final input = jobs.submitted.single['input']! as JsonMap;
      expect(input[minimaxH3GenerationModeInput], 'video_edit');
      expect(input[minimaxH3EditOperationInput], 'character_replacement');
      expect(input[minimaxH3IdentityConsentInput], isTrue);
      final manifest =
          jsonDecode(input[minimaxH3ReferenceManifestInput]! as String)
              as Map<String, Object?>;
      expect(manifest['schema_version'], 1);
      expect(manifest['mode'], 'video_edit');
      final references = manifest['references']! as List<Object?>;
      expect(references, hasLength(2));
      expect((references.first! as Map)['role'], 'source_video');
      expect((references.last! as Map)['role'], 'subject');
    },
  );

  test('H3 adds an image selected from the workspace Asset Library', () async {
    final media = _StubMedia();
    final viewModel = _viewModel(
      templates: [_template(minimaxH3WorkflowId, fullH3: true)],
      jobs: _StubJobs(),
      sources: _StubSourceAssets(),
      media: media,
    );
    await viewModel.load();
    viewModel.setH3Mode(MiniMaxH3GenerationMode.firstFrame);
    final entry = HistoryEntryModel(
      jobId: 'image-job-1',
      repository: 'acme/media',
      status: 'completed',
      submittedAt: DateTime.utc(2026, 8, 16),
      generation: const GenerationMetadataModel(
        prompt: 'A fictional dancer',
        model: 'Z-Image Turbo',
        workflowKey: 'image-create',
      ),
      artifact: const {
        'path': 'workspaces/workspace-1/runs/image-job-1/image/dancer.png',
        'generation': '1786900000000000',
        'content_type': 'image/png',
        'size_bytes': 8,
        'sha256':
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      },
    );

    final added = await viewModel.addGeneratedH3Reference(
      kind: MiniMaxH3ReferenceKind.image,
      entry: entry,
    );

    expect(added, isTrue);
    expect(media.readCount, 1);
    expect(viewModel.h3References.single.filename, 'dancer.png');
    expect(
      viewModel.h3References.single.role,
      MiniMaxH3ReferenceRole.firstFrame,
    );
    expect(viewModel.h3References.single.bytes, media.bytes);
    expect(viewModel.addingH3LibraryReference, isFalse);
  });

  test(
    'H3 rejects the wrong Asset Library media type before download',
    () async {
      final media = _StubMedia();
      final viewModel = _viewModel(
        templates: [_template(minimaxH3WorkflowId, fullH3: true)],
        jobs: _StubJobs(),
        sources: _StubSourceAssets(),
        media: media,
      );
      await viewModel.load();
      viewModel.setH3Mode(MiniMaxH3GenerationMode.firstFrame);
      final entry = HistoryEntryModel(
        jobId: 'video-job-1',
        repository: 'acme/media',
        status: 'completed',
        submittedAt: null,
        generation: const GenerationMetadataModel(
          prompt: '',
          model: 'MiniMax H3',
          workflowKey: 'video-create',
        ),
        artifact: const {
          'path': 'workspaces/workspace-1/runs/video-job-1/video/clip.mp4',
          'generation': '1786900000000001',
          'content_type': 'video/mp4',
          'size_bytes': 8,
          'sha256':
              'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        },
      );

      final added = await viewModel.addGeneratedH3Reference(
        kind: MiniMaxH3ReferenceKind.image,
        entry: entry,
      );

      expect(added, isFalse);
      expect(media.readCount, 0);
      expect(viewModel.modelError.toString(), contains('Asset Library'));
    },
  );

  test('character replacement requires subject media and permission', () async {
    final jobs = _StubJobs();
    final viewModel = _viewModel(
      templates: [_template(minimaxH3WorkflowId, fullH3: true)],
      jobs: jobs,
      sources: _StubSourceAssets(),
    );
    await viewModel.load();
    viewModel.setH3Mode(MiniMaxH3GenerationMode.videoEdit);
    viewModel.addH3Reference(
      kind: MiniMaxH3ReferenceKind.video,
      filename: 'source.mp4',
      bytes: Uint8List.fromList('0000ftyp0000'.codeUnits),
    );
    viewModel.setH3EditOperation(MiniMaxH3EditOperation.characterReplacement);

    final result = await viewModel.submit(prompt: 'Replace the performer.');

    expect(result, isNull);
    expect(jobs.submitted, isEmpty);
    expect(viewModel.modelError.toString(), contains('permission'));
  });

  test(
    'video editor handoff selects H3 continuation without reupload',
    () async {
      final jobs = _StubJobs();
      final sources = _StubSourceAssets();
      final media = _StubMedia();
      final viewModel = _viewModel(
        templates: [
          _template(ltxImageToVideoWorkflowId),
          _template(minimaxH3WorkflowId, fullH3: true),
        ],
        jobs: jobs,
        sources: sources,
        media: media,
        initialH3Mode: MiniMaxH3GenerationMode.videoContinue,
        initialH3SourceAssetId: '33449737-9e39-4d53-8040-f39d5f7bc3ce',
      );

      await viewModel.load();
      expect(viewModel.isMiniMaxH3, isTrue);
      expect(viewModel.h3Mode, MiniMaxH3GenerationMode.videoContinue);
      expect(
        viewModel.h3References.single.role,
        MiniMaxH3ReferenceRole.sourceVideo,
      );
      // The handoff arrives as an id alone; hydration fetches the bytes so
      // the reference row can show what is about to be continued.
      expect(viewModel.h3References.single.bytes, isNotEmpty);
      expect(media.sourceAssetReadCount, 1);
      expect(media.lastSourceAssetId, '33449737-9e39-4d53-8040-f39d5f7bc3ce');
      expect(media.lastSourceAssetBucket, 'workspace-bucket');
      expect(viewModel.allowedH3ReferenceKinds, MiniMaxH3ReferenceKind.values);
      expect(
        viewModel.addH3Reference(
          kind: MiniMaxH3ReferenceKind.image,
          filename: 'pose.png',
          bytes: Uint8List.fromList(const [
            0x89,
            0x50,
            0x4e,
            0x47,
            0x0d,
            0x0a,
            0x1a,
            0x0a,
          ]),
        ),
        isTrue,
      );
      viewModel.setH3ReferenceRole(
        viewModel.h3References.last.id,
        MiniMaxH3ReferenceRole.poseReference,
      );

      final result = await viewModel.submit(
        prompt: 'Continue into one smooth final dance movement.',
      );
      expect(result, isNotNull);
      expect(sources.uploads.single.filename, 'pose.png');
      final input = jobs.submitted.single['input']! as JsonMap;
      expect(input[minimaxH3GenerationModeInput], 'video_continue');
      expect(
        input[minimaxH3ReferenceManifestInput],
        contains('pose_reference'),
      );
    },
  );

  test('a preview that cannot be fetched never breaks page load', () async {
    final media = _StubMedia()..sourceAssetFailure = StateError('offline');
    final viewModel = _viewModel(
      templates: [_template(minimaxH3WorkflowId, fullH3: true)],
      jobs: _StubJobs(),
      sources: _StubSourceAssets(),
      media: media,
      initialH3Mode: MiniMaxH3GenerationMode.videoContinue,
      initialH3SourceAssetId: '33449737-9e39-4d53-8040-f39d5f7bc3ce',
    );

    await viewModel.load();

    expect(media.sourceAssetReadCount, 1);
    expect(viewModel.h3References.single.bytes, isEmpty);
    expect(viewModel.h3References.single.assetId, isNotNull);
    expect(viewModel.modelError, isNull);
    expect(viewModel.templates, isNotEmpty);
  });

  test('references that already carry bytes are never refetched', () async {
    final media = _StubMedia();
    final viewModel = _viewModel(
      templates: [_template(minimaxH3WorkflowId, fullH3: true)],
      jobs: _StubJobs(),
      sources: _StubSourceAssets(),
      media: media,
    );
    await viewModel.load();
    viewModel.setH3Mode(MiniMaxH3GenerationMode.firstFrame);
    viewModel.addH3Reference(
      kind: MiniMaxH3ReferenceKind.image,
      filename: 'pose.png',
      bytes: Uint8List.fromList(const [
        0x89,
        0x50,
        0x4e,
        0x47,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
      ]),
    );

    expect(viewModel.h3References.single.bytes, isNotEmpty);
    expect(media.sourceAssetReadCount, 0);
  });

  test('ghost mode can resubmit a hydrated handoff reference', () async {
    // Ghost mode clears every assetId. Before hydration that left the handoff
    // draft with neither bytes nor id, so submitting threw or uploaded nothing.
    final sources = _StubSourceAssets();
    final jobs = _StubJobs();
    final viewModel = _viewModel(
      templates: [_template(minimaxH3WorkflowId, fullH3: true)],
      jobs: jobs,
      sources: sources,
      media: _StubMedia(),
      initialH3Mode: MiniMaxH3GenerationMode.videoContinue,
      initialH3SourceAssetId: '33449737-9e39-4d53-8040-f39d5f7bc3ce',
    );
    await viewModel.load();
    expect(viewModel.h3References.single.bytes, isNotEmpty);

    viewModel.setGhostMode(true);
    expect(viewModel.h3References.single.assetId, isNull);
    expect(viewModel.h3References.single.bytes, isNotEmpty);

    final result = await viewModel.submit(prompt: 'Continue the movement.');

    expect(result, isNotNull);
    expect(sources.uploads, hasLength(1));
    expect(jobs.submitted, hasLength(1));
  });

  testWidgets('duration reads as the finished length for a continuation', (
    tester,
  ) async {
    final viewModel = _viewModel(
      templates: [_template(minimaxH3WorkflowId, fullH3: true)],
      jobs: _StubJobs(),
      sources: _StubSourceAssets(),
      initialH3Mode: MiniMaxH3GenerationMode.videoContinue,
      initialH3SourceAssetId: '33449737-9e39-4d53-8040-f39d5f7bc3ce',
    );
    await viewModel.load();
    expect(viewModel.h3Mode, MiniMaxH3GenerationMode.videoContinue);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: VideoGenerationSettings(viewModel: viewModel),
          ),
        ),
      ),
    );

    // A continuation renders only what it adds, so calling the number a
    // clip length would misstate what the user is choosing.
    expect(find.textContaining('finished length'), findsOneWidget);
    expect(
      find.textContaining('renders only the seconds you add'),
      findsOneWidget,
    );
    expect(find.textContaining('whole-second clip'), findsNothing);
  });

  testWidgets('MiniMax H3 exposes portrait and landscape output choices', (
    tester,
  ) async {
    final viewModel = _viewModel(
      templates: [_template(minimaxH3WorkflowId, fullH3: true)],
      jobs: _StubJobs(),
      sources: _StubSourceAssets(),
    );
    await viewModel.load();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: VideoGenerationSettings(viewModel: viewModel),
          ),
        ),
      ),
    );

    final orientation = tester.widget<SegmentedButton<String>>(
      find.byType(SegmentedButton<String>),
    );
    expect(orientation.selected, {'portrait'});
    expect(find.text('Portrait'), findsOneWidget);
    expect(find.text('Landscape'), findsOneWidget);
    expect(find.text('720 × 1280'), findsOneWidget);

    await tester.tap(find.text('Landscape'));
    await tester.pump();

    expect(viewModel.orientation, 'landscape');
    expect(viewModel.resolution, '1280 × 720');
  });

  testWidgets('duration still reads as a clip length everywhere else', (
    tester,
  ) async {
    final viewModel = _viewModel(
      templates: [_template(minimaxH3WorkflowId, fullH3: true)],
      jobs: _StubJobs(),
      sources: _StubSourceAssets(),
    );
    await viewModel.load();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: VideoGenerationSettings(viewModel: viewModel),
          ),
        ),
      ),
    );

    expect(find.textContaining('whole-second clip'), findsOneWidget);
    expect(find.textContaining('finished length'), findsNothing);
  });
  test('a continuation sends the chosen extension method', () async {
    final jobs = _StubJobs();
    final viewModel = _viewModel(
      templates: [_template(minimaxH3WorkflowId, fullH3: true)],
      jobs: jobs,
      sources: _StubSourceAssets(),
      initialH3Mode: MiniMaxH3GenerationMode.videoContinue,
      initialH3SourceAssetId: '33449737-9e39-4d53-8040-f39d5f7bc3ce',
    );
    await viewModel.load();

    // The default is the one-pass anchor.
    expect(viewModel.h3ExtensionMethod, MiniMaxH3ExtensionMethod.singlePass);
    viewModel.setH3ExtensionMethod(MiniMaxH3ExtensionMethod.chained);
    await viewModel.submit(
      prompt: 'integrated_multimodal_description: keep dancing',
    );

    expect(jobs.submitted, hasLength(1));
    final input = jobs.submitted.single['input'] as JsonMap;
    expect(input[minimaxH3ExtensionMethodInput], 'chained');
  });

  test('only a continuation carries an extension method', () async {
    final jobs = _StubJobs();
    final viewModel = _viewModel(
      templates: [_template(minimaxH3WorkflowId, fullH3: true)],
      jobs: jobs,
      sources: _StubSourceAssets(),
    );
    await viewModel.load();

    // Every other mode renders its whole duration, so the method is
    // meaningless and must not be sent.
    expect(viewModel.h3Mode, MiniMaxH3GenerationMode.textToVideo);
    viewModel.setH3ExtensionMethod(MiniMaxH3ExtensionMethod.chained);
    expect(viewModel.h3ExtensionMethod, MiniMaxH3ExtensionMethod.singlePass);

    await viewModel.submit(prompt: 'integrated_multimodal_description: a wave');
    final input = jobs.submitted.single['input'] as JsonMap;
    expect(input.containsKey(minimaxH3ExtensionMethodInput), isFalse);
  });
}
