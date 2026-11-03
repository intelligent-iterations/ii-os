import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/state/app_controller.dart';
import 'package:ii_os/theme/ii_os_theme.dart';
import 'package:ii_os/widgets/job_submission_result.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  testWidgets('active submitted jobs expose a mobile-safe cancel action', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(
          body: JobSubmissionResult(
            controller: controller,
            result: const {'jobId': 'request-12345678', 'status': 'dispatched'},
          ),
        ),
      ),
    );

    expect(find.text('Cancel job'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('finished submitted jobs do not expose cancellation', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(
          body: JobSubmissionResult(
            controller: controller,
            result: const {'jobId': 'request-12345678', 'status': 'completed'},
          ),
        ),
      ),
    );

    expect(find.text('Cancel job'), findsNothing);
  });

  testWidgets('active jobs keep a progress indicator visible', (tester) async {
    final controller = _controller();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(
          body: JobSubmissionResult(
            controller: controller,
            result: const {'jobId': 'request-12345678', 'status': 'running'},
          ),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('active jobs explain their estimated GPU time', (tester) async {
    final controller = _controller();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(
          body: JobSubmissionResult(
            controller: controller,
            result: const {
              'jobId': 'request-12345678',
              'status': 'running',
              'runtimeEstimate': {
                'estimatedSeconds': 900,
                'hardware': '24 GB GPU',
                'measuredAt': '2026-08-14',
                'baselineOutputSeconds': 15,
                'baselineRuntimeSeconds': 900,
                'selectedInputs': {'performance_mode': 'turbo'},
              },
            },
          ),
        ),
      ),
    );

    expect(find.text('About 15 minutes on 24 GB GPU'), findsOneWidget);
    expect(find.textContaining('Queueing, setup, and uploads'), findsOneWidget);
  });

  testWidgets('image jobs reserve a loading media surface until completion', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(
          body: JobSubmissionResult(
            controller: controller,
            result: const {'jobId': 'request-12345678', 'status': 'running'},
            mediaKind: GeneratedMediaKind.image,
          ),
        ),
      ),
    );

    expect(find.text('Generating image\u2026'), findsOneWidget);
    expect(find.byType(AspectRatio), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNWidgets(2));
  });

  testWidgets('video failures remain inside the expected media surface', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(
          body: JobSubmissionResult(
            controller: controller,
            result: const {'jobId': 'request-12345678', 'status': 'failed'},
            mediaKind: GeneratedMediaKind.video,
          ),
        ),
      ),
    );

    expect(find.text('Failed before a video was produced.'), findsOneWidget);
    expect(
      find.textContaining('failed before a video was produced'),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('failed generation exposes one guarded retry action', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    var retries = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(
          body: JobSubmissionResult(
            controller: controller,
            result: const {'jobId': 'request-12345678', 'status': 'failed'},
            mediaKind: GeneratedMediaKind.video,
            onRetry: () async {
              retries += 1;
            },
          ),
        ),
      ),
    );

    expect(find.text('Retry generation'), findsOneWidget);
    await tester.tap(find.text('Retry generation'));
    await tester.pump();
    expect(retries, 1);
  });

  testWidgets('completed media jobs are not ready without their artifact', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(
          body: JobSubmissionResult(
            controller: controller,
            result: const {
              'jobId': 'request-12345678',
              'status': 'completed',
              'artifacts': <Object?>[],
            },
            mediaKind: GeneratedMediaKind.image,
          ),
        ),
      ),
    );

    expect(find.text('artifact missing'), findsOneWidget);
    expect(
      find.textContaining('completed, but no image was attached'),
      findsOneWidget,
    );
  });

  testWidgets('song jobs reserve an audio loading surface', (tester) async {
    final controller = _controller();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(
          body: JobSubmissionResult(
            controller: controller,
            result: const {'jobId': 'song-12345678', 'status': 'running'},
            mediaKind: GeneratedMediaKind.audio,
          ),
        ),
      ),
    );

    expect(find.text('Generating song\u2026'), findsOneWidget);
    expect(find.byIcon(LucideIcons.audioLines), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNWidgets(2));
  });

  testWidgets('narration jobs can override the audio loading label', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(
          body: JobSubmissionResult(
            controller: controller,
            result: const {'jobId': 'narration-12345678', 'status': 'running'},
            mediaKind: GeneratedMediaKind.audio,
            mediaLabel: 'narration',
          ),
        ),
      ),
    );

    expect(find.text('Generating narration\u2026'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNWidgets(2));
  });

  testWidgets('failed jobs explain that no image was produced', (tester) async {
    final controller = _controller();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(
          body: JobSubmissionResult(
            controller: controller,
            result: const {
              'jobId': 'request-12345678',
              'status': 'failed',
              'errorCode': 'runner_start_failed',
            },
          ),
        ),
      ),
    );

    expect(
      find.textContaining('failed before an image was produced'),
      findsOneWidget,
    );
    expect(find.textContaining('runner_start_failed'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
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
          workflows: ['acme-co/example-app#image-create'],
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
