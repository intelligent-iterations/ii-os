import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ii_interactive_sessions_flutter/ii_interactive_sessions_flutter.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:stacked/stacked.dart';

import '../repositories/interactive_session_repository.dart';
import '../view_models/interactive_session_detail_view_model.dart';
import '../widgets/common.dart';
import 'interactive_terminal_dialogs.dart';

class InteractiveTerminalSession extends StatefulWidget {
  const InteractiveTerminalSession({
    required this.repository,
    required this.workspaceId,
    required this.sessionId,
    this.onClose,
    super.key,
  });

  final InteractiveSessionRepository repository;
  final String workspaceId;
  final String sessionId;
  final VoidCallback? onClose;

  @override
  State<InteractiveTerminalSession> createState() =>
      _InteractiveTerminalSessionState();
}

class _InteractiveTerminalSessionState
    extends State<InteractiveTerminalSession> {
  final _captureKey = GlobalKey();

  @override
  Widget build(BuildContext context) =>
      ViewModelBuilder<InteractiveSessionDetailViewModel>.reactive(
        viewModelBuilder: () => InteractiveSessionDetailViewModel(
          sessions: widget.repository,
          workspaceId: widget.workspaceId,
          sessionId: widget.sessionId,
          route: () => GoRouterState.of(context).uri.toString(),
        ),
        onViewModelReady: (model) => model.start(),
        builder: (context, model, _) => PageFrame(
          title: 'Terminal session',
          subtitle: widget.sessionId,
          actions: [
            OutlinedButton.icon(
              onPressed: widget.onClose,
              icon: const Icon(LucideIcons.arrowLeft, size: IiOsIconSize.md),
              label: const Text('Sessions'),
            ),
            if (model.canManage)
              OutlinedButton.icon(
                onPressed: model.isBusy ? null : () => _invite(context, model),
                icon: const Icon(LucideIcons.userPlus, size: IiOsIconSize.md),
                label: const Text('Invite'),
              ),
            if (model.canManage &&
                (model.session?.participants.length ?? 0) > 1)
              OutlinedButton.icon(
                onPressed: model.isBusy ? null : () => _revoke(context, model),
                icon: const Icon(LucideIcons.userMinus, size: IiOsIconSize.md),
                label: const Text('Remove access'),
              ),
            if (model.canManage && model.uiAccessEnabled)
              FilledButton.tonalIcon(
                onPressed: model.disableUiAccess,
                icon: const Icon(LucideIcons.eyeOff, size: IiOsIconSize.md),
                label: const Text('Disable UI access'),
              )
            else if (model.canManage)
              FilledButton.tonalIcon(
                onPressed: model.terminal == null || model.isBusy
                    ? null
                    : () => _enableUi(context, model),
                icon: const Icon(LucideIcons.scanSearch, size: IiOsIconSize.md),
                label: const Text('Grant Codex UI access'),
              ),
          ],
          child: _InteractiveTerminalBody(
            model: model,
            captureKey: _captureKey,
            onStop: () => _stop(context, model),
          ),
        ),
      );

  Future<void> _enableUi(
    BuildContext context,
    InteractiveSessionDetailViewModel model,
  ) async {
    final allowAct = await chooseInteractiveUiAccess(context);
    if (allowAct == null || !mounted) return;
    await model.enableUiAccess(
      allowAct: allowAct,
      approveSensitiveAction: (node, action) =>
          approveInteractiveAction(context, node, action),
      captureScreenshot: (revision) => captureApprovedInteractiveSurface(
        context: context,
        boundaryKey: _captureKey,
        revision: revision,
      ),
    );
  }

  Future<void> _invite(
    BuildContext context,
    InteractiveSessionDetailViewModel model,
  ) async {
    final invite = await inviteInteractiveParticipant(context);
    if (invite == null || !context.mounted) return;
    final invited = await model.invite(invite.subject, invite.role);
    if (context.mounted && invited) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${invite.subject} can now join this session.')),
      );
    }
  }

  Future<void> _revoke(
    BuildContext context,
    InteractiveSessionDetailViewModel model,
  ) async {
    final session = model.session;
    if (session == null) return;
    final subject = await chooseInteractiveParticipantToRevoke(
      context,
      session,
    );
    if (subject == null || !context.mounted) return;
    final revoked = await model.revoke(subject);
    if (context.mounted && revoked) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$subject was removed from this session.')),
      );
    }
  }

  Future<void> _stop(
    BuildContext context,
    InteractiveSessionDetailViewModel model,
  ) async {
    if (!await confirmInteractiveSessionStop(context)) return;
    await model.stop();
    if (mounted && model.errorMessage == null) widget.onClose?.call();
  }
}

class _InteractiveTerminalBody extends StatelessWidget {
  const _InteractiveTerminalBody({
    required this.model,
    required this.captureKey,
    required this.onStop,
  });

  final InteractiveSessionDetailViewModel model;
  final GlobalKey captureKey;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    if (model.isBusy && model.terminal == null) {
      return const LoadingSurface(label: 'Connecting to terminal');
    }
    if (model.terminal == null) {
      return ErrorSurface(
        title: 'Terminal could not connect',
        message: model.errorMessage ?? 'The relay did not accept this session.',
        onRetry: model.start,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (model.errorMessage case final error?)
          MaterialBanner(
            content: Text(error),
            actions: [
              TextButton(onPressed: model.start, child: const Text('Retry')),
            ],
          ),
        if (model.uiAccessEnabled) const _UiAccessBanner(),
        Expanded(
          child: RepaintBoundary(
            key: captureKey,
            child: InteractiveTerminalView(
              controller: model.terminal!,
              uiBridge: model.uiBridge,
              onStop: !model.canManage || model.stopping ? null : onStop,
            ),
          ),
        ),
      ],
    );
  }
}

class _UiAccessBanner extends StatelessWidget {
  const _UiAccessBanner();

  @override
  Widget build(BuildContext context) => Material(
    color: IiOsPalette.of(context).info.container,
    child: const Padding(
      padding: EdgeInsets.all(IiOsSpacing.sm),
      child: Row(
        children: [
          Icon(LucideIcons.eye, size: IiOsIconSize.md),
          SizedBox(width: IiOsSpacing.xs),
          Expanded(
            child: Text(
              'Codex UI access is active for this session. Screenshots and sensitive actions require approval.',
            ),
          ),
        ],
      ),
    ),
  );
}
