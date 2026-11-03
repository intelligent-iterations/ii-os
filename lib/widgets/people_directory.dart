import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/models.dart';
import 'common.dart';
import 'people_card.dart';
import 'people_invitations.dart';

class PeopleDirectory extends StatelessWidget {
  const PeopleDirectory({
    required this.directory,
    required this.people,
    required this.onManageAccess,
    required this.onRevokeInvitation,
    required this.isRevoking,
    super.key,
  });

  final OrganizationPeopleModel directory;
  final List<OrganizationPersonModel> people;
  final ValueChanged<OrganizationPersonModel> onManageAccess;
  final ValueChanged<OrganizationInvitationModel>? onRevokeInvitation;
  final bool Function(String invitationId) isRevoking;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DirectorySummary(directory: directory),
        IiOsGap.vXl,
        SectionTitle('People', trailing: Text('${people.length} shown')),
        IiOsGap.vSm,
        if (people.isEmpty)
          const EmptyState(
            icon: LucideIcons.searchX,
            title: 'No people match this search',
            message: 'Try another email address or clear the search.',
          )
        else
          _PeopleGrid(people: people, onManageAccess: onManageAccess),
        IiOsGap.vXxl,
        PeopleInvitations(
          directory: directory,
          onRevoke: onRevokeInvitation,
          isRevoking: isRevoking,
        ),
      ],
    );
  }
}

class _DirectorySummary extends StatelessWidget {
  const _DirectorySummary({required this.directory});

  final OrganizationPeopleModel directory;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: IiOsSpacing.xs,
      runSpacing: IiOsSpacing.xs,
      children: [
        IiOsMetaChip(
          icon: LucideIcons.users,
          label: '${directory.people.length} people',
        ),
        IiOsMetaChip(
          icon: LucideIcons.panelsTopLeft,
          label: '${directory.workspaces.length} workspaces',
        ),
        IiOsMetaChip(
          icon: LucideIcons.mail,
          label: '${directory.invitations.length} pending',
        ),
      ],
    );
  }
}

class _PeopleGrid extends StatelessWidget {
  const _PeopleGrid({required this.people, required this.onManageAccess});

  final List<OrganizationPersonModel> people;
  final ValueChanged<OrganizationPersonModel> onManageAccess;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= IiOsBreakpoints.medium;
        final width = twoColumns
            ? (constraints.maxWidth - IiOsSpacing.md) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: IiOsSpacing.md,
          runSpacing: IiOsSpacing.md,
          children: [
            for (final person in people)
              SizedBox(
                width: width,
                child: PeopleCard(
                  person: person,
                  onManage: () => onManageAccess(person),
                ),
              ),
          ],
        );
      },
    );
  }
}
