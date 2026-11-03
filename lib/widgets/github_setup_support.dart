part of 'github_setup_onboarding.dart';

/// The one surface allowed to render a check's own `label`, `detail`, and
/// `guidance`.
///
/// Rule 12 in `docs/ii-os-frontend.md` § Rules: those strings are authored for
/// whoever is debugging the repository, not for the person setting it up. They
/// render here, behind a collapsed disclosure that says so, and nowhere else.
/// `R12` in `tool/frontend_audit_rules.dart` allowlists this widget by name.
class _TechnicalChecks extends StatelessWidget {
  const _TechnicalChecks({required this.checks});

  final List<GitHubSetupCheckModel> checks;

  @override
  Widget build(BuildContext context) {
    final warningColor = IiOsPalette.of(context).warning.text;
    final passed = checks.where((check) => check.passed).length;
    final warnings = checks.where((check) => check.warning).length;
    final needsAttention = checks.length - passed - warnings;
    final ordered = [
      ...checks.where((check) => !check.dispatchable),
      ...checks.where((check) => check.warning),
      ...checks.where((check) => check.passed),
    ];
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      leading: Icon(
        needsAttention == 0 && warnings == 0
            ? LucideIcons.circleCheckBig
            : LucideIcons.listChecks,
        size: 18,
        color: needsAttention == 0 && warnings == 0
            ? IiOsColors.green
            : IiOsColors.amber,
      ),
      title: const Text('Technical details'),
      subtitle: Text(
        needsAttention == 0 && warnings == 0
            ? 'All $passed checks passed'
            : [
                if (needsAttention > 0) '$needsAttention need attention',
                if (warnings > 0) '$warnings recommended',
                '$passed passed',
              ].join(' · '),
      ),
      children: [
        for (final check in ordered)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: IiOsSpacing.xxs),
            leading: Icon(
              check.passed
                  ? LucideIcons.circleCheck
                  : check.warning
                  ? LucideIcons.triangleAlert
                  : check.unableToVerify
                  ? LucideIcons.cloudOff
                  : LucideIcons.circleAlert,
              size: 18,
              color: check.passed
                  ? IiOsColors.green
                  : check.warning
                  ? warningColor
                  : check.unableToVerify
                  ? IiOsColors.muted
                  : IiOsColors.amber,
            ),
            title: Text(check.label),
            subtitle: _technicalDetail(check).isEmpty
                ? null
                : Text(_technicalDetail(check)),
            trailing: StatusPill(
              check.passed
                  ? 'Passed'
                  : check.warning
                  ? 'Recommended'
                  : check.unableToVerify
                  ? 'Couldn\u2019t verify'
                  : 'Needs action',
              color: check.passed
                  ? IiOsColors.green
                  : check.warning
                  ? warningColor
                  : check.unableToVerify
                  ? IiOsColors.muted
                  : IiOsColors.amber,
            ),
          ),
      ],
    );
  }
}

/// Everything a check knows, for the disclosure that is allowed to show it.
///
/// `guidance` used to leak onto the focused step as a fallback explanation.
/// It lands here instead, so removing it from the primary surface loses
/// nothing for whoever is actually debugging.
String _technicalDetail(GitHubSetupCheckModel check) =>
    [check.detail, check.guidance].where((line) => line.isNotEmpty).join('\n');

class _SetupSupplementalDetails extends StatelessWidget {
  const _SetupSupplementalDetails({
    required this.checks,
    required this.ready,
    required this.actionInProgress,
    required this.blockedReason,
    required this.onAction,
  });

  final List<GitHubSetupCheckModel> checks;
  final bool ready;
  final bool actionInProgress;
  final GitHubSetupBlockedReason blockedReason;
  final void Function(GitHubSetupAction, GitHubSetupCheckModel) onAction;

  @override
  Widget build(BuildContext context) {
    final recommendation = checks.where((check) => check.warning).firstOrNull;
    if (ready && recommendation == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (recommendation != null) ...[
          IiOsGap.vSm,
          _SetupRecommendation(
            check: recommendation,
            actionInProgress: actionInProgress,
            blockedReason: blockedReason,
            onAction: onAction,
          ),
        ],
        IiOsGap.vSm,
        _TechnicalChecks(checks: checks),
      ],
    );
  }
}

class _LoadingSetup extends StatelessWidget {
  const _LoadingSetup();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: IiOsSpacing.xxxl),
    child: Center(child: CircularProgressIndicator()),
  );
}

class _SetupError extends StatelessWidget {
  const _SetupError({required this.message, required this.onRefresh});

  final String message;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: IiOsColors.amberTint,
      borderRadius: BorderRadius.circular(IiOsRadii.lg),
    ),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'We couldn\u2019t check your setup.',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          IiOsGap.vXxs,
          Text(message, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onRefresh,
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}

