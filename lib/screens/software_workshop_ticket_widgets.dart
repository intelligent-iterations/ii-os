import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/agent_permission.dart';
import '../models/models.dart';
import '../models/workshop_ticket.dart';
import '../models/workshop_pull_request.dart';
import '../theme/ii_os_theme.dart';
import '../theme/ii_os_tokens.dart';
import '../widgets/common.dart';
import 'software_workshop_ticket_state_summary.dart';
import 'software_workshop_pull_request_widgets.dart';

part 'software_workshop_ticket_notices.dart';

class WorkshopTicketListCard extends StatelessWidget {
  const WorkshopTicketListCard({
    required this.ticket,
    required this.selected,
    required this.onSelected,
    this.accentColor,
    super.key,
  });

  final WorkshopTicket ticket;
  final bool selected;
  final VoidCallback onSelected;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? IiOsColors.green;
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label:
          '${ticket.repository} ticket ${ticket.number}. ${ticket.title}. '
          'Status: ${ticket.displayStatus}. Next: ${ticket.nextActionLabel}.',
      onTap: onSelected,
      excludeSemantics: true,
      child: Card(
        color: selected ? accent.withValues(alpha: 0.055) : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(IiOsRadii.md),
          side: BorderSide(
            color: selected ? accent : IiOsColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          onTap: onSelected,
          borderRadius: BorderRadius.circular(IiOsRadii.md),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${ticket.repository} #${ticket.number}',
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    IiOsGap.hXs,
                    StatusPill(ticket.displayStatus),
                  ],
                ),
                const SizedBox(height: 9),
                Text(
                  ticket.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                _TicketNextAction(ticket: ticket),
                IiOsGap.vXs,
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _CompactFact(
                      icon: ticket.structured
                          ? LucideIcons.clipboardCheck
                          : LucideIcons.clipboardX,
                      label: ticket.structured
                          ? 'Brief ready'
                          : 'Brief incomplete',
                    ),
                    _CompactFact(
                      icon: ticket.permissionProfile == 'none'
                          ? LucideIcons.shieldAlert
                          : LucideIcons.shieldCheck,
                      label: ticket.permissionProfile == 'none'
                          ? 'No agent access'
                          : ticket.permissionProfile,
                    ),
                    if (ticket.agentActivityLabel.isNotEmpty)
                      _CompactFact(
                        icon: LucideIcons.bot,
                        label: ticket.agentActivityLabel,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TicketNextAction extends StatelessWidget {
  const _TicketNextAction({required this.ticket});

  final WorkshopTicket ticket;

  @override
  Widget build(BuildContext context) {
    final color = _color;
    final label = ticket.agentWorking || ticket.agentStarting || ticket.terminal
        ? ticket.nextActionLabel
        : 'Next: ${ticket.nextActionLabel.toLowerCase()}';
    return Row(
      children: [
        Icon(LucideIcons.arrowRight, size: 15, color: color),
        IiOsGap.hXxs,
        Expanded(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }

  Color get _color {
    if (ticket.terminal) return IiOsColors.muted;
    if (ticket.agentWorking ||
        ticket.agentStarting ||
        ticket.agentReady ||
        ticket.awaitingQa) {
      return IiOsColors.blue;
    }
    if (ticket.retryFailed) return IiOsColors.red;
    if (ticket.requiresAgentResponse ||
        !ticket.structured ||
        ticket.permissionProfile == 'none') {
      return IiOsColors.amber;
    }
    if (ticket.status == 'Todo') return IiOsColors.green;
    return IiOsColors.muted;
  }
}

class WorkshopTicketDetail extends StatelessWidget {
  const WorkshopTicketDetail({
    required this.ticket,
    required this.readiness,
    required this.profile,
    required this.statusOptions,
    required this.canWrite,
    required this.busy,
    required this.onEdit,
    required this.onDelete,
    required this.onReview,
    required this.onPause,
    required this.onStatusChanged,
    required this.onOpenGitHub,
    required this.onManagePermissions,
    this.pullRequest,
    this.pullRequestLoading = false,
    this.pullRequestError,
    this.canMergePullRequest = false,
    this.deploying = false,
    this.onReset,
    this.onOpenPullRequest,
    this.onRefreshPullRequest,
    this.onApproveAndMerge,
    this.onResolvePullRequestConflicts,
    super.key,
  });

  final WorkshopTicket ticket;
  final WorkshopTicketReadiness readiness;
  final AgentPermissionModel? profile;
  final List<JsonMap> statusOptions;
  final bool canWrite;
  final bool busy;
  final bool deploying;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onReset;
  final VoidCallback onReview;
  final VoidCallback onPause;
  final ValueChanged<String> onStatusChanged;
  final VoidCallback onOpenGitHub;
  final VoidCallback onManagePermissions;
  final WorkshopPullRequestModel? pullRequest;
  final bool pullRequestLoading;
  final String? pullRequestError;
  final bool canMergePullRequest;
  final VoidCallback? onOpenPullRequest;
  final VoidCallback? onRefreshPullRequest;
  final VoidCallback? onApproveAndMerge;
  final VoidCallback? onResolvePullRequestConflicts;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${ticket.repository} #${ticket.number}',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      ticket.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.end,
                children: [
                  StatusPill(ticket.displayStatus),
                  if (ticket.agentActivityLabel.isNotEmpty)
                    StatusPill(ticket.agentActivityLabel),
                ],
              ),
            ],
          ),
          IiOsGap.vMd,
          if (ticket.status == 'Done')
            const WorkshopTicketStateSummary(
              icon: LucideIcons.circleCheck,
              title: 'Work complete',
              message:
                  'This ticket is done. No further Workshop action is needed.',
            )
          else if (!ticket.issueOpen)
            const WorkshopTicketStateSummary(
              icon: LucideIcons.circleCheck,
              title: 'Issue closed',
              message:
                  'This GitHub issue is closed. Reopen it before starting '
                  'another pass.',
            )
          else if (deploying)
            const WorkshopTicketStateSummary(
              icon: LucideIcons.clock3,
              title: 'Sending to the runner queue',
              message:
                  'ii-os is locking this exact brief and creating the exact '
                  'workflow run. Its queue state will appear here as soon as '
                  'GitHub accepts it.',
              progress: true,
            )
          else if (ticket.awaitingQa)
            const WorkshopTicketStateSummary(
              icon: LucideIcons.badgeCheck,
              title: 'Ready for your QA',
              message:
                  'Use \u201cHow to verify\u201d below. Choose QA passed if it succeeds, '
                  'or QA failed to send it back for another pass.',
            )
          else if (ticket.agentWorking)
            const WorkshopTicketStateSummary(
              icon: LucideIcons.bot,
              title: 'Agent is working',
              message:
                  'No action is needed while this pass runs. Refresh for the '
                  'next handoff.',
            )
          else if (ticket.agentStarting)
            WorkshopTicketStateSummary(
              icon: LucideIcons.clock3,
              title: ticket.agentActivityLabel,
              message: ticket.agentRunStatus.endsWith('_cleaned')
                  ? 'Cleanup is confirmed. ii-os is finalizing the result.'
                  : ticket.agentRunStatus.endsWith('_cleaning')
                  ? 'The run is finishing and its resources are being cleaned up.'
                  : 'The workflow is bound to this request. The agent shows as '
                        'working once execution starts.',
            )
          else if (ticket.agentReady)
            const WorkshopTicketStateSummary(
              icon: LucideIcons.clock3,
              title: 'Waiting for a runner',
              message:
                  'A human deployed this pass. It will stay in line until an '
                  'eligible runner is available.',
            )
          else
            _ReadinessSummary(readiness: readiness),
          if (ticket.retryFailed) ...[
            IiOsGap.vSm,
            _RetryFailureNotice(ticket: ticket),
          ],
          if (ticket.hasCurrentAgentHandoff) ...[
            IiOsGap.vSm,
            Text(
              '${ticket.agentActivityLabel}. Review the agent evidence, then '
              'choose the human-controlled Workshop status.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 18),
          _DetailSection(
            title: 'Definition of Done',
            value: ticket.definitionOfDone,
          ),
          const SizedBox(height: 14),
          _DetailSection(title: 'How to verify', value: ticket.howToTest),
          if (ticket.context.isNotEmpty) ...[
            const SizedBox(height: 14),
            _DetailSection(title: 'Context', value: ticket.context),
          ],
          const SizedBox(height: 18),
          _PermissionPanel(
            profile: profile,
            ticket: ticket,
            onManage: onManagePermissions,
          ),
          if (ticket.hasPullRequest) ...[
            const SizedBox(height: 18),
            WorkshopPullRequestPanel(
              pullRequest: pullRequest,
              loading: pullRequestLoading,
              error: pullRequestError,
              busy: busy,
              canMerge: canMergePullRequest,
              previousPass:
                  ticket.needsAnotherAgentPass ||
                  !ticket.resultMatchesCurrentTicket,
              onOpen: onOpenPullRequest,
              onRefresh: onRefreshPullRequest,
              onApproveAndMerge: onApproveAndMerge,
              onResolveConflicts: onResolvePullRequestConflicts,
              conflictResolutionUnavailable: _conflictResolutionUnavailable,
            ),
          ],
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: onOpenGitHub,
                icon: const Icon(LucideIcons.externalLink, size: 17),
                label: const Text('Open issue'),
              ),
              if (canWrite)
                OutlinedButton.icon(
                  onPressed: busy ? null : onEdit,
                  icon: const Icon(LucideIcons.pencil, size: 17),
                  label: const Text('Edit brief'),
                ),
              if (canWrite && ticket.canReset && onReset != null)
                OutlinedButton.icon(
                  onPressed: busy ? null : onReset,
                  icon: const Icon(LucideIcons.rotateCcw, size: 17),
                  label: Text(
                    ticket.resetting ? 'Retry reset' : 'Reset ticket',
                  ),
                ),
              if (canWrite)
                Tooltip(
                  excludeFromSemantics: true,
                  message:
                      ticket.agentReady ||
                          ticket.agentStarting ||
                          ticket.agentWorking
                      ? 'Cancel the deployment or wait for the agent to finish first'
                      : 'Remove this ticket from the Workshop',
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: IiOsColors.red,
                      side: BorderSide(
                        color: IiOsColors.red.withValues(alpha: 0.55),
                      ),
                    ),
                    onPressed:
                        busy ||
                            ticket.agentReady ||
                            ticket.agentStarting ||
                            ticket.agentWorking
                        ? null
                        : onDelete,
                    icon: const Icon(LucideIcons.trash2, size: 17),
                    label: const Text('Delete ticket'),
                  ),
                ),
              if (canWrite && !ticket.terminal && !ticket.awaitingQa)
                _agentAction(),
              if (canWrite && !ticket.terminal && ticket.awaitingQa)
                WorkshopQaActions(
                  statusOptions: statusOptions,
                  busy: busy,
                  onStatusChanged: onStatusChanged,
                ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _agentAction() {
    if (ticket.terminal) return StatusPill(ticket.displayStatus);
    if (deploying) {
      return FilledButton.icon(
        onPressed: null,
        icon: const SizedBox.square(
          dimension: 17,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        ),
        label: const Text('Queueing\u2026'),
      );
    }
    if (ticket.agentWorking) return const StatusPill('Agent working');
    if (ticket.agentStarting) return StatusPill(ticket.agentActivityLabel);
    if (ticket.awaitingQa) return const StatusPill('Ready for QA');
    if (ticket.needsAnotherAgentPass) {
      if (!ticket.canDeploy) {
        return const StatusPill('Recovery status updating');
      }
      return FilledButton.tonalIcon(
        onPressed: busy ? null : onReview,
        icon: const Icon(LucideIcons.rotateCcw, size: 17),
        label: Text(ticket.qaFailed ? 'Review & redeploy' : 'Review & retry'),
      );
    }
    if (ticket.agentReady) {
      return OutlinedButton.icon(
        onPressed: busy ? null : onPause,
        icon: const Icon(LucideIcons.pause, size: 17),
        label: const Text('Cancel deployment'),
      );
    }
    final readyForQaOptionId = statusOptions
        .where((option) => option['name'] == 'Ready for QA')
        .map((option) => option['id'])
        .whereType<String>()
        .firstOrNull;
    if (pullRequest?.readyForQa == true &&
        ticket.canHandoffMergedPullRequest &&
        readyForQaOptionId != null) {
      return FilledButton.icon(
        onPressed: busy ? null : () => onStatusChanged(readyForQaOptionId),
        icon: const Icon(LucideIcons.badgeCheck, size: 17),
        label: const Text('Ready for QA'),
      );
    }
    if (pullRequest?.merged == true && ticket.canHandoffMergedPullRequest) {
      return StatusPill(pullRequest!.qaDeploymentLabel);
    }
    if (!ticket.canDeploy) {
      return const Tooltip(
        message:
            'Finish the current workflow step before deploying another pass.',
        child: StatusPill('Next action unavailable'),
      );
    }
    return FilledButton.icon(
      onPressed: busy ? null : onReview,
      icon: const Icon(LucideIcons.clipboardCheck, size: 17),
      label: Text(ticket.requiresAgentResponse ? 'Answer & deploy' : 'Deploy'),
    );
  }

  String? get _conflictResolutionUnavailable {
    if (!canWrite) {
      return 'Your workspace role does not allow agent deployments.';
    }
    if (!readiness.ready) {
      return 'Complete the ticket readiness checks before deploying a conflict-resolution pass.';
    }
    if (!ticket.canDeploy) {
      return 'Finish the current workflow step before deploying a conflict-resolution pass.';
    }
    if (onResolvePullRequestConflicts == null) {
      return 'Refresh the pull request before deploying a conflict-resolution pass.';
    }
    return null;
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 5),
      Text(value.isEmpty ? 'Not provided' : value),
    ],
  );
}

class _PermissionPanel extends StatelessWidget {
  const _PermissionPanel({
    required this.profile,
    required this.ticket,
    required this.onManage,
  });

  final AgentPermissionModel? profile;
  final WorkshopTicket ticket;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: IiOsColors.canvas,
      borderRadius: BorderRadius.circular(IiOsRadii.md),
    ),
    child: Padding(
      padding: const EdgeInsets.all(IiOsSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            profile == null ? LucideIcons.shieldAlert : LucideIcons.shieldCheck,
            color: profile == null ? IiOsColors.amber : IiOsColors.green,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile == null
                      ? 'Agent access needs attention'
                      : 'Installed · ${profile!.displayName}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  profile?.description ??
                      '${ticket.permissionProfile}@${ticket.permissionRef}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          TextButton(onPressed: onManage, child: const Text('Manage')),
        ],
      ),
    ),
  );
}
