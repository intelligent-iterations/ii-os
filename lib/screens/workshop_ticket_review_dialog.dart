import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/agent_permission.dart';
import '../models/workshop_pull_request.dart';
import '../models/workshop_ticket.dart';
import '../theme/ii_os_theme.dart';
import '../theme/ii_os_tokens.dart';
import '../widgets/common.dart';
import 'workshop_ticket_model_picker.dart';

final class WorkshopTicketReviewResult {
  const WorkshopTicketReviewResult({
    required this.response,
    required this.permissionProfile,
    required this.permissionRef,
    required this.deploy,
  });

  final String response;
  final String permissionProfile;
  final String permissionRef;
  final bool deploy;
}

class WorkshopTicketReviewDialog extends StatefulWidget {
  const WorkshopTicketReviewDialog({
    required this.ticket,
    required this.readiness,
    required this.profile,
    required this.permissionProfiles,
    this.conflictedPullRequest,
    this.initialResponse = '',
    super.key,
  });

  final WorkshopTicket ticket;
  final WorkshopTicketReadiness readiness;
  final AgentPermissionModel? profile;
  final List<AgentPermissionModel> permissionProfiles;
  final WorkshopPullRequestModel? conflictedPullRequest;
  final String initialResponse;

  @override
  State<WorkshopTicketReviewDialog> createState() =>
      _WorkshopTicketReviewDialogState();
}

