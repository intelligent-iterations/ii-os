import '../models/models.dart';
import '../services/api_client.dart';

/// A generation job request, built by a ViewModel and posted by a repository.
///
/// Screens used to assemble this body inline, which is how the deep link and
/// the `input` shape drifted between the image, video, and song surfaces.
final class JobSubmission {
  const JobSubmission({
    required this.workflowKey,
    required this.pageSlug,
    required this.input,
    this.ghostMode = false,
    this.keptEnhancedText = false,
  });

  final String workflowKey;

  /// The page a completion notification should open, e.g. `images`.
  final String pageSlug;

  final JsonMap input;

  /// Keeps generated media only long enough for this browser to download it.
  final bool ghostMode;

  /// The person enhanced this text and kept the result.
  ///
  /// Dispatch enhances the prompt again on its way out, which would rewrite
  /// text they already reviewed and accepted -- the one edit nobody asked for.
  final bool keptEnhancedText;

  JsonMap body(String workspaceId) => {
    'workflowKey': workflowKey,
    if (ghostMode) 'ghostMode': true,
    if (keptEnhancedText) 'promptEnhancementBypass': 'user_enhanced',
    if (!ghostMode)
      'notificationDeepLink': Uri(
        pathSegments: ['', 'workspaces', workspaceId, pageSlug],
      ).toString(),
    'input': input,
  };
}

/// A page of jobs and whether the control plane considers it stale.
///
/// `stale` is not an error: the list is real but the upstream refresh is
/// lagging, so the screen keeps showing it and says so rather than blanking.
final class JobListing {
  const JobListing({required this.jobs, required this.stale});

  final List<JsonMap> jobs;
  final bool stale;

  static const empty = JobListing(jobs: [], stale: false);
}

/// The single owner of `v1/workspaces/{id}/jobs`.
abstract interface class JobRepository {
  /// Submits a generation job and returns the created job record.
  Future<JsonMap> submit(String workspaceId, JobSubmission submission);

  /// Every job in the workspace, newest first as the API returns them.
  Future<JobListing> list(String workspaceId);

  /// One job, including the fields the list omits.
  Future<JsonMap> detail(String workspaceId, String jobId);
}

final class JobApiRepository implements JobRepository {
  const JobApiRepository(this.api);

  final ApiClient api;

  @override
  Future<JsonMap> submit(String workspaceId, JobSubmission submission) async {
    final response = await api.post(
      'v1/workspaces/$workspaceId/jobs',
      body: submission.body(workspaceId),
    );
    return asJsonMap(response['data']);
  }

  @override
  Future<JobListing> list(String workspaceId) async {
    final response = await api.get('v1/workspaces/$workspaceId/jobs');
    return parseJobListing(response);
  }

  @override
  Future<JsonMap> detail(String workspaceId, String jobId) {
    return api.get(
      'v1/workspaces/$workspaceId/jobs/${Uri.encodeComponent(jobId)}',
    );
  }
}

/// Parses a job-listing response.
///
/// Split from the request so the wire format is testable without a signed-in
/// Firebase user. Type-checked rather than cast: a malformed payload degrades
/// to an empty list, which the screen can render, instead of throwing a
/// TypeError that surfaces as an unexplained red screen.
JobListing parseJobListing(JsonMap response) {
  final raw = response['jobs'];
  return JobListing(
    jobs: raw is List<Object?>
        ? raw.map(asJsonMap).toList(growable: false)
        : const [],
    stale: response['stale'] is bool && response['stale'] as bool,
  );
}
