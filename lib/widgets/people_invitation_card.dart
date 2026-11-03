import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/models.dart';

class PeopleInvitationCard extends StatelessWidget {
  const PeopleInvitationCard({
    required this.invitation,
    required this.workspaceNames,
    required this.onRevoke,
    required this.revoking,
    super.key,
  });

  final OrganizationInvitationModel invitation;
  final List<String> workspaceNames;
  final VoidCallback? onRevoke;
  final bool revoking;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(IiOsSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: IiOsSpacing.sm,
            runSpacing: IiOsSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                invitation.email,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              _DeliveryStatus(status: invitation.deliveryStatus),
              IiOsMetaChip(label: invitation.roleLabel),
            ],
          ),
          IiOsGap.vSm,
          Text(
            workspaceNames.isEmpty
                ? 'No workspace access selected'
                : 'Workspace access',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (workspaceNames.isNotEmpty) ...[
            IiOsGap.vXs,
            Wrap(
              spacing: IiOsSpacing.xs,
              runSpacing: IiOsSpacing.xs,
              children: [
                for (final name in workspaceNames)
                  IiOsMetaChip(label: name, icon: LucideIcons.panelTop),
              ],
            ),
          ],
          IiOsGap.vSm,
          Row(
            children: [
              Expanded(child: Text(_expiryLabel(invitation.expiresAt))),
              if (onRevoke != null)
                TextButton.icon(
                  onPressed: revoking ? null : onRevoke,
                  icon: revoking
                      ? const SizedBox.square(
                          dimension: IiOsIconSize.md,
                          child: CircularProgressIndicator(
                            strokeWidth: IiOsSpacing.xxs / 2,
                          ),
                        )
                      : const Icon(LucideIcons.x, size: IiOsIconSize.md),
                  label: const Text('Revoke'),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _DeliveryStatus extends StatelessWidget {
  const _DeliveryStatus({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    final (label, icon, hue) = switch (status) {
      'delivered' => ('Email sent', LucideIcons.mailCheck, palette.brand),
      'failed' => ('Email not sent', LucideIcons.mailWarning, palette.danger),
      _ => ('Sending email', LucideIcons.mail, palette.info),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: hue.container,
        borderRadius: IiOsRadii.pillAll,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: IiOsSpacing.xs,
          vertical: IiOsSpacing.xxs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: IiOsIconSize.xs, color: hue.text),
            IiOsGap.hXxs,
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: hue.text),
            ),
          ],
        ),
      ),
    );
  }
}

String _expiryLabel(DateTime? expiresAt) {
  if (expiresAt == null) return 'Expires in 7 days';
  final local = expiresAt.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  return 'Expires ${local.year}-$month-$day';
}
