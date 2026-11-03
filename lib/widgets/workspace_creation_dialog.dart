import 'package:flutter/material.dart';

import '../models/organization_access.dart';
import '../theme/ii_os_tokens.dart';

final class WorkspaceCreationRequest {
  const WorkspaceCreationRequest({
    required this.name,
    required this.environment,
  });

  final String name;
  final String environment;
}

Future<WorkspaceCreationRequest?> showWorkspaceCreationDialog({
  required BuildContext context,
  required OrganizationAccess organization,
}) {
  return showDialog<WorkspaceCreationRequest>(
    context: context,
    builder: (context) =>
        _WorkspaceCreationDialog(organizationName: organization.name),
  );
}

class _WorkspaceCreationDialog extends StatefulWidget {
  const _WorkspaceCreationDialog({required this.organizationName});

  final String organizationName;

  @override
  State<_WorkspaceCreationDialog> createState() =>
      _WorkspaceCreationDialogState();
}

class _WorkspaceCreationDialogState extends State<_WorkspaceCreationDialog> {
  final _name = TextEditingController();
  String _environment = 'dev';

  @override
  void initState() {
    super.initState();
    _name.addListener(_nameChanged);
  }

  @override
  void dispose() {
    _name
      ..removeListener(_nameChanged)
      ..dispose();
    super.dispose();
  }

  void _nameChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New workspace'),
      content: SizedBox(
        width: IiOsBreakpoints.compact,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Create a project inside ${widget.organizationName}. It starts '
              'with no cloud, GitHub, or runner access; an Organization Admin '
              'or Workspace Admin selects its subset after creation.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            IiOsGap.vMd,
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Workspace name'),
              onSubmitted: (_) => _submit(),
            ),
            IiOsGap.vSm,
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'dev', label: Text('Dev')),
                ButtonSegment(value: 'prod', label: Text('Prod')),
              ],
              selected: {_environment},
              onSelectionChanged: (value) =>
                  setState(() => _environment = value.first),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _name.text.trim().isEmpty ? null : _submit,
          child: const Text('Create workspace'),
        ),
      ],
    );
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(
      context,
      WorkspaceCreationRequest(name: name, environment: _environment),
    );
  }
}
