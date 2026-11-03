import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/models.dart';

class PeopleCard extends StatelessWidget {
  const PeopleCard({required this.person, required this.onManage, super.key});

  final OrganizationPersonModel person;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    final initial = person.email.trim().isEmpty
        ? '?'
        : person.email.trim().substring(0, 1).toUpperCase();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(IiOsSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Semantics(
                  label: 'Account ${person.email}',
                  child: ExcludeSemantics(
                    child: CircleAvatar(
                      backgroundColor: palette.brand.container,
                      foregroundColor: palette.brand.text,
                      child: Text(initial),
                    ),
                  ),
                ),
                IiOsGap.hSm,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        person.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      IiOsGap.vXxs,
                      Text(
                        person.roleLabel,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: palette.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            IiOsGap.vMd,
            OutlinedButton.icon(
              onPressed: onManage,
              icon: const Icon(
                LucideIcons.panelsTopLeft,
                size: IiOsIconSize.md,
              ),
              label: const Text('Manage workspaces'),
            ),
          ],
        ),
      ),
    );
  }
}
