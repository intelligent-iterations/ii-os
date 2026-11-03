import 'package:flutter/material.dart';

import '../models/agent_permission.dart';
import '../theme/ii_os_theme.dart';
import '../theme/ii_os_tokens.dart';

class WorkshopTicketModelPicker extends StatelessWidget {
  const WorkshopTicketModelPicker({
    required this.profiles,
    required this.selectedProfile,
    required this.changed,
    required this.onChanged,
    super.key,
  });

  final List<AgentPermissionModel> profiles;
  final String selectedProfile;
  final bool changed;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    initialValue: selectedProfile,
    isExpanded: true,
    decoration: InputDecoration(
      labelText: 'Model for this pass',
      helperText: changed
          ? 'Save this choice so ii-os can check the selected model before deployment.'
          : 'Choose from the models installed and reviewed in this repository.',
    ),
    items: [
      for (final profile in profiles)
        DropdownMenuItem(
          value: profile.id,
          child: Text(profile.selectionLabel, overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: (value) {
      if (value != null) onChanged(value);
    },
  );
}

class WorkshopTicketPermissionSummary extends StatelessWidget {
  const WorkshopTicketPermissionSummary({required this.profile, super.key});

  final AgentPermissionModel profile;

  @override
  Widget build(BuildContext context) => Card(
    color: IiOsColors.canvas,
    child: Padding(
      padding: const EdgeInsets.all(IiOsSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Agent access · ${profile.displayName}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          IiOsGap.vXs,
          Text(profile.description),
          IiOsGap.vSm,
          Text(
            '${profile.allowedActions.length} allowed · ${profile.deniedActions.length} denied · ${profile.environment}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
        ],
      ),
    ),
  );
}
