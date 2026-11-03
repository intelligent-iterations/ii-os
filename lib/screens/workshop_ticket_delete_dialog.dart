import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/workshop_ticket.dart';
import '../theme/ii_os_theme.dart';
import '../theme/ii_os_tokens.dart';

class WorkshopTicketDeleteDialog extends StatelessWidget {
  const WorkshopTicketDeleteDialog({required this.ticket, super.key});

  final WorkshopTicket ticket;

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(LucideIcons.trash2, color: IiOsColors.red),
    title: Text('Delete ticket #${ticket.number}?'),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '\u201c${ticket.title}\u201d will be removed from this Software Workshop.',
          ),
          IiOsGap.vSm,
          Text(
            ticket.issueOpen
                ? 'The GitHub issue will be closed and kept for history. You can reopen it in GitHub later, but it will need to be added back to the Project.'
                : 'The closed GitHub issue will be kept for history. To restore this ticket, reopen the issue in GitHub and add it back to the Project.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: IiOsColors.muted),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Keep ticket'),
      ),
      FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: IiOsColors.red),
        onPressed: () => Navigator.pop(context, true),
        icon: const Icon(LucideIcons.trash2, size: 17),
        label: const Text('Delete ticket'),
      ),
    ],
  );
}
