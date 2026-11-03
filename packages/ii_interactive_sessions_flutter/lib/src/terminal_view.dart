import 'package:flutter/material.dart';
import 'package:ii_interactive_sessions/ii_interactive_sessions.dart';
import 'package:xterm/xterm.dart';

import 'terminal_controller.dart';
import 'ui_bridge_controller.dart';
import 'ui_semantic_element.dart';

final class InteractiveTerminalView extends StatelessWidget {
  const InteractiveTerminalView({
    required this.controller,
    this.onStop,
    this.uiBridge,
    super.key,
  });

  final InteractiveTerminalController controller;
  final VoidCallback? onStop;
  final InteractiveUiBridgeController? uiBridge;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Column(
      children: [
        _SessionToolbar(
          controller: controller,
          onStop: onStop,
          uiBridge: uiBridge,
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  label: 'Interactive terminal output',
                  textField: true,
                  readOnly: !controller.canWrite,
                  child: TerminalView(
                    controller.terminal,
                    autofocus: true,
                    readOnly: !controller.canWrite,
                    padding: const EdgeInsets.all(12),
                  ),
                ),
              ),
              SizedBox(
                width: 220,
                child: _PresencePanel(controller: controller),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

final class _SessionToolbar extends StatelessWidget {
  const _SessionToolbar({required this.controller, this.onStop, this.uiBridge});

  final InteractiveTerminalController controller;
  final VoidCallback? onStop;
  final InteractiveUiBridgeController? uiBridge;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainer,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(
            controller.connectionState == SessionConnectionState.connected
                ? Icons.cloud_done_outlined
                : Icons.cloud_off_outlined,
          ),
          const SizedBox(width: 8),
          Text(controller.connectionState.name),
          const Spacer(),
          if (!controller.canWrite)
            _BridgeButton(
              bridge: uiBridge,
              id: controller.canManageSession
                  ? 'terminal.take-input'
                  : 'terminal.request-input',
              label: controller.canManageSession
                  ? 'Take terminal input'
                  : 'Request terminal input',
              sensitive: controller.canManageSession,
              onPressed: controller.canManageSession
                  ? () => controller.grantInput(controller.subject)
                  : controller.requestInput,
              child: OutlinedButton.icon(
                onPressed: controller.canManageSession
                    ? () => controller.grantInput(controller.subject)
                    : controller.requestInput,
                icon: const Icon(Icons.keyboard),
                label: Text(
                  controller.canManageSession ? 'Take input' : 'Request input',
                ),
              ),
            ),
          if (onStop != null) ...[
            const SizedBox(width: 8),
            _BridgeButton(
              bridge: uiBridge,
              id: 'session.stop',
              label: 'Stop terminal session',
              sensitive: true,
              onPressed: () async => onStop?.call(),
              child: FilledButton.tonalIcon(
                onPressed: onStop,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Stop'),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

final class _BridgeButton extends StatelessWidget {
  const _BridgeButton({
    required this.bridge,
    required this.id,
    required this.label,
    required this.onPressed,
    required this.child,
    this.sensitive = false,
  });

  final InteractiveUiBridgeController? bridge;
  final String id;
  final String label;
  final Future<void> Function() onPressed;
  final Widget child;
  final bool sensitive;

  @override
  Widget build(BuildContext context) {
    final value = bridge;
    if (value == null) return child;
    return InteractiveSemanticElement(
      bridge: value,
      id: id,
      role: 'button',
      label: label,
      sensitive: sensitive,
      onAction: (request) async {
        if (request.kind == UiActionKind.activate) await onPressed();
      },
      child: child,
    );
  }
}

final class _PresencePanel extends StatelessWidget {
  const _PresencePanel({required this.controller});

  final InteractiveTerminalController controller;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLowest,
    child: ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('Participants', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        for (final participant in controller.participants)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              participant.subject == controller.inputHolder
                  ? Icons.keyboard
                  : Icons.visibility_outlined,
              size: 18,
            ),
            title: Text(participant.subject),
            subtitle: Text(participant.role),
            trailing:
                controller.canManageSession &&
                    participant.subject != controller.subject &&
                    participant.role == ParticipantRole.collaborator.name
                ? IconButton(
                    tooltip: participant.subject == controller.inputRequester
                        ? 'Grant requested input'
                        : 'Give terminal input',
                    onPressed: () => controller.grantInput(participant.subject),
                    icon: Icon(
                      participant.subject == controller.inputRequester
                          ? Icons.keyboard_tab
                          : Icons.swap_horiz,
                    ),
                  )
                : null,
          ),
      ],
    ),
  );
}
