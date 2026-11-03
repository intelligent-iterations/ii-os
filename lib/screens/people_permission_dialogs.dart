part of 'people_screen.dart';

class _WorkspacePermissionsDialog extends StatefulWidget {
  const _WorkspacePermissionsDialog({
    required this.model,
    required this.workspace,
    required this.workspaceRoles,
  });

  final WorkspaceAccessViewModel model;
  final OrganizationWorkspaceModel workspace;
  final List<PermissionRoleModel> workspaceRoles;

  @override
  State<_WorkspacePermissionsDialog> createState() =>
      _WorkspacePermissionsDialogState();
}

class _WorkspacePermissionsDialogState
    extends State<_WorkspacePermissionsDialog> {
  late String _role = widget.model.assignmentFor(widget.workspace.id)!.role;
  late Set<String> _claims = _initialClaims();
  bool _saving = false;

  Set<String> _initialClaims() {
    final assignment = widget.model.assignmentFor(widget.workspace.id)!;
    return {
      ...(assignment.role == 'owner'
          ? assignment.effectiveCapabilities
          : assignment.featureClaims),
    };
  }

  List<PermissionRoleModel> get _roles => widget.workspaceRoles
      .where(
        (role) =>
            role.id != 'owner' ||
            widget.model.canAssignWorkspaceOwner(widget.workspace.id),
      )
      .toList(growable: false);

  PermissionRoleModel get _selectedRole =>
      _roles.firstWhere((role) => role.id == _role, orElse: () => _roles.first);

  @override
  Widget build(BuildContext context) {
    final selected = _selectedRole;
    final grantable = widget.model.grantableCapabilities(
      widget.workspace.id,
      selected,
    );
    return AlertDialog(
      title: Text('${widget.workspace.name} permissions'),
      content: SizedBox(
        width: IiOsWidths.wideForm,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'This role and its selected permissions apply only to ${widget.workspace.name}.',
              ),
              IiOsGap.vMd,
              DropdownButtonFormField<String>(
                key: Key('workspace-role-${widget.workspace.id}'),
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Workspace role'),
                items: [
                  for (final role in _roles)
                    DropdownMenuItem(value: role.id, child: Text(role.label)),
                ],
                onChanged: _saving ? null : _onRoleChanged,
              ),
              IiOsGap.vMd,
              Text(
                'Permissions',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              IiOsGap.vXxs,
              Text(
                'You can grant only permissions you hold in this workspace.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              IiOsGap.vXs,
              for (final capability in selected.capabilities)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _claims.contains(capability.id),
                  title: Text(capability.label),
                  onChanged: !_saving && grantable.contains(capability.id)
                      ? (checked) => _onClaimChanged(capability.id, checked)
                      : null,
                ),
              InlineFormError(
                message: widget.model.errorFor(widget.workspace.id),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving\u2026' : 'Save permissions'),
        ),
      ],
    );
  }

  void _onRoleChanged(String? value) => setState(() {
    _role = value ?? _role;
    _claims = widget.model.grantableCapabilities(
      widget.workspace.id,
      _selectedRole,
    );
  });

  void _onClaimChanged(String capabilityId, bool? checked) => setState(() {
    if (checked == true) {
      _claims.add(capabilityId);
    } else {
      _claims.remove(capabilityId);
    }
  });

  Future<void> _save() async {
    setState(() => _saving = true);
    final saved = await widget.model.saveWorkspacePermissions(
      widget.workspace,
      role: _role,
      featureClaims: _claims,
    );
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() => _saving = false);
    }
  }
}

class _DeleteOrganizationDialog extends StatefulWidget {
  const _DeleteOrganizationDialog({required this.organizationName});

  final String organizationName;

  @override
  State<_DeleteOrganizationDialog> createState() =>
      _DeleteOrganizationDialogState();
}

class _DeleteOrganizationDialogState extends State<_DeleteOrganizationDialog> {
  final _confirmation = TextEditingController();

  @override
  void dispose() {
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Delete organization?'),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: IiOsWidths.wideForm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Every person will be removed from ${widget.organizationName}. '
            'Its ii-os workspaces and access records will be deleted. External '
            'cloud resources, generated media, and provider accounts are not deleted.',
          ),
          IiOsGap.vMd,
          Text('Type ${widget.organizationName} to confirm.'),
          IiOsGap.vXs,
          TextField(
            key: const Key('delete-organization-name'),
            controller: _confirmation,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Organization name'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Keep organization'),
      ),
      FilledButton(
        key: const Key('confirm-delete-organization'),
        onPressed: _confirmation.text == widget.organizationName
            ? () => Navigator.pop(context, true)
            : null,
        child: const Text('Delete organization'),
      ),
    ],
  );
}
