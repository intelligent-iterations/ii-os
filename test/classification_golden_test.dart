@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/classification_decisions.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/repositories/classification_result_repository.dart';
import 'package:ii_os/repositories/job_repository.dart';
import 'package:ii_os/repositories/workflow_template_repository.dart';
import 'package:ii_os/screens/classification_screen.dart';
import 'package:ii_os/widgets/classification_results.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'golden_harness.dart';
import 'page_golden_harness.dart';

/// Goldens for the classification surface: the two design-system components
/// it introduced, the verified result card, and the page with the runtime
/// installed. Regenerate with `flutter test --tags golden --update-goldens`.

const _decisions = ClassificationDecisions(
  answers: [
    ClassificationChoiceAnswer(
      'tone',
      choice: 'angry',
      confidence: 0.7,
      distribution: [
        DecisionShare(label: 'angry', probability: 0.8),
        DecisionShare(label: 'calm', probability: 0.15),
        DecisionShare(label: 'excited', probability: 0.05),
      ],
    ),
    ClassificationYesNoAnswer('billing', yes: 0.98),
    ClassificationScoreAnswer(
      'urgency',
      score: 3.4,
      confidence: 0.42,
      distribution: [
        DecisionShare(label: '0 · None', probability: 0.01),
        DecisionShare(label: '1 · Very low', probability: 0.02),
        DecisionShare(label: '2 · Low', probability: 0.1),
        DecisionShare(label: '3 · Moderate', probability: 0.4),
        DecisionShare(label: '4 · High', probability: 0.37),
        DecisionShare(label: '5 · Very high', probability: 0.1),
      ],
    ),
  ],
  run: ClassificationRunFacts(
    model: 'autotrust/JEV-9B',
    revision: '7ac669b8fb476ba926491e3d1c39f9330d68dbed',
    decideSeconds: 0.41,
    loadSeconds: 38.2,
    stateTokens: 24,
    stateTruncated: true,
    device: 'Example 24 GB GPU',
  ),
  inputTokens: 412,
);

final class _InstalledTemplates implements WorkflowTemplateRepository {
  const _InstalledTemplates();

  @override
  Future<List<WorkflowTemplateModel>> list(
    String workspaceId, {
    String? workflowIdPrefix,
  }) async => const [
    WorkflowTemplateModel(
      id: 'acme/media#classification-open-jev-9b',
      workflowId: 'classification-open-jev-9b',
      version: '1',
      displayName: 'Open JEV 9B Classification',
      model: 'autotrust/JEV-9B',
      repository: 'acme/media',
      enabled: true,
      disabledReason: '',
      runtime: WorkflowRuntimeRequirement(
        status: WorkflowRuntimeStatus.available,
      ),
    ),
  ];
}

final class _UnusedJobs implements JobRepository {
  const _UnusedJobs();

  @override
  Future<JsonMap> submit(String workspaceId, JobSubmission submission) =>
      throw UnimplementedError();

  @override
  Future<JsonMap> detail(String workspaceId, String jobId) =>
      throw UnimplementedError();

  @override
  Future<JobListing> list(String workspaceId) async => JobListing.empty;
}

final class _UnusedResults implements ClassificationResultRepository {
  const _UnusedResults();

  @override
  Future<ClassificationDecisions> readDecisions({
    required String workspaceId,
    required String jobId,
    required String expectedBucket,
    required JsonMap artifact,
  }) => throw UnimplementedError();

  @override
  Future<void> consumeGhostJob({
    required String workspaceId,
    required String jobId,
  }) => throw UnimplementedError();
}

void main() {
  setUpAll(loadIiOsFonts);

  testWidgets('decision distribution and gated tabs', (tester) async {
    await tester.pumpWidget(
      goldenHarness(
        const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            IiOsDecisionDistribution(
              shares: [
                IiOsDecisionShare(
                  label: 'angry',
                  probability: 0.8,
                  chosen: true,
                ),
                IiOsDecisionShare(label: 'calm', probability: 0.15),
                IiOsDecisionShare(label: 'excited', probability: 0.05),
              ],
            ),
            SizedBox(height: 16),
            DefaultTabController(
              length: 3,
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  IiOsGatedTab(icon: LucideIcons.mic2, label: 'Narration'),
                  IiOsGatedTab(
                    icon: LucideIcons.listChecks,
                    label: 'Classify',
                    state: IiOsGateState.locked,
                    reason: 'Open JEV runtime not installed',
                  ),
                  IiOsGatedTab(
                    icon: LucideIcons.listChecks,
                    label: 'Classify',
                    state: IiOsGateState.pending,
                    reason: 'Open JEV runtime status not confirmed yet',
                  ),
                ],
              ),
            ),
          ],
        ),
        width: 420,
      ),
    );

    await expectLater(
      find.byType(Column).first,
      matchesGoldenFile('goldens/decision_widgets.png'),
    );
  });

  testWidgets('classification results show every answer type', (tester) async {
    await tester.pumpWidget(
      goldenHarness(
        const ClassificationResults(decisions: _decisions),
        width: 520,
      ),
    );

    await expectLater(
      find.byType(ClassificationResults),
      matchesGoldenFile('goldens/classification_results.png'),
    );
  });

  testWidgets('classification page with the runtime installed', (tester) async {
    await loadPageFonts();
    final controller = pageController();
    addTearDown(controller.dispose);

    await pumpPage(
      tester,
      ClassificationScreen(
        controller: controller,
        templateRepository: const _InstalledTemplates(),
        jobRepository: const _UnusedJobs(),
        resultRepository: const _UnusedResults(),
      ),
    );

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/pages/classification_ready.png'),
    );
  });
}
