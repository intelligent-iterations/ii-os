import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/workshop_ticket.dart';

class WorkshopTicketResetDialog extends StatelessWidget {
  const WorkshopTicketResetDialog({required this.ticket, super.key});

  final WorkshopTicket ticket;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Reset ticket #${ticket.number}?'),
    content: const Text(
      'This clears the Workshop status and supersedes the visible agent '
      'handoff so the ticket returns to Draft, ready for a new Deploy.\n\n'
      'The GitHub issue, brief, comments, and execution history remain. Labels '
      'are cleared to match a newly filed Workshop ticket.',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      FilledButton.tonalIcon(
        onPressed: () => Navigator.pop(context, true),
        icon: const Icon(LucideIcons.rotateCcw, size: 17),
        label: Text(ticket.resetting ? 'Retry reset' : 'Reset ticket'),
      ),
    ],
  );
}
