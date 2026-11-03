import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart' show IiOsPalette;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/models.dart';
import '../models/workshop_pull_request.dart';
import '../theme/ii_os_tokens.dart';
import '../widgets/common.dart';

class WorkshopPullRequestPanel extends StatelessWidget {
  const WorkshopPullRequestPanel({
    required this.pullRequest,
    required this.loading,
    required this.error,
    required this.busy,
    required this.canMerge,
    required this.previousPass,
    required this.onOpen,
    required this.onRefresh,
    required this.onApproveAndMerge,
    required this.onResolveConflicts,
    required this.conflictResolutionUnavailable,
    super.key,
  });

  final WorkshopPullRequestModel? pullRequest;
  final bool loading;
  final String? error;
  final bool busy;
  final bool canMerge;
  final bool previousPass;
  final VoidCallback? onOpen;
  final VoidCallback? onRefresh;
  final VoidCallback? onApproveAndMerge;
  final VoidCallback? onResolveConflicts;
  final String? conflictResolutionUnavailable;

  @override
  Widget build(BuildContext context) {
    final pull = pullRequest;
    final palette = IiOsPalette.of(context);
    final mergeUnavailable = !canMerge
        ? 'Your workspace role does not allow pull request merges.'
        : pull?.draft == true
        ? 'Mark the pull request ready for review in GitHub first.'
        : pull?.mergeable == false
        ? 'GitHub reports a conflict or an unmet merge requirement.'
        : pull != null && !pull.canRequestMerge && !pull.merged
        ? 'This pull request is no longer open against dev.'
        : null;
    return Semantics(
      container: true,
      label: pull == null
          ? 'Agent pull request'
          : 'Pull request ${pull.number}. ${pull.statusLabel}.',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.info.container,
          border: Border.all(color: palette.info.text.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(IiOsRadii.md),
        ),
        child: Padding(
          padding: const EdgeInsets.all(IiOsSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PullRequestHeader(pullRequest: pull, loading: loading),
              if (pull != null) ...[
                IiOsGap.vXs,
                Text(
                  '${_shortSha(pull.headSha)} → ${pull.baseRef}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                ),
                if (pull.merged) ...[
                  IiOsGap.vXs,
                  _DeploymentStatus(pullRequest: pull),
                ],
              ],
              if (previousPass && pull?.merged == true)
                const _PreviousPassMessage(),
              _PullRequestMessages(
                pullRequest: pull,
                error: error,
                mergeUnavailable: mergeUnavailable,
                conflictResolutionUnavailable: conflictResolutionUnavailable,
              ),
              IiOsGap.vSm,
              _PullRequestActions(
                pullRequest: pull,
                loading: loading,
                error: error,
                busy: busy,
                mergeUnavailable: mergeUnavailable,
                onOpen: onOpen,
                onRefresh: onRefresh,
                onApproveAndMerge: onApproveAndMerge,
                onResolveConflicts: onResolveConflicts,
                conflictResolutionUnavailable: conflictResolutionUnavailable,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PullRequestMessages extends StatelessWidget {
  const _PullRequestMessages({
    required this.pullRequest,
    required this.error,
    required this.mergeUnavailable,
    required this.conflictResolutionUnavailable,
  });

  final WorkshopPullRequestModel? pullRequest;
  final String? error;
  final String? mergeUnavailable;
  final String? conflictResolutionUnavailable;

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error != null) ...[
          IiOsGap.vXs,
          Text(
            error!,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: palette.danger.text),
          ),
        ],
        if (mergeUnavailable != null && pullRequest?.merged != true) ...[
          IiOsGap.vXs,
          Text(mergeUnavailable!, style: Theme.of(context).textTheme.bodySmall),
        ],
        if (pullRequest?.hasMergeConflicts == true &&
            conflictResolutionUnavailable != null) ...[
          IiOsGap.vXs,
          Text(
            conflictResolutionUnavailable!,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _PreviousPassMessage extends StatelessWidget {
  const _PreviousPassMessage();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: IiOsSpacing.xs),
    child: Text(
      'Previous pass. This merged pull request remains as history; '
      'the current brief needs a new deployment.',
      style: Theme.of(context).textTheme.bodySmall,
    ),
  );
}

class _DeploymentStatus extends StatelessWidget {
  const _DeploymentStatus({required this.pullRequest});

  final WorkshopPullRequestModel pullRequest;

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    final succeeded = pullRequest.readyForQa;
    final failed = const {
      'failure',
      'error',
    }.contains(pullRequest.qaDeploymentState);
    return Row(
      children: [
        Icon(
          succeeded
              ? LucideIcons.badgeCheck
              : failed
              ? LucideIcons.triangleAlert
              : LucideIcons.clock3,
          size: 17,
          color: succeeded
              ? palette.brand.text
              : failed
              ? palette.danger.text
              : palette.info.text,
        ),
        IiOsGap.hXxs,
        Expanded(
          child: Text(
            pullRequest.qaDeploymentLabel,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _PullRequestHeader extends StatelessWidget {
  const _PullRequestHeader({required this.pullRequest, required this.loading});

  final WorkshopPullRequestModel? pullRequest;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final pull = pullRequest;
    final palette = IiOsPalette.of(context);
    return Row(
      children: [
        const Icon(LucideIcons.gitPullRequest, size: 20),
        IiOsGap.hXs,
        Expanded(
          child: Text(
            pull == null
                ? 'Agent pull request'
                : '#${pull.number} · ${pull.title}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        if (loading && pull == null)
          const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else if (pull != null)
          StatusPill(
            pull.statusLabel,
            color: pull.merged ? palette.brand.text : palette.info.text,
          ),
      ],
    );
  }
}

class _PullRequestActions extends StatelessWidget {
  const _PullRequestActions({
    required this.pullRequest,
    required this.loading,
    required this.error,
    required this.busy,
    required this.mergeUnavailable,
    required this.onOpen,
    required this.onRefresh,
    required this.onApproveAndMerge,
    required this.onResolveConflicts,
    required this.conflictResolutionUnavailable,
  });

  final WorkshopPullRequestModel? pullRequest;
  final bool loading;
  final String? error;
  final bool busy;
  final String? mergeUnavailable;
  final VoidCallback? onOpen;
  final VoidCallback? onRefresh;
  final VoidCallback? onApproveAndMerge;
  final VoidCallback? onResolveConflicts;
  final String? conflictResolutionUnavailable;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: IiOsSpacing.xs,
    runSpacing: IiOsSpacing.xs,
    children: [
      OutlinedButton.icon(
        onPressed: onOpen,
        icon: const Icon(LucideIcons.externalLink, size: 17),
        label: const Text('Open in GitHub'),
      ),
      if (onRefresh != null)
        TextButton.icon(
          onPressed: loading || busy ? null : onRefresh,
          icon: const Icon(LucideIcons.refreshCw, size: 17),
          label: Text(error == null ? 'Refresh PR' : 'Retry'),
        ),
      if (pullRequest?.hasMergeConflicts == true)
        FilledButton.tonalIcon(
          onPressed: busy || conflictResolutionUnavailable != null
              ? null
              : onResolveConflicts,
          icon: const Icon(LucideIcons.bot, size: 17),
          label: const Text('Resolve conflicts with agent'),
        )
      else if (pullRequest?.merged != true)
        FilledButton.icon(
          onPressed: busy || mergeUnavailable != null || pullRequest == null
              ? null
              : onApproveAndMerge,
          icon: const Icon(LucideIcons.gitMerge, size: 17),
          label: const Text('Approve & merge'),
        ),
    ],
  );
}

class WorkshopQaActions extends StatelessWidget {
  const WorkshopQaActions({
    required this.statusOptions,
    required this.busy,
    required this.onStatusChanged,
    super.key,
  });

  final List<JsonMap> statusOptions;
  final bool busy;
  final ValueChanged<String> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    final done = _option('Done');
    final failed = _option('QA failed');
    return Wrap(
      spacing: IiOsSpacing.xs,
      runSpacing: IiOsSpacing.xs,
      children: [
        OutlinedButton.icon(
          onPressed: busy || failed == null
              ? null
              : () => onStatusChanged(failed),
          icon: const Icon(LucideIcons.rotateCcw, size: 17),
          label: const Text('QA failed'),
        ),
        FilledButton.icon(
          onPressed: busy || done == null ? null : () => onStatusChanged(done),
          icon: const Icon(LucideIcons.badgeCheck, size: 17),
          label: const Text('QA passed · mark done'),
        ),
      ],
    );
  }

  String? _option(String name) => statusOptions
      .where((option) => option['name'] == name)
      .map((option) => option['id'])
      .whereType<String>()
      .firstOrNull;
}

String _shortSha(String value) =>
    value.length > 8 ? value.substring(0, 8) : value;

extension _WorkshopPullRequestFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
