import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/workshop_ticket.dart';
import '../view_models/workshop_deployment_view_model.dart';
import '../widgets/common.dart';
import 'workshop_ticket_reset_dialog.dart';

Future<void> openWorkshopUrl(String value) async {
  final uri = Uri.tryParse(value);
  if (uri != null) await launchUrl(uri);
}

Future<void> resetWorkshopTicket({
  required BuildContext context,
  required WorkshopTicket ticket,
  required String workspaceId,
  required String projectId,
  required WorkshopDeploymentViewModel deployment,
  required Future<void> Function() reload,
}) async {
  if (!ticket.canReset) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => WorkshopTicketResetDialog(ticket: ticket),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await deployment.reset(
      workspaceId: workspaceId,
      projectId: projectId,
      ticket: ticket,
    );
    await reload();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Ticket #${ticket.number} is back in Draft with newly filed metadata. Its GitHub issue and history were preserved.',
        ),
      ),
    );
  } on Object catch (error) {
    if (context.mounted) showFailure(context, error);
  } finally {
    deployment.confirmReset(ticket.itemId);
  }
}
