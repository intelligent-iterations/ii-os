@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/state/app_controller.dart';
import 'package:ii_os/widgets/job_submission_result.dart';

import 'golden_harness.dart';

void main() {
  setUpAll(loadIiOsFonts);

  testWidgets('failed video generation offers retry in place', (tester) async {
    tester.view.physicalSize = const Size(520, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = _controller();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      goldenHarness(
        JobSubmissionResult(
          controller: controller,
          result: const {
            'jobId': 'minimax-h3-reference-12345678',
            'status': 'failed',
            'errorCode': 'generation_failed',
          },
          mediaKind: GeneratedMediaKind.video,
          mediaAspectRatio: 16 / 9,
          onRetry: _unusedRetry,
        ),
        width: 440,
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(JobSubmissionResult),
      matchesGoldenFile('goldens/job_submission_result_recovery.png'),
    );
  });
}

Future<void> _unusedRetry() async {
  throw StateError('The golden never activates the retry control.');
}

AppController _controller() =>
    AppController()
      ..selectedAccess = const WorkspaceAccess(
        workspace: WorkspaceModel(
          id: 'workspace-1',
          name: 'Example',
          environment: 'dev',
          githubInstallationId: 12,
          repositories: ['acme-co/example-app'],
          projects: [],
          workflows: ['acme-co/example-app#text-to-video-minimax-h3'],
          artifactStorage: null,
        ),
        membership: MembershipModel(
          workspaceId: 'workspace-1',
          uid: 'editor-1',
          email: 'editor@example.com',
          role: 'editor',
          roleLabel: 'Editor',
          featureClaims: {'jobs.trigger'},
          capabilities: {'jobs.read', 'jobs.trigger'},
        ),
      );
