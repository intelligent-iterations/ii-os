import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart'
    show
        InlineFormError,
        PermissionChange,
        PermissionChangeGuide,
        ReviewedCommitGuide;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/github_setup_readiness.dart';
import '../theme/ii_os_theme.dart';
import '../theme/ii_os_tokens.dart';
import 'common.dart';
import '../models/github_setup_copy.dart';

part 'github_setup_support.dart';
part 'github_setup_automation.dart';
part 'github_setup_header.dart';
part 'github_setup_progress.dart';

/// Why the signed-in account cannot run [action] here, or null when it can.
///
/// The reason travels with the control so the button can be disabled and the
/// sentence rendered beside it. Returning it from a callback keeps this card
/// free of `AppController` (rule 5 in `docs/ii-os-frontend.md` § Rules) while
/// still letting the screen answer from the viewer's real membership claims.
typedef GitHubSetupBlockedReason = String? Function(GitHubSetupAction action);

class AgentReadinessCard extends StatelessWidget {
  const AgentReadinessCard({
    required this.readiness,
    required this.repository,
    required this.repositories,
    required this.step,
    required this.loading,
    required this.error,
    required this.actionInProgress,
    required this.blockedReason,
    required this.onRepositoryChanged,
    required this.onStepChanged,
    required this.onAction,
    required this.onOpenWorkshop,
    required this.onRefresh,
    this.taskStatus,
    super.key,
  });

  final GitHubSetupReadinessModel? readiness;
  final String? repository;
  final List<String> repositories;
  final String? step;
  final bool loading;
  final String? error;
  final bool actionInProgress;
  final GitHubSetupBlockedReason blockedReason;
  final ValueChanged<String?> onRepositoryChanged;
  final ValueChanged<String> onStepChanged;
  final void Function(GitHubSetupAction action, GitHubSetupCheckModel check)
  onAction;
  final VoidCallback onOpenWorkshop;
  final VoidCallback onRefresh;
  final Widget? taskStatus;

