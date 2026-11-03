import 'package:stacked/stacked.dart';

import '../models/models.dart';
import '../repositories/job_repository.dart';
import '../services/mobile_update_platform.dart';

abstract final class HomeBusy {
  static const update = 'update';
  static const recent = 'recent';
}

/// Owns the authenticated mobile-release dispatch shown on the homepage.
final class HomeViewModel extends BaseViewModel {
  HomeViewModel({
    required this._jobs,
    required this.workspaceId,
    required this.platform,
    required this.canTriggerJobs,
    required this._enabledWorkflows,
    required this.mobileUpdateRepository,
  });

  final JobRepository _jobs;
  final Set<String> _enabledWorkflows;
  final String workspaceId;
  final MobileUpdatePlatform? platform;
  final bool canTriggerJobs;
  final String mobileUpdateRepository;

  JsonMap? submittedJob;

  /// The newest jobs in the workspace, so the landing page answers "what has
  /// been happening" instead of only counting it. The API returns them newest
  /// first; nothing is re-sorted here.
  List<JsonMap> recent = const [];

  bool get updating => busy(HomeBusy.update);

  bool get loadingRecent => busy(HomeBusy.recent);

  /// How many rows the panel shows. Enough to recognise the last session's
  /// work, short enough that it never becomes the page.
  static const recentLimit = 5;

  Future<void> loadRecent() async {
    setBusyForObject(HomeBusy.recent, true);
    try {
      final listing = await _jobs.list(workspaceId);
      recent = listing.jobs.take(recentLimit).toList(growable: false);
    } on Object {
      // The counters above are the page's contract; a failed activity read
      // leaves the panel empty rather than replacing the dashboard with an
      // error.
      recent = const [];
    } finally {
      setBusyForObject(HomeBusy.recent, false);
    }
  }

  bool get workflowEnabled {
    final key = _workflowKey;
    return key != null && _enabledWorkflows.contains(key);
  }

  String? get _workflowKey {
    final current = platform;
    final repository = mobileUpdateRepository.trim();
    if (current == null || repository.isEmpty) return null;
    return current.workflowKey(repository);
  }

  bool get canUpdate =>
      platform != null && canTriggerJobs && workflowEnabled && !updating;

  String get tooltip {
    final current = platform;
    if (current == null) {
      return 'Mobile updates are available on iOS and Android.';
    }
    if (!canTriggerJobs) {
      return 'You do not have permission to trigger application updates.';
    }
    if (_workflowKey == null) {
      return 'Mobile updates are not configured for this deployment.';
    }
    if (!workflowEnabled) {
      return 'Enable the ${current.label} update workflow for this workspace.';
    }
    return 'Publish the latest ${current.label} application update.';
  }

  Future<JsonMap?> update() async {
    final current = platform;
    final workflowKey = _workflowKey;
    if (current == null ||
        workflowKey == null ||
        !canTriggerJobs ||
        !workflowEnabled ||
        updating) {
      return null;
    }
    submittedJob = null;
    setError(null);
    setBusyForObject(HomeBusy.update, true);
    try {
      submittedJob = await _jobs.submit(
        workspaceId,
        JobSubmission(
          workflowKey: workflowKey,
          pageSlug: 'home',
          input: const {},
        ),
      );
      return submittedJob;
    } on Object catch (error) {
      setError(error);
      return null;
    } finally {
      setBusyForObject(HomeBusy.update, false);
    }
  }
}
