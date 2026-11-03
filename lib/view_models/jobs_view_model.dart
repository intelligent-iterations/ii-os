import 'package:stacked/stacked.dart';

import '../models/models.dart';
import '../repositories/job_repository.dart';

/// State for the jobs list.
final class JobsViewModel extends BaseViewModel {
  JobsViewModel({required this._jobs, required this.workspaceId});

  final JobRepository _jobs;
  final String workspaceId;

  List<JsonMap> jobs = const [];
  bool stale = false;
  String? errorMessage;

  /// True only on the first load, when there is genuinely nothing to show.
  /// A background refresh must not blank a list the operator is reading.
  bool get showLoadingSurface => isBusy && jobs.isEmpty;

  Future<void> start() async {
    await load();
  }

  /// [quiet] refreshes in place without replacing a useful existing list.
  Future<void> load({bool quiet = false}) async {
    if (!quiet) setBusy(true);
    try {
      final listing = await _jobs.list(workspaceId);
      jobs = listing.jobs;
      stale = listing.stale;
      errorMessage = null;
    } on Object catch (error) {
      if (!quiet) errorMessage = error.toString();
    } finally {
      if (!quiet) setBusy(false);
      notifyListeners();
    }
  }
}