  @override
  Widget build(BuildContext context) {
    final selected = repository;
    final stages = readiness?.stagesFor(selected ?? '') ?? const [];
    final repositoryReady =
        stages.length == 2 && stages.every((stage) => stage.ready);
    final ready = repositoryReady;
    final active = _activeStage(stages, step);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WizardHeader(ready: ready, loading: loading),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _RepositoryPicker(
                  repository: selected,
                  repositories: repositories,
                  health: selected == null
                      ? null
                      : readiness?.healthFor(selected),
                  statusLabel: _repositoryStatusLabel(
                    selected == null ? null : readiness?.healthFor(selected),
                    active,
                  ),
                  onChanged: onRepositoryChanged,
                ),
                IiOsGap.vLg,
                _ProgressSteps(
                  stages: stages,
                  activeId: repositoryReady ? 'complete' : active?.id,
                  onSelected: onStepChanged,
                ),
                const SizedBox(height: 22),
                if (error != null)
                  _SetupError(message: error!, onRefresh: onRefresh)
                else if (loading && readiness == null)
                  const _LoadingSetup()
                else if (ready)
                  _WorkshopReady(onOpenWorkshop: onOpenWorkshop)
                else if (active == null)
                  _SetupError(
                    message: 'No setup task was returned.',
                    onRefresh: onRefresh,
                  )
                else
                  _FocusedStep(
                    stage: active,
                    number: stages.indexOf(active) + 1,
                    total: stages.length,
                    loading: loading,
                    actionInProgress: actionInProgress,
                    blockedReason: blockedReason,
                    onContinue: () => _continueFrom(
                      stages,
                      stages.indexOf(active),
                      onStepChanged,
                      onOpenWorkshop,
                    ),
                    onAction: onAction,
                    onRefresh: onRefresh,
                    taskStatus: taskStatus,
                  ),
                _SetupSupplementalDetails(
                  checks: readiness?.checksFor(selected ?? '') ?? const [],
                  ready: ready,
                  actionInProgress: actionInProgress,
                  blockedReason: blockedReason,
                  onAction: onAction,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

GitHubSetupStageModel? _activeStage(
  List<GitHubSetupStageModel> stages,
  String? requested,
) {
  final requestedIndex = stages.indexWhere((stage) => stage.id == requested);
  if (requestedIndex >= 0 &&
      stages.take(requestedIndex).every((stage) => stage.ready)) {
    return stages[requestedIndex];
  }
  return stages.where((stage) => !stage.ready).firstOrNull ?? stages.lastOrNull;
}

void _continueFrom(
  List<GitHubSetupStageModel> stages,
  int index,
  ValueChanged<String> onStepChanged,
  VoidCallback onOpenWorkshop,
) {
  if (index + 1 < stages.length) {
    onStepChanged(stages[index + 1].id);
  } else {
    onOpenWorkshop();
  }
}

class _FocusedStep extends StatelessWidget {
  const _FocusedStep({
    required this.stage,
    required this.number,
    required this.total,
    required this.loading,
    required this.actionInProgress,
    required this.blockedReason,
    required this.onContinue,
    required this.onAction,
    required this.onRefresh,
    required this.taskStatus,
  });

  final GitHubSetupStageModel stage;
  final int number;
  final int total;
  final bool loading;
  final bool actionInProgress;
  final GitHubSetupBlockedReason blockedReason;
  final VoidCallback onContinue;
  final void Function(GitHubSetupAction, GitHubSetupCheckModel) onAction;
  final VoidCallback onRefresh;
  final Widget? taskStatus;

  @override
  Widget build(BuildContext context) {
    if (stage.ready) {
      return _CompletedStep(
        stage: stage,
        number: number,
        onContinue: onContinue,
      );
    }
    final task = stage.nextTask;
    if (task == null) {
      return _SetupError(
        message: 'This step has no verifiable setup task.',
        onRefresh: onRefresh,
      );
    }
    final action = task.suggestedAction;
    final permissionChanges = action == GitHubSetupAction.configureGitHubApp
        ? stage.outstanding.map(_permissionChange).nonNulls.toList()
        : const <PermissionChange>[];
    final external = action == GitHubSetupAction.configureGitHubApp;
    final needsReviewMarker = task.id == 'permission_bootstrap_tag';
    final later = _laterTasks(stage, task);
    final blocked = blockedReason(action);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: IiOsColors.blue),
        borderRadius: BorderRadius.circular(IiOsRadii.xl),
        color: IiOsColors.blue.withValues(alpha: 0.035),
      ),
      child: Padding(
        padding: const EdgeInsets.all(IiOsSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Step $number of $total',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: IiOsColors.blue,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                StatusPill(
                  actionInProgress ? 'In progress' : 'Action needed',
                  color: actionInProgress ? IiOsColors.blue : IiOsColors.amber,
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              permissionChanges.isEmpty
                  ? _taskTitle(task)
                  : 'Give ii-os repository access',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            IiOsGap.vXs,
            Text(
              permissionChanges.isEmpty
                  ? _taskExplanation(task)
                  : 'Grant the required permissions shown below for the selected repositories, then save and come back.',
            ),
            if (needsReviewMarker) ...[
              IiOsGap.vMd,
              ReviewedCommitGuide(
                subject: '${task.repository} on dev',
                marker: task.requiredValue,
                command: task.command,
              ),
            ] else if (permissionChanges.isNotEmpty) ...[
              IiOsGap.vMd,
              PermissionChangeGuide(
                changes: permissionChanges,
                steps: _permissionSteps,
              ),
            ] else if (later.isNotEmpty) ...[
              IiOsGap.vMd,
              _OutstandingChecks(checks: later),
            ],
            IiOsGap.vMd,
            _NextOutcome(text: _nextOutcome(task)),
            if (taskStatus == null) ...[
              IiOsGap.vLg,
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: actionInProgress || blocked != null
                        ? null
                        : () => onAction(action, task),
                    icon: actionInProgress
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(_actionIcon(action), size: 17),
                    label: Text(
                      actionInProgress ? 'Working\u2026' : _actionLabel(task),
                    ),
                  ),
                  if (external)
                    OutlinedButton.icon(
                      onPressed: loading ? null : onRefresh,
                      icon: const Icon(LucideIcons.circleCheck, size: 17),
                      label: Text(
                        action == GitHubSetupAction.configureGitHubApp
                            ? 'Check my GitHub setup'
                            : 'Check again',
                      ),
                    ),
                ],
              ),
            ],
            InlineFormError(message: blocked),
            if (taskStatus != null) ...[
              const SizedBox(height: 18),
              taskStatus!,
            ],
          ],
        ),
      ),
    );
  }
}

class _NextOutcome extends StatelessWidget {
  const _NextOutcome({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: IiOsColors.surface,
      borderRadius: BorderRadius.circular(IiOsRadii.lg),
      border: Border.all(color: IiOsColors.border),
    ),
    child: Padding(
      padding: const EdgeInsets.all(IiOsSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(LucideIcons.arrowRight, size: 17, color: IiOsColors.blue),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What happens next',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                IiOsGap.vXxs,
                Text(text),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// What is still ahead in this step once the focused task is done.
///
/// Renders `_taskTitle`, never `check.label` -- rule 12 in
/// `docs/ii-os-frontend.md` § Rules. The heading carries no count, because the
/// list is the count and a second denominator on this card only competes with
/// the focused step counter.
class _OutstandingChecks extends StatelessWidget {
  const _OutstandingChecks({required this.checks});

  final List<GitHubSetupCheckModel> checks;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: IiOsColors.canvas,
      borderRadius: BorderRadius.circular(IiOsRadii.lg),
      border: Border.all(color: IiOsColors.border),
    ),
    child: Padding(
      padding: const EdgeInsets.all(IiOsSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'After this, still in this step',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          IiOsGap.vXs,
          for (final check in checks)
            Padding(
              padding: const EdgeInsets.only(top: IiOsSpacing.xxs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    check.unableToVerify
                        ? LucideIcons.cloudOff
                        : LucideIcons.circleAlert,
                    size: 16,
                    color: IiOsColors.amber,
                  ),
                  const SizedBox(width: 7),
                  Expanded(child: Text(_taskTitle(check))),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
