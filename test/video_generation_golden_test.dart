@Tags(['golden'])
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/models/minimax_h3_generation_spec.dart';
import 'package:ii_os/repositories/job_repository.dart';
import 'package:ii_os/repositories/source_asset_repository.dart';
import 'package:ii_os/repositories/workflow_template_repository.dart';
import 'package:ii_os/screens/video_generation_screen.dart';
import 'package:ii_os/view_models/video_generation_view_model.dart';

import 'page_golden_harness.dart';

final class _Templates implements WorkflowTemplateRepository {
  const _Templates({this.fullH3 = false});

  final bool fullH3;

  @override
  Future<List<WorkflowTemplateModel>> list(
    String workspaceId, {
    String? workflowIdPrefix,
  }) async => [
    _template(ltxImageToVideoWorkflowId, 'LTX 2.3'),
    _template(seedVr2VideoUpscaleWorkflowId, 'SeedVR2 3B FP16'),
    _template(minimaxH3WorkflowId, 'MiniMax H3', fullH3: fullH3),
  ];
}

final class _Jobs implements JobRepository {
  @override
  Future<JsonMap> detail(String workspaceId, String jobId) async => const {};

  @override
  Future<JobListing> list(String workspaceId) async => JobListing.empty;

  @override
  Future<JsonMap> submit(String workspaceId, JobSubmission submission) async =>
      const {'jobId': 'video-1', 'status': 'requested'};
}

final class _Sources implements SourceAssetRepository {
  @override
  Future<String> upload({
    required String workspaceId,
    required String filename,
    required Uint8List bytes,
    required String contentType,
    required String expectedBucket,
    bool ghostMode = false,
  }) async => 'source-1';
}

