import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/repositories/job_repository.dart';
import 'package:ii_os/screens/home_screen.dart';
import 'package:ii_os/services/mobile_update_platform.dart';
import 'package:ii_os/state/app_controller.dart';
import 'package:ii_os/theme/ii_os_theme.dart';

const _implementationRepository = 'example-org/example-app-deploy';

final class _RecordingJobs implements JobRepository {
  @override
  Future<JobListing> list(String workspaceId) async => JobListing.empty;

  @override
  Future<JsonMap> detail(String workspaceId, String jobId) async => const {};

  final List<JsonMap> submissions = [];

  @override
  Future<JsonMap> submit(String workspaceId, JobSubmission submission) async {
    submissions.add(submission.body(workspaceId));
    return const {'jobId': 'release-1', 'status': 'dispatching'};
  }
}

AppController _controller(MobileUpdatePlatform platform) => AppController()
  ..session = const SessionModel(
    user: UserProfile(
      uid: 'owner-1',
      email: 'owner@example.com',
      displayName: 'Owner',
      isOwner: true,
    ),
    workspaces: [],
  )
  ..selectedAccess = WorkspaceAccess(
    workspace: WorkspaceModel(
      id: 'workspace-1',
      name: 'Mobile releases',
      environment: 'dev',
      githubInstallationId: 12,
      repositories: const [_implementationRepository],
      projects: const [],
      workflows: [platform.workflowKey(_implementationRepository)],
      artifactStorage: null,
    ),
    membership: const MembershipModel(
      workspaceId: 'workspace-1',
      uid: 'owner-1',
      email: 'owner@example.com',
      role: 'owner',
      roleLabel: 'Owner',
      featureClaims: {},
      capabilities: {'workspace.read', 'jobs.trigger'},
    ),
  );

Widget _harness({
  required AppController controller,
  required JobRepository jobs,
  required MobileUpdatePlatform? platform,
}) => MaterialApp(
  theme: IiOsTheme.light(),
  home: Scaffold(
    body: HomeScreen(
      controller: controller,
      jobs: jobs,
      platformResolver: () => platform,
      mobileUpdateRepository: _implementationRepository,
    ),
  ),
);

void main() {
  test('native platform detection distinguishes Android and iOS', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(detectMobileUpdatePlatform(), MobileUpdatePlatform.android);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(detectMobileUpdatePlatform(), MobileUpdatePlatform.ios);
  });

  testWidgets('Update is hidden outside native iOS and Android', (
    tester,
  ) async {
    final controller = _controller(MobileUpdatePlatform.android);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _harness(controller: controller, jobs: _RecordingJobs(), platform: null),
    );

    expect(find.text('Update'), findsNothing);
  });

  for (final platform in MobileUpdatePlatform.values) {
    testWidgets('Update dispatches on ${platform.label}', (tester) async {
      final jobs = _RecordingJobs();
      final controller = _controller(platform);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _harness(controller: controller, jobs: jobs, platform: platform),
      );
      expect(find.text('Update'), findsOneWidget);

      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();

      expect(jobs.submissions, hasLength(1));
      expect(find.text('${platform.label} update queued.'), findsOneWidget);
    });
  }
}
