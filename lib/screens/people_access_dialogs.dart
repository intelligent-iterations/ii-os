part of 'people_screen.dart';

class _PersonAccessDialog extends StatelessWidget {
  const _PersonAccessDialog({
    required this.organization,
    required this.person,
    required this.workspaces,
    required this.workspaceRoles,
    required this.actorWorkspaceMemberships,
    required this.repository,
  });

  final OrganizationAccess organization;
  final OrganizationPersonModel person;
  final List<OrganizationWorkspaceModel> workspaces;
  final List<PermissionRoleModel> workspaceRoles;
  final Map<String, MembershipModel> actorWorkspaceMemberships;
  final PeopleRepository repository;

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<WorkspaceAccessViewModel>.reactive(
      viewModelBuilder: () => WorkspaceAccessViewModel(
        organization: organization,
        person: person,
        workspaces: workspaces,
        actorWorkspaceMemberships: actorWorkspaceMemberships,
        repository: repository,
      ),
      onViewModelReady: (model) => model.load(),
      builder: (context, model, _) => AlertDialog(
        title: const Text('Edit person'),
        content: SizedBox(
          width: IiOsWidths.wideForm,
          height: IiOsWidths.form,
          child: _PersonAccessBody(
            model: model,
            workspaceRoles: workspaceRoles,
          ),
        ),
        actions: [
          TextButton(
            onPressed: model.hasChangesInFlight
                ? null
                : () => Navigator.pop(context, model.hasSavedChanges),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

class _PersonAccessBody extends StatefulWidget {
  const _PersonAccessBody({required this.model, required this.workspaceRoles});

  final WorkspaceAccessViewModel model;
  final List<PermissionRoleModel> workspaceRoles;

  @override
  State<_PersonAccessBody> createState() => _PersonAccessBodyState();
}

class _PersonAccessBodyState extends State<_PersonAccessBody> {
  late String _organizationRole = widget.model.organizationRole;

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    if (model.isBusy && !model.loaded) {
      return const LoadingSurface(label: 'Loading workspace access');
    }
    if (model.loadError != null) {
      return ErrorSurface(
        title: 'Workspace access could not be loaded',
        message: model.loadError!,
        onRetry: model.load,
      );
    }
    return ListView(
      children: [
        Text(model.person.email),
        IiOsGap.vMd,
        DropdownButtonFormField<String>(
          key: const Key('organization-role'),
          initialValue: _organizationRole,
          decoration: const InputDecoration(labelText: 'Organization role'),
          items: [
            const DropdownMenuItem(value: 'member', child: Text('Member')),
            const DropdownMenuItem(value: 'admin', child: Text('Admin')),
            if (model.organization.roleId == 'owner' ||
                model.organizationRole == 'owner')
              const DropdownMenuItem(value: 'owner', child: Text('Owner')),
          ],
          onChanged: model.canEditOrganization
              ? (value) => setState(() {
                  _organizationRole = value ?? model.organizationRole;
                })
              : null,
        ),
        IiOsGap.vSm,
        FilledButton(
          onPressed: !model.canEditOrganization || model.changingOrganization
              ? null
              : () => model.saveOrganizationRole(_organizationRole),
          child: Text(
            model.changingOrganization
                ? 'Saving\u2026'
                : 'Save organization role',
          ),
        ),
        InlineFormError(message: model.organizationError),
        IiOsGap.vLg,
        Text('Workspace access', style: Theme.of(context).textTheme.titleSmall),
        IiOsGap.vXxs,
        Text(
          'Changes take effect immediately. Each workspace has its own role and permissions.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        IiOsGap.vSm,
        if (model.workspaces.isEmpty)
          const Text('Create a workspace before assigning access.')
        else
          for (final workspace in model.workspaces)
            _WorkspaceAccessRow(
              model: model,
              workspace: workspace,
              workspaceRoles: widget.workspaceRoles,
            ),
        if (model.canRemovePerson) ...[
          IiOsGap.vLg,
          TextButton.icon(
            key: const Key('remove-from-organization'),
            onPressed: model.removingPerson
                ? null
                : () => _removePerson(context, model),
            icon: const Icon(LucideIcons.userRoundX, size: IiOsIconSize.md),
            label: Text(
              model.removingPerson
                  ? 'Removing\u2026'
                  : 'Remove from organization',
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _removePerson(
    BuildContext context,
    WorkspaceAccessViewModel model,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove from organization?'),
        content: Text(
          '${model.person.email} will also lose access to every workspace in this organization.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep person'),
          ),
          FilledButton(
            key: const Key('confirm-remove-person'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove person'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    if (await model.removePerson() && context.mounted) {
      Navigator.pop(context, true);
    }
  }
}

class _WorkspaceAccessRow extends StatelessWidget {
  const _WorkspaceAccessRow({
    required this.model,
    required this.workspace,
    required this.workspaceRoles,
  });

  final WorkspaceAccessViewModel model;
  final OrganizationWorkspaceModel workspace;
  final List<PermissionRoleModel> workspaceRoles;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SwitchListTile(
        key: Key('workspace-access-${workspace.id}'),
        contentPadding: EdgeInsets.zero,
        value: model.hasAccess(workspace.id),
        onChanged:
            !model.canChange(workspace.id) || model.changing(workspace.id)
            ? null
            : (enabled) => model.setAccess(workspace, enabled),
        title: Text(workspace.name),
        subtitle: _WorkspaceAccessDetails(
          role: model.roleFor(workspace.id),
          owner: model.assignmentFor(workspace.id)?.role == 'owner',
          message: model.messageFor(workspace.id),
          error: model.errorFor(workspace.id),
        ),
      ),
      Align(
        alignment: Alignment.centerRight,
        child: OutlinedButton.icon(
          key: Key('workspace-permissions-${workspace.id}'),
          onPressed:
              !model.canEditWorkspacePermissions(workspace.id) ||
                  model.changing(workspace.id)
              ? null
              : () => showDialog<void>(
                  context: context,
                  builder: (context) => _WorkspacePermissionsDialog(
                    model: model,
                    workspace: workspace,
                    workspaceRoles: workspaceRoles,
                  ),
                ),
          icon: const Icon(
            LucideIcons.slidersHorizontal,
            size: IiOsIconSize.sm,
          ),
          label: const Text('Edit permissions'),
        ),
      ),
      IiOsGap.vSm,
    ],
  );
}

class _WorkspaceAccessDetails extends StatelessWidget {
  const _WorkspaceAccessDetails({
    required this.role,
    required this.owner,
    required this.message,
    required this.error,
  });

  final String? role;
  final bool owner;
  final String? message;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    final detail = owner
        ? 'Workspace Owner \u2014 edit permissions to transfer ownership.'
        : message ?? error ?? role ?? 'Not assigned';
    return Text(
      detail,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: error == null ? palette.muted : palette.danger.text,
      ),
    );
  }
}
