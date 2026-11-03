import 'package:flutter/material.dart';
import 'package:ii_interactive_sessions/ii_interactive_sessions.dart';
import 'package:ii_interactive_sessions_flutter/ii_interactive_sessions_flutter.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';

import '../models/models.dart';

Future<({String subject, ParticipantRole role})?> inviteInteractiveParticipant(
  BuildContext context,
) async {
  final controller = TextEditingController();
  var role = ParticipantRole.collaborator;
  final result = await showDialog<({String subject, ParticipantRole role})>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Invite a workspace member'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Enter the exact ii-os member ID. They can open this session from the same workspace after you invite them.',
            ),
            const SizedBox(height: IiOsSpacing.md),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Workspace member ID',
              ),
            ),
            DropdownButtonFormField<ParticipantRole>(
              initialValue: role,
              decoration: const InputDecoration(
                labelText: 'Access',
                helperText:
                    'Collaborators can request input; viewers observe only.',
              ),
              items: const [
                DropdownMenuItem(
                  value: ParticipantRole.collaborator,
                  child: Text('Collaborator'),
                ),
                DropdownMenuItem(
                  value: ParticipantRole.viewer,
                  child: Text('Viewer'),
                ),
              ],
              onChanged: (value) =>
                  setState(() => role = value ?? ParticipantRole.collaborator),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final subject = controller.text.trim();
              if (subject.isNotEmpty && !subject.contains('/')) {
                Navigator.of(context).pop((subject: subject, role: role));
              }
            },
            child: const Text('Invite'),
          ),
        ],
      ),
    ),
  );
  controller.dispose();
  return result;
}

Future<String?> chooseInteractiveParticipantToRevoke(
  BuildContext context,
  InteractiveSessionModel session,
) {
  final participants = session.participants
      .where(
        (item) =>
            item.subject != session.ownerSubject &&
            item.subject != 'agent:codex',
      )
      .toList();
  return showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Remove session access'),
      children: participants.isEmpty
          ? const [
              Padding(
                padding: EdgeInsets.all(IiOsSpacing.lg),
                child: Text('No invited people can be removed.'),
              ),
            ]
          : [
              for (final participant in participants)
                SimpleDialogOption(
                  onPressed: () =>
                      Navigator.of(context).pop(participant.subject),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(participant.subject),
                    subtitle: Text(participant.role),
                    trailing: const Icon(Icons.person_remove_outlined),
                  ),
                ),
            ],
    ),
  );
}

Future<bool?> chooseInteractiveUiAccess(
  BuildContext context,
) => showDialog<bool>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Grant Codex access to this screen?'),
    content: const Text(
      'Observe shares structured visible controls. Control also lets Codex activate enabled controls. Sensitive actions and every screenshot still require your approval.',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      OutlinedButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: const Text('Observe only'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(true),
        child: const Text('Allow control'),
      ),
    ],
  ),
);

Future<bool> approveInteractiveAction(
  BuildContext context,
  UiSemanticNode node,
  UiActionRequest action,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Allow sensitive UI action?'),
        content: Text('${action.kind.wireName} \u201c${node.label}\u201d'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Deny'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Allow once'),
          ),
        ],
      ),
    ) ??
    false;

Future<UiScreenshot> captureApprovedInteractiveSurface({
  required BuildContext context,
  required GlobalKey boundaryKey,
  required int revision,
}) async {
  final approved = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Share this screenshot with Codex?'),
      content: const Text(
        'The current terminal surface may contain sensitive text. Review it before allowing this one capture.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Deny'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Share once'),
        ),
      ],
    ),
  );
  if (approved != true) throw StateError('Screenshot approval denied.');
  return captureInteractiveSurface(
    boundaryKey: boundaryKey,
    revision: revision,
    redacted: false,
  );
}

Future<bool> confirmInteractiveSessionStop(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop this terminal session?'),
        content: const Text(
          'The shell and installed packages are temporary. Fleet will destroy the leased runtime.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep running'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Stop session'),
          ),
        ],
      ),
    ) ??
    false;
