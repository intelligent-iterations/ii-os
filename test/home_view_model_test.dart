import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/repositories/job_repository.dart';
import 'package:ii_os/services/mobile_update_platform.dart';
import 'package:ii_os/view_models/home_view_model.dart';

final class _RecordingJobs implements JobRepository {
  @override
  Future<JobListing> list(String workspaceId) async => JobListing.empty;

  @override
  Future<JsonMap> detail(String workspaceId, String jobId) async => const {};

  _RecordingJobs({this.failure});

  final Object? failure;
  final List<JsonMap> submissions = [];

  @override
  Future<JsonMap> submit(String workspaceId, JobSubmission submission) async {
    if (failure case final failure?) throw failure;
    submissions.add(submission.body(workspaceId));
    return const {'jobId': 'release-1', 'status': 'dispatching'};
  }
}

const _implementationRepository = 'example-org/example-app-deploy';

HomeViewModel _viewModel(
  MobileUpdatePlatform platform,
  _RecordingJobs jobs, {
  bool canTrigger = true,
  bool enabled = true,
}) => HomeViewModel(
  jobs: jobs,
  workspaceId: 'workspace-1',
  platform: platform,
  canTriggerJobs: canTrigger,
  enabledWorkflows: enabled
      ? {platform.workflowKey(_implementationRepository)}
      : const {},
  mobileUpdateRepository: _implementationRepository,
);

void main() {
  test('Android update dispatches the Google Play workflow input', () async {
    final jobs = _RecordingJobs();
    final viewModel = _viewModel(MobileUpdatePlatform.android, jobs);

    final result = await viewModel.update();

    expect(result?['jobId'], 'release-1');
    expect(jobs.submissions, hasLength(1));
    expect(jobs.submissions.single, {
      'workflowKey': 'example-org/example-app-deploy#mobile-update-android',
      'notificationDeepLink': '/workspaces/workspace-1/home',
      'input': <String, Object?>{},
    });
  });

  test('iOS update dispatches the App Store workflow input', () async {
    final jobs = _RecordingJobs();
    final viewModel = _viewModel(MobileUpdatePlatform.ios, jobs);

    await viewModel.update();

    expect(
      jobs.submissions.single['workflowKey'],
      'example-org/example-app-deploy#mobile-update-ios',
    );
    expect(jobs.submissions.single['input'], <String, Object?>{});
  });

  test('disabled workflow cannot dispatch', () async {
    final jobs = _RecordingJobs();
    final viewModel = _viewModel(
      MobileUpdatePlatform.ios,
      jobs,
      enabled: false,
    );

    expect(viewModel.canUpdate, isFalse);
    expect(await viewModel.update(), isNull);
    expect(jobs.submissions, isEmpty);
  });

  test('missing jobs permission cannot dispatch', () async {
    final jobs = _RecordingJobs();
    final viewModel = _viewModel(
      MobileUpdatePlatform.android,
      jobs,
      canTrigger: false,
    );

    expect(viewModel.canUpdate, isFalse);
    expect(await viewModel.update(), isNull);
    expect(jobs.submissions, isEmpty);
  });

  test('missing implementation repository fails closed', () async {
    final jobs = _RecordingJobs();
    final viewModel = HomeViewModel(
      jobs: jobs,
      workspaceId: 'workspace-1',
      platform: MobileUpdatePlatform.android,
      canTriggerJobs: true,
      enabledWorkflows: const {
        'example-org/example-app-deploy#mobile-update-android',
      },
      mobileUpdateRepository: '',
    );

    expect(viewModel.canUpdate, isFalse);
    expect(viewModel.tooltip, contains('not configured'));
    expect(await viewModel.update(), isNull);
    expect(jobs.submissions, isEmpty);
  });

  test('dispatch failure is exposed without leaving the button busy', () async {
    final jobs = _RecordingJobs(
      failure: const FormatException('Release dispatch failed.'),
    );
    final viewModel = _viewModel(MobileUpdatePlatform.ios, jobs);

    expect(await viewModel.update(), isNull);
    expect(viewModel.hasError, isTrue);
    expect(viewModel.updating, isFalse);
  });
}