/// The wizard's names for setup tasks now come from the shared copy table, so
/// the Software Workshop cannot describe the same blocked repository in a
/// different vocabulary.
String _taskTitle(GitHubSetupCheckModel task) => setupTaskTitle(task);

String _taskExplanation(GitHubSetupCheckModel task) =>
    setupTaskExplanation(task);

/// Outstanding checks in this stage that the current task's button will not
/// resolve.
///
/// Every check sharing the focused task's action is a description of what that
/// one button is about to do. Listing those as work reads as a to-do list the
/// user is expected to work through by hand -- the exact failure this screen
/// shipped with, where "Install recommended agent permissions" sat above four
/// items the same button fixes.
List<GitHubSetupCheckModel> _laterTasks(
  GitHubSetupStageModel stage,
  GitHubSetupCheckModel task,
) => stage.outstanding
    .where((check) => check.suggestedAction != task.suggestedAction)
    .toList();

String _nextOutcome(GitHubSetupCheckModel task) {
  return switch (task.suggestedAction) {
    GitHubSetupAction.configureRepository =>
      'The Firebase function will use the workspace\u2019s Secret Manager key to ask GitHub for a short-lived installation token and read this repository directly.',
    GitHubSetupAction.configureGitHubApp =>
      'Save the required permissions, approve the installation update if GitHub asks, then return and check again. Deployment verification remains a separate recommendation.',
    GitHubSetupAction.refresh =>
      task.id == 'permission_bootstrap_tag'
          ? 'After the marker is pushed, check again. ii-os will verify it against the current dev commit.'
          : 'The Firebase function will retry GitHub directly. No workflow or runner starts.',
  };
}

String _actionLabel(GitHubSetupCheckModel task) =>
    switch (task.suggestedAction) {
      GitHubSetupAction.configureRepository => 'Enter repository details',
      GitHubSetupAction.configureGitHubApp => 'Open permission settings',
      GitHubSetupAction.refresh => 'Check again',
    };

/// The GitHub App permission a check refers to, or null when the check is not
/// about one.
///
/// Rule 12 (`docs/ii-os-frontend.md` § Rules): the name here is read as a
/// heading in GitHub's own settings UI, so it has to be GitHub's word for it.
/// Falling back to `check.label` printed an ii-os verification sentence where
/// the user was looking for a row to find.
/// What each permission is for, in the words of the person granting it.
///
/// Widening access to your own code is a decision. A row reading only
/// "Issues: none -> Read and write" asks for that decision without saying what
/// it buys, which earns either a refusal or an approval nobody read. The wording
/// names what the reader owns and what ii-os will do with it -- never the
/// mechanism, per rule 12 in `docs/ii-os-frontend.md` § Rules.
const _permissionReasons = {
  'github_app_actions': 'Lets ii-os start the CI/CD workflows you approve.',
  'github_app_contents':
      'Lets ii-os read repository code and publish approved changes.',
  'github_app_deployments':
      'Lets ii-os verify that the exact merged commit reached dev before QA starts.',
  'github_app_pull_requests':
      'Lets ii-os create and update pull requests. Auto-merge remains a separate, optional ii-os policy.',
};

/// What to do in GitHub once the values above are set.
const _permissionSteps = [
  'Open permission settings.',
  'Find each named permission and choose the value shown.',
  'Click Save changes, approve the update if GitHub asks, then return here.',
];

const _permissionNames = {
  'github_app_actions': 'Actions',
  'github_app_contents': 'Contents',
  'github_app_deployments': 'Deployments',
  'github_app_pull_requests': 'Pull requests',
};

PermissionChange? _permissionChange(GitHubSetupCheckModel check) {
  final name = _permissionNames[check.id];
  if (name == null) return null;
  return PermissionChange(
    name: name,
    section: 'Repository permissions',
    currentValue: check.currentValue.isEmpty
        ? 'Not configured'
        : check.currentValue,
    requiredValue: check.requiredValue.isEmpty
        ? 'Read and write'
        : check.requiredValue,
    reason: _permissionReasons[check.id] ?? '',
  );
}

IconData _actionIcon(GitHubSetupAction action) => switch (action) {
  GitHubSetupAction.configureRepository => LucideIcons.gitBranch,
  GitHubSetupAction.configureGitHubApp => LucideIcons.externalLink,
  GitHubSetupAction.refresh => LucideIcons.refreshCw,
};

String _completionTitle(String id) => switch (id) {
  'repository' => 'GitHub App connected',
  'permissions' => 'Repository access is ready',
  _ => 'GitHub is connected',
};

String _completionDetail(String id) => switch (id) {
  'repository' =>
    'The Firebase function used the workspace key and reached the selected repository directly.',
  'permissions' =>
    'Actions, Contents, and Pull requests are ready. Deployments read-only is recommended for a verified QA handoff.',
  _ =>
    'The App can reach the selected repository with the permissions agent work needs.',
};
