part of 'organization_resources_dialogs.dart';

class _RunnerPoolDialog extends StatefulWidget {
  const _RunnerPoolDialog();

  @override
  State<_RunnerPoolDialog> createState() => _RunnerPoolDialogState();
}

class _RunnerPoolDialogState extends State<_RunnerPoolDialog> {
  final _form = GlobalKey<FormState>();
  final _id = TextEditingController();
  final _name = TextEditingController();
  final _providerPoolId = TextEditingController();
  final _capabilities = TextEditingController();
  final _cpu = TextEditingController();
  final _ram = TextEditingController();
  final _concurrent = TextEditingController();
  String _provider = 'fleet';

  @override
  void dispose() {
    _id.dispose();
    _name.dispose();
    _providerPoolId.dispose();
    _capabilities.dispose();
    _cpu.dispose();
    _ram.dispose();
    _concurrent.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add organization runner pool'),
    content: SizedBox(
      width: IiOsWidths.wideForm,
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: _RunnerPoolFields(
            id: _id,
            name: _name,
            providerPoolId: _providerPoolId,
            capabilities: _capabilities,
            cpu: _cpu,
            ram: _ram,
            concurrent: _concurrent,
            provider: _provider,
            onProviderChanged: (value) => setState(() => _provider = value),
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Add runner pool')),
    ],
  );

  void _submit() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      OrganizationRunnerPoolDraft(
        id: _id.text.trim(),
        name: _name.text.trim(),
        provider: _provider,
        providerPoolId: _providerPoolId.text.trim(),
        capabilities: _capabilities.text
            .split(',')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toSet(),
        maxCpu: int.parse(_cpu.text.trim()),
        maxRamMiB: int.parse(_ram.text.trim()),
        maxConcurrent: int.parse(_concurrent.text.trim()),
      ),
    );
  }
}

class _RunnerPoolFields extends StatelessWidget {
  const _RunnerPoolFields({
    required this.id,
    required this.name,
    required this.providerPoolId,
    required this.capabilities,
    required this.cpu,
    required this.ram,
    required this.concurrent,
    required this.provider,
    required this.onProviderChanged,
  });

  final TextEditingController id;
  final TextEditingController name;
  final TextEditingController providerPoolId;
  final TextEditingController capabilities;
  final TextEditingController cpu;
  final TextEditingController ram;
  final TextEditingController concurrent;
  final String provider;
  final ValueChanged<String> onProviderChanged;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text(
        'Runner pools describe Fleet-managed or customer capacity. This does '
        'not enable GitHub-hosted runner spending.',
      ),
      IiOsGap.vMd,
      TextFormField(
        controller: id,
        decoration: const InputDecoration(
          labelText: 'Resource ID',
          hintText: 'runner_gpu',
        ),
        validator: _idValidator,
      ),
      IiOsGap.vSm,
      TextFormField(
        controller: name,
        decoration: const InputDecoration(labelText: 'Display name'),
        validator: _nameValidator,
      ),
      IiOsGap.vSm,
      TextFormField(
        controller: providerPoolId,
        decoration: const InputDecoration(
          labelText: 'Provider pool ID',
          hintText: 'personal-alice',
          helperText: 'Exact Fleet pool used for placement; never a host ID.',
        ),
        validator: _nameValidator,
      ),
      IiOsGap.vSm,
      DropdownButtonFormField<String>(
        initialValue: provider,
        decoration: const InputDecoration(labelText: 'Provider'),
        items: const [
          DropdownMenuItem(value: 'fleet', child: Text('Fleet')),
          DropdownMenuItem(value: 'customer', child: Text('Customer')),
        ],
        onChanged: (value) {
          if (value != null) onProviderChanged(value);
        },
      ),
      IiOsGap.vSm,
      TextFormField(
        controller: capabilities,
        decoration: const InputDecoration(
          labelText: 'Capabilities (comma separated)',
          hintText: 'docker, gpu.nvidia',
        ),
        validator: _nameValidator,
      ),
      IiOsGap.vSm,
      Row(
        children: [
          Expanded(child: _PositiveNumberField(cpu, 'Max CPU')),
          IiOsGap.hSm,
          Expanded(child: _PositiveNumberField(ram, 'Max RAM MiB')),
          IiOsGap.hSm,
          Expanded(child: _PositiveNumberField(concurrent, 'Concurrent')),
        ],
      ),
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
