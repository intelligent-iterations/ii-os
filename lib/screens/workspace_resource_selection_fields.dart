part of 'workspace_resource_selection_screen.dart';

class _RunnerCapacityFields extends StatelessWidget {
  const _RunnerCapacityFields({required this.model, required this.envelope});

  final WorkspaceResourcesViewModel model;
  final OrganizationRunnerPoolModel envelope;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: _CapacityField(
          key: ValueKey('${envelope.id}:cpu'),
          label: 'CPU (max ${envelope.maxCpu})',
          initialValue: model.runnerMaxCpu,
          enabled: model.canManage && !model.isBusy,
          onChanged: model.setRunnerMaxCpu,
        ),
      ),
      IiOsGap.hSm,
      Expanded(
        child: _CapacityField(
          key: ValueKey('${envelope.id}:ram'),
          label: 'RAM MiB (max ${envelope.maxRamMiB})',
          initialValue: model.runnerMaxRamMiB,
          enabled: model.canManage && !model.isBusy,
          onChanged: model.setRunnerMaxRamMiB,
        ),
      ),
      IiOsGap.hSm,
      Expanded(
        child: _CapacityField(
          key: ValueKey('${envelope.id}:concurrent'),
          label: 'Concurrent (max ${envelope.maxConcurrent})',
          initialValue: model.runnerMaxConcurrent,
          enabled: model.canManage && !model.isBusy,
          onChanged: model.setRunnerMaxConcurrent,
        ),
      ),
    ],
  );
}

class _CapacityField extends StatelessWidget {
  const _CapacityField({
    required this.label,
    required this.initialValue,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final String label;
  final int initialValue;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => TextFormField(
    initialValue: '$initialValue',
    enabled: enabled,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(labelText: label),
    onChanged: onChanged,
  );
}

class _OptionalResourceDropdown extends StatelessWidget {
  const _OptionalResourceDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.enabled,
    required this.onChanged,
    required this.assignments,
    required this.details,
  });

  final String label;
  final String? value;
  final List<({String id, String name})> items;
  final bool enabled;
  final ValueChanged<String?> onChanged;
  final Widget assignments;
  final Widget? details;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (items.isNotEmpty) ...[
        _AvailableResources(names: items.map((item) => item.name)),
        IiOsGap.vXs,
      ],
      DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: [
          const DropdownMenuItem(value: '', child: Text('Not assigned')),
          for (final item in items)
            DropdownMenuItem(value: item.id, child: Text(item.name)),
        ],
        onChanged: enabled
            ? (value) => onChanged(value?.isEmpty == true ? null : value)
            : null,
      ),
      IiOsGap.vSm,
      assignments,
      if (details != null) ...[IiOsGap.vSm, details!],
    ],
  );
}

class _AssignedResourceChips extends StatelessWidget {
  const _AssignedResourceChips({
    required this.label,
    required this.resources,
    required this.assignedIds,
    required this.primaryId,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final List<({String id, String name})> resources;
  final Set<String> assignedIds;
  final String? primaryId;
  final bool enabled;
  final void Function(String resourceId, bool assigned) onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelLarge),
      IiOsGap.vXxs,
      Wrap(
        spacing: IiOsSpacing.xs,
        runSpacing: IiOsSpacing.xs,
        children: [
          for (final resource in resources)
            FilterChip(
              label: Text(
                resource.id == primaryId
                    ? '${resource.name} · primary'
                    : resource.name,
              ),
              selected: assignedIds.contains(resource.id),
              onSelected: enabled && resource.id != primaryId
                  ? (selected) => onChanged(resource.id, selected)
                  : null,
            ),
        ],
      ),
      IiOsGap.vXxs,
      Text(
        'Assign several when needed. Current operations use the primary; '
        'choose another as primary to edit its narrower limits.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}

class _AvailableResources extends StatelessWidget {
  const _AvailableResources({required this.names});

  final Iterable<String> names;

  @override
  Widget build(BuildContext context) => Text(
    'Available: ${names.join(', ')}',
    style: Theme.of(context).textTheme.bodySmall,
  );
}

class _ResourceCard extends StatelessWidget {
  const _ResourceCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(IiOsSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: IiOsIconSize.md),
              IiOsGap.hXs,
              Expanded(child: SectionTitle(title)),
            ],
          ),
          IiOsGap.vSm,
          child,
        ],
      ),
    ),
  );
}

class _PermissionChips extends StatelessWidget {
  const _PermissionChips({
    required this.permissions,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final Set<String> permissions;
  final Set<String> selected;
  final bool enabled;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) => _ChoiceChips(
    choices: permissions,
    selected: selected,
    enabled: enabled,
    onChanged: onChanged,
  );
}

class _ChoiceChips extends StatelessWidget {
  const _ChoiceChips({
    required this.choices,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final Set<String> choices;
  final Set<String> selected;
  final bool enabled;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: IiOsSpacing.xs,
    runSpacing: IiOsSpacing.xs,
    children: [
      for (final choice in choices.toList()..sort())
        FilterChip(
          label: Text(choice),
          selected: selected.contains(choice),
          onSelected: enabled
              ? (selected) => onChanged({
                  ...this.selected.where((item) => item != choice),
                  if (selected) choice,
                })
              : null,
        ),
    ],
  );
}

class _EmptyResource extends StatelessWidget {
  const _EmptyResource(this.message);

  final String message;

  @override
  Widget build(BuildContext context) =>
      Text(message, style: Theme.of(context).textTheme.bodySmall);
}