class _WorkshopTicketReviewDialogState
    extends State<WorkshopTicketReviewDialog> {
  late final TextEditingController _response;
  late String _permissionProfile;
  String? _responseError;

  bool get _resolvingConflicts => widget.conflictedPullRequest != null;
  bool get _showsResponse =>
      widget.ticket.requiresAgentResponse || _resolvingConflicts;
  bool get _profileChanged =>
      _permissionProfile != widget.ticket.permissionProfile;
  AgentPermissionModel? get _selectedProfile => widget.permissionProfiles
      .where((profile) => profile.id == _permissionProfile)
      .firstOrNull;

  @override
  void initState() {
    super.initState();
    _permissionProfile = widget.ticket.permissionProfile;
    _response = TextEditingController(
      text: widget.initialResponse.isNotEmpty
          ? widget.initialResponse
          : widget.conflictedPullRequest?.conflictResolutionRequest() ?? '',
    );
  }

  @override
  void dispose() {
    _response.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ticket = widget.ticket;
    final ready = widget.readiness.ready && !_profileChanged;
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: EdgeInsets.all(size.width < 620 ? 12 : 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 720,
          maxHeight: size.height * 0.9,
        ),
        child: Padding(
          padding: const EdgeInsets.all(IiOsSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ReviewDialogHeader(
                ticket: ticket,
                ready: ready,
                profileChanged: _profileChanged,
                resolvingConflicts: _resolvingConflicts,
              ),
              const SizedBox(height: 18),
              _ReviewDialogContent(
                ticket: ticket,
                readiness: widget.readiness,
                profile: _selectedProfile ?? widget.profile,
                permissionProfiles: widget.permissionProfiles,
                permissionProfile: _permissionProfile,
                profileChanged: _profileChanged,
                onProfileChanged: (value) => setState(() {
                  _permissionProfile = value;
                  _responseError = null;
                }),
                response: _response,
                responseError: _responseError,
                showsResponse: _showsResponse,
                resolvingConflicts: _resolvingConflicts,
              ),
              IiOsGap.vMd,
              _ReviewDialogActions(
                ready: ready,
                profileChanged: _profileChanged,
                resolvingConflicts: _resolvingConflicts,
                requiresAgentResponse: ticket.requiresAgentResponse,
                qaFailed: ticket.qaFailed,
                onDeploy: _deploy,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _deploy() {
    final response = _response.text.trim();
    if (!_profileChanged && _showsResponse && response.isEmpty) {
      setState(
        () => _responseError = _resolvingConflicts
            ? 'Add conflict-resolution instructions before deploying.'
            : 'Add an answer before deploying another pass.',
      );
      return;
    }
    final profile = _selectedProfile ?? widget.profile;
    Navigator.pop(
      context,
      WorkshopTicketReviewResult(
        response: response,
        permissionProfile: profile?.id ?? widget.ticket.permissionProfile,
        permissionRef: profile?.workflowRef ?? widget.ticket.permissionRef,
        deploy: !_profileChanged,
      ),
    );
  }
}

class _ReviewDialogContent extends StatelessWidget {
  const _ReviewDialogContent({
    required this.ticket,
    required this.readiness,
    required this.profile,
    required this.permissionProfiles,
    required this.permissionProfile,
    required this.profileChanged,
    required this.onProfileChanged,
    required this.response,
    required this.responseError,
    required this.showsResponse,
    required this.resolvingConflicts,
  });

  final WorkshopTicket ticket;
  final WorkshopTicketReadiness readiness;
  final AgentPermissionModel? profile;
  final List<AgentPermissionModel> permissionProfiles;
  final String permissionProfile;
  final bool profileChanged;
  final ValueChanged<String> onProfileChanged;
  final TextEditingController response;
  final String? responseError;
  final bool showsResponse;
  final bool resolvingConflicts;

  @override
  Widget build(BuildContext context) => Expanded(
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(ticket.title, style: Theme.of(context).textTheme.titleMedium),
          IiOsGap.vMd,
          if (permissionProfiles.isNotEmpty) ...[
            WorkshopTicketModelPicker(
              profiles: permissionProfiles,
              selectedProfile: permissionProfile,
              changed: profileChanged,
              onChanged: onProfileChanged,
            ),
            IiOsGap.vMd,
          ],
          if (!profileChanged)
            for (final check in readiness.checks) _ReviewCheck(check),
          if (profile case final value?) ...[
            const SizedBox(height: 10),
            WorkshopTicketPermissionSummary(profile: value),
          ],
          if (showsResponse) ...[
            IiOsGap.vMd,
            TextField(
              controller: response,
              minLines: 4,
              maxLines: 8,
              maxLength: 8000,
              decoration: InputDecoration(
                labelText: resolvingConflicts
                    ? 'Conflict-resolution instructions'
                    : 'Answer the agent',
                helperText: resolvingConflicts
                    ? 'Review or edit the exact instructions before deploying the agent.'
                    : 'This answer will be included when you deploy the next pass.',
                errorText: responseError,
                alignLabelWithHint: true,
              ),
            ),
          ],
          const SizedBox(height: 14),
          DecoratedBox(
            decoration: BoxDecoration(
              color: IiOsColors.blueTint,
              borderRadius: BorderRadius.circular(IiOsRadii.md),
              border: Border.all(color: IiOsColors.blue),
            ),
            child: const Padding(
              padding: EdgeInsets.all(IiOsSpacing.sm),
              child: Text(
                'When you deploy this pass, ii-os locks this exact brief and answer for the agent. The deployment waits for an eligible runner, you remain in control of Workshop status, and the agent cannot mark the ticket Done.',
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ReviewDialogHeader extends StatelessWidget {
  const _ReviewDialogHeader({
    required this.ticket,
    required this.ready,
    required this.profileChanged,
    required this.resolvingConflicts,
  });

  final WorkshopTicket ticket;
  final bool ready;
  final bool profileChanged;
  final bool resolvingConflicts;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(LucideIcons.clipboardCheck, size: 24),
      IiOsGap.hSm,
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              resolvingConflicts
                  ? 'Review conflict-resolution pass'
                  : ticket.requiresAgentResponse
                  ? 'Answer and deploy another pass'
                  : ticket.qaFailed
                  ? 'Review and redeploy the next pass'
                  : 'Review deployment',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 3),
            Text(
              '${ticket.repository} #${ticket.number}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      StatusPill(
        profileChanged
            ? 'Recheck needed'
            : ready
            ? 'Ready'
            : 'Blocked',
        color: ready ? IiOsColors.green : IiOsColors.amber,
      ),
    ],
  );
}

class _ReviewDialogActions extends StatelessWidget {
  const _ReviewDialogActions({
    required this.ready,
    required this.profileChanged,
    required this.resolvingConflicts,
    required this.requiresAgentResponse,
    required this.qaFailed,
    required this.onDeploy,
  });

  final bool ready;
  final bool profileChanged;
  final bool resolvingConflicts;
  final bool requiresAgentResponse;
  final bool qaFailed;
  final VoidCallback onDeploy;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    alignment: WrapAlignment.end,
    children: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton.icon(
        onPressed: ready || profileChanged ? onDeploy : null,
        icon: const Icon(LucideIcons.play, size: 17),
        label: Text(
          profileChanged
              ? 'Save model and recheck'
              : resolvingConflicts
              ? 'Deploy conflict-resolution pass'
              : requiresAgentResponse
              ? 'Answer and deploy next pass'
              : qaFailed
              ? 'Deploy next pass'
              : 'Deploy',
        ),
      ),
    ],
  );
}

class _ReviewCheck extends StatelessWidget {
  const _ReviewCheck(this.check);

  final WorkshopReadinessCheck check;

  @override
  Widget build(BuildContext context) {
    final color = check.passed ? IiOsColors.green : IiOsColors.amber;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            check.passed ? LucideIcons.circleCheck : LucideIcons.circleAlert,
            color: color,
            size: 19,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  check.label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  check.detail,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