WorkflowTemplateModel _template(
  String workflowId,
  String model, {
  bool fullH3 = false,
}) => WorkflowTemplateModel(
  id: 'acme/media#$workflowId',
  workflowId: workflowId,
  version: '1',
  displayName: model,
  model: model,
  repository: 'acme/media',
  enabled: true,
  disabledReason: '',
  inputs: {
    if (workflowId == minimaxH3WorkflowId)
      'duration_seconds': const WorkflowInputModel(
        type: 'number',
        required: true,
        minimum: 4,
        maximum: 15,
        defaultNumber: 15,
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

void main() {
  setUpAll(loadPageFonts);

  testWidgets('MiniMax H3 model toggle and selectable duration contract', (
    tester,
  ) async {
    final controller = pageController();
    addTearDown(controller.dispose);
    await pumpPage(
      tester,
      VideoGenerationScreen(
        controller: controller,
        templateRepository: _Templates(),
        jobRepository: _Jobs(),
        sourceAssetRepository: _Sources(),
      ),
    );

    expect(find.text('Prompting guide'), findsNothing);
    await tester.tap(find.text('MiniMax H3'));
    await tester.pump();

    expect(find.text('15 seconds'), findsOneWidget);
    expect(find.text('720 × 1280'), findsOneWidget);
    expect(find.text('Portrait'), findsOneWidget);
    expect(find.text('Landscape'), findsOneWidget);
    expect(find.text('24 FPS'), findsOneWidget);
    final durationSlider = tester.widget<Slider>(find.byType(Slider));
    expect(durationSlider.value, 15);
    expect(durationSlider.min, 4);
    expect(durationSlider.max, 15);
    expect(durationSlider.onChanged, isNotNull);
    expect(find.text('Choose source image'), findsNothing);
    expect(find.text('Check license terms and territory'), findsOneWidget);
    expect(find.text('Prompting guide'), findsOneWidget);
    expect(find.text('Render mode'), findsOneWidget);
    expect(find.text('Quality'), findsOneWidget);
    expect(find.text('Turbo'), findsOneWidget);
    await tester.tap(find.text('Turbo'));
    await tester.pump();
    expect(find.textContaining('Much faster generation'), findsOneWidget);
    expect(find.text('About 15 minutes on 24 GB GPU'), findsOneWidget);
    expect(find.text('Text to video'), findsOneWidget);
    expect(
      find.textContaining('currently supports text-to-video'),
      findsOneWidget,
    );
    expect(find.text('First frame'), findsNothing);
    expect(find.text('Video edit'), findsNothing);
    expect(find.text('Output'), findsOneWidget);
    expect(find.text('Stereo · 32 kHz'), findsOneWidget);
    expect(find.textContaining('from 4 to 15 seconds'), findsOneWidget);

    await tester.tap(find.text('Prompting guide'));
    await tester.pumpAndSettle();
    expect(find.text('Write a stronger MiniMax H3 prompt'), findsOneWidget);
    expect(find.text('Build a timed shot sequence'), findsOneWidget);
    expect(find.text('Separate scene sound from the score'), findsOneWidget);
    expect(
      find.textContaining('integrated_multimodal_description:'),
      findsOneWidget,
    );
    expect(find.textContaining('At 00:07.000'), findsOneWidget);
    expect(find.text('Read the official guide'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    final pageScroll = find
        .descendant(
          of: find.byType(SingleChildScrollView).first,
          matching: find.byType(Scrollable),
        )
        .first;
    tester.state<ScrollableState>(pageScroll).position.jumpTo(0);
    await tester.pump();
    await expectLater(
      find.byType(VideoGenerationScreen),
      matchesGoldenFile('goldens/video_generation_minimax_h3.png'),
    );
  });

  testWidgets('SeedVR2 presents one bounded video-upscale contract', (
    tester,
  ) async {
    final controller = pageController();
    addTearDown(controller.dispose);
    await pumpPage(
      tester,
      VideoGenerationScreen(
        controller: controller,
        templateRepository: const _Templates(),
        jobRepository: _Jobs(),
        sourceAssetRepository: _Sources(),
      ),
    );

    await tester.tap(find.text('SeedVR2 3B FP16'));
    await tester.pumpAndSettle();

    expect(find.text('Select source video'), findsOneWidget);
    expect(find.text('Cinematic prompt'), findsNothing);
    expect(find.text('Motion prompt'), findsNothing);
    expect(find.text('1080 shortest edge'), findsOneWidget);
    expect(find.text('Preserve source FPS'), findsOneWidget);
    expect(find.text('Remux source audio'), findsOneWidget);
    expect(find.text('Quality · 3B FP16'), findsOneWidget);
    await expectLater(
      find.byType(VideoGenerationScreen),
      matchesGoldenFile('goldens/video_generation_seedvr2.png'),
    );
  });

  testWidgets('MiniMax H3 multimodal catalog activates editing controls', (
    tester,
  ) async {
    final controller = pageController();
    addTearDown(controller.dispose);
    await pumpPage(
      tester,
      VideoGenerationScreen(
        controller: controller,
        templateRepository: const _Templates(fullH3: true),
        jobRepository: _Jobs(),
        sourceAssetRepository: _Sources(),
      ),
    );

    await tester.tap(find.text('MiniMax H3'));
    await tester.pump();
    final videoEditFinder = find.widgetWithText(ChoiceChip, 'Video edit');
    expect(tester.widget<ChoiceChip>(videoEditFinder).onSelected, isNotNull);
    await tester.tap(videoEditFinder);
    await tester.pump();

    expect(find.textContaining('Highest fine-detail fidelity'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Turbo'))
          .onSelected,
      isNull,
    );
    expect(find.text('Reference media'), findsOneWidget);
    expect(find.text('Add image'), findsOneWidget);
    expect(find.text('Add video'), findsOneWidget);
    expect(find.text('Add audio'), findsOneWidget);
    expect(find.text('Edit operation'), findsOneWidget);
    expect(find.textContaining('downloads directly'), findsOneWidget);
    await expectLater(
      find.byType(VideoGenerationScreen),
      matchesGoldenFile('goldens/video_generation_minimax_h3_library.png'),
    );

    await tester.ensureVisible(find.text('Add image'));
    await tester.tap(find.text('Add image'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Upload'), findsOneWidget);
  });
}
