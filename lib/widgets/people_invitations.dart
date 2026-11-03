import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';

import '../models/models.dart';
import 'common.dart';
import 'people_invitation_card.dart';

class PeopleInvitations extends StatelessWidget {
  const PeopleInvitations({
    required this.directory,
    required this.onRevoke,
    required this.isRevoking,
    super.key,
  });

  final OrganizationPeopleModel directory;
  final ValueChanged<OrganizationInvitationModel>? onRevoke;
  final bool Function(String invitationId) isRevoking;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          'Pending invitations',
          trailing: Text('${directory.invitations.length}'),
        ),
        IiOsGap.vSm,
        if (directory.invitations.isEmpty)
          const _NoInvitations()
        else
          for (final invitation in directory.invitations) ...[
            PeopleInvitationCard(
              invitation: invitation,
              workspaceNames: invitation.workspaceIds
                  .map(directory.workspace)
                  .whereType<OrganizationWorkspaceModel>()
                  .map((item) => item.name)
                  .toList(growable: false),
              onRevoke: onRevoke == null ? null : () => onRevoke!(invitation),
              revoking: isRevoking(invitation.id),
            ),
            IiOsGap.vSm,
          ],
      ],
    );
  }
}

class _NoInvitations extends StatelessWidget {
  const _NoInvitations();

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.neutralTint,
        borderRadius: IiOsRadii.mdAll,
        border: Border.all(color: palette.border),
      ),
      child: const Padding(
        padding: EdgeInsets.all(IiOsSpacing.md),
        child: Text('No one is waiting to join.'),
      ),
    );
  }
}
