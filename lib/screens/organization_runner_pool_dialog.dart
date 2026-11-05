part of 'organization_resources_dialogs.dart';

/// Describes runners the organization already runs. With [existing] it edits
/// that pool, including whether workspaces may use it.
class _RunnerPoolDialog extends StatefulWidget {
  const _RunnerPoolDialog({this.existing});

  final OrganizationRunnerPoolModel? existing;

  @override
  State<_RunnerPoolDialog> createState() => _RunnerPoolDialogState();
}

class _RunnerPoolDialogState extends State<_RunnerPoolDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _group = TextEditingController(
    text: widget.existing?.providerPoolId,
  );
  late final _capabilities = TextEditingController(
    text: (widget.existing?.capabilities.toList()?..sort())?.join(', '),
  );
  late final _cpu = TextEditingController(
    text: _number(widget.existing?.maxCpu),
  );
  late final _ram = TextEditingController(
    text: _number(widget.existing?.maxRamMiB),
  );
  late final _concurrent = TextEditingController(
    text: _number(widget.existing?.maxConcurrent),
  );
  late bool _active = widget.existing?.active ?? true;

  @override
  void dispose() {
    _name.dispose();
    _group.dispose();
    _capabilities.dispose();
    _cpu.dispose();
    _ram.dispose();
    _concurrent.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return AlertDialog(
      title: Text(editing ? 'Edit your runners' : 'Add your runners'),
      content: SizedBox(
        width: IiOsWidths.wideForm,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: _RunnerPoolFields(
              name: _name,
              group: _group,
              capabilities: _capabilities,
              cpu: _cpu,
              ram: _ram,
              concurrent: _concurrent,
              active: editing ? _active : null,
              onActiveChanged: (value) => setState(() => _active = value),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(editing ? 'Save changes' : 'Add runners'),
        ),
      ],
    );
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      CustomerRunnerPoolInput(
        name: _name.text.trim(),
        runnerGroup: _group.text.trim(),
        capabilities: parseRunnerCapabilities(_capabilities.text),
        maxCpu: int.parse(_cpu.text.trim()),
        maxRamMiB: int.parse(_ram.text.trim()),
        maxConcurrent: int.parse(_concurrent.text.trim()),
        active: _active,
      ),
    );
  }
}

String? _number(int? value) => value == null ? null : '$value';

class _RunnerPoolFields extends StatelessWidget {
  const _RunnerPoolFields({
    required this.name,
    required this.group,
    required this.capabilities,
    required this.cpu,
    required this.ram,
    required this.concurrent,
    required this.active,
    required this.onActiveChanged,
  });

  final TextEditingController name;
  final TextEditingController group;
  final TextEditingController capabilities;
  final TextEditingController cpu;
  final TextEditingController ram;
  final TextEditingController concurrent;

  /// Null while adding: a new pool is always available.
  final bool? active;
  final ValueChanged<bool> onActiveChanged;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text(
        'Describe runners you already run, such as your self-hosted GitHub '
        'Actions runners. Your workflows still choose where they run; these '
        'limits cap what each workspace you grant them to may ask for.',
      ),
      IiOsGap.vMd,
      TextFormField(
        controller: name,
        decoration: const InputDecoration(
          labelText: 'Name',
          hintText: 'GPU runners',
        ),
        validator: _runnerNameValidator,
      ),
      IiOsGap.vSm,
      TextFormField(
        controller: group,
        decoration: const InputDecoration(
          labelText: 'Runner group',
          hintText: 'gpu-runners',
          helperText: 'The name your workflows use for these runners.',
        ),
        validator: _runnerGroupValidator,
      ),
      IiOsGap.vSm,
      TextFormField(
        controller: capabilities,
        decoration: const InputDecoration(
          labelText: 'Capabilities',
          hintText: 'runtime-docker, gpu.nvidia',
          helperText: 'Separate capabilities with commas.',
        ),
        validator: _capabilitiesValidator,
      ),
      IiOsGap.vSm,
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _PositiveNumberField(cpu, 'CPU cores')),
          IiOsGap.hSm,
          Expanded(child: _PositiveNumberField(ram, 'Memory (MiB)')),
          IiOsGap.hSm,
          Expanded(child: _PositiveNumberField(concurrent, 'Jobs at once')),
        ],
      ),
      if (active case final value?) ...[
        IiOsGap.vSm,
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: value,
          onChanged: onActiveChanged,
          title: const Text('Workspaces can use these runners'),
          subtitle: const Text(
            'Turn this off to stop workspaces starting new jobs on them.',
          ),
        ),
      ],
    ],
  );
}

class _PositiveNumberField extends StatelessWidget {
  const _PositiveNumberField(this.controller, this.label);

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(labelText: label),
    validator: _positiveIdValidator,
  );
}
