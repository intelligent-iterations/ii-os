import 'models.dart';

final class WorkshopPullRequestModel {
  const WorkshopPullRequestModel({
    required this.repository,
    required this.number,
    required this.title,
    required this.url,
    required this.state,
    required this.draft,
    required this.merged,
    required this.mergeable,
    required this.mergeableState,
    required this.headRef,
    required this.headSha,
    required this.baseRef,
    required this.baseSha,
    this.mergeCommitSha = '',
    this.qaDeploymentState = '',
    this.qaDeploymentEnvironment = '',
    this.qaDeploymentSha = '',
    this.qaDeploymentCoversSha = '',
    this.qaDeploymentSucceeded = false,
    this.qaDeploymentEnvironmentUrl = '',
    this.qaDeploymentLogUrl = '',
  });

  factory WorkshopPullRequestModel.fromJson(JsonMap json) {
    final deployment = asJsonMap(json['qaDeployment']);
    return WorkshopPullRequestModel(
      repository: json['repository'] as String? ?? '',
      number: (json['number'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? '',
      url: json['url'] as String? ?? '',
      state: json['state'] as String? ?? '',
      draft: json['draft'] == true,
      merged: json['merged'] == true,
      mergeable: json['mergeable'] as bool?,
      mergeableState: json['mergeableState'] as String? ?? '',
      headRef: json['headRef'] as String? ?? '',
      headSha: json['headSha'] as String? ?? '',
      baseRef: json['baseRef'] as String? ?? '',
      baseSha: json['baseSha'] as String? ?? '',
      mergeCommitSha: json['mergeCommitSha'] as String? ?? '',
      qaDeploymentState: deployment['state'] as String? ?? '',
      qaDeploymentEnvironment: deployment['environment'] as String? ?? '',
      qaDeploymentSha: deployment['sha'] as String? ?? '',
      qaDeploymentCoversSha:
          deployment['coversSha'] as String? ??
          deployment['sha'] as String? ??
          '',
      qaDeploymentSucceeded: deployment['succeeded'] == true,
      qaDeploymentEnvironmentUrl: deployment['environmentUrl'] as String? ?? '',
      qaDeploymentLogUrl: deployment['logUrl'] as String? ?? '',
    );
  }

  final String repository;
  final int number;
  final String title;
  final String url;
  final String state;
  final bool draft;
  final bool merged;
  final bool? mergeable;
  final String mergeableState;
  final String headRef;
  final String headSha;
  final String baseRef;
  final String baseSha;
  final String mergeCommitSha;
  final String qaDeploymentState;
  final String qaDeploymentEnvironment;
  final String qaDeploymentSha;
  final String qaDeploymentCoversSha;
  final bool qaDeploymentSucceeded;
  final String qaDeploymentEnvironmentUrl;
  final String qaDeploymentLogUrl;

  bool get canRequestMerge =>
      state == 'open' && !draft && !merged && baseRef == 'dev';

  bool get hasMergeConflicts =>
      canRequestMerge && mergeable == false && mergeableState == 'dirty';

  String conflictResolutionRequest() =>
      '''Resolve the merge conflicts blocking this exact agent pull request.

Pull request: $url
Head: $headRef at $headSha
Target: $baseRef at $baseSha

Reapply the intended ticket changes on the latest $baseRef, preserve newer work already on $baseRef, and resolve every conflict deliberately. Update this pull request when it is still safe to do so; otherwise create a clean replacement that supersedes it. Run the repository's required validation and report the resulting pull request and evidence.''';

  bool get readyForQa =>
      merged &&
      mergeCommitSha.isNotEmpty &&
      qaDeploymentEnvironment == 'dev' &&
      qaDeploymentCoversSha == mergeCommitSha &&
      qaDeploymentSucceeded;

  String get qaDeploymentLabel => switch (qaDeploymentState) {
    'success' || 'inactive' when readyForQa => 'Dev deployment succeeded',
    'failure' || 'error' => 'Dev deployment failed',
    'queued' || 'pending' || 'in_progress' => 'Dev deployment in progress',
    'unavailable' => 'Deployment status unavailable',
    _ => 'Waiting for dev deployment',
  };

  String get statusLabel {
    if (merged) return 'Merged';
    if (draft) return 'Draft';
    if (state != 'open') return 'Closed';
    if (mergeable == false) return 'Blocked';
    if (mergeable == null) return 'Checking';
    return 'Ready to merge';
  }
}
