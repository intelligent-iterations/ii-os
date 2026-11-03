part of 'people_screen.dart';

final class _OrganizationInviteDraft {
  const _OrganizationInviteDraft({
    required this.email,
    required this.role,
    required this.workspaceIds,
  });

  final String email;
  final String role;
  final List<String> workspaceIds;
}

class _OrganizationInviteDialog extends StatefulWidget {
  const _OrganizationInviteDialog({
    required this.workspaces,
    required this.currentWorkspaceId,
  });

  final List<OrganizationWorkspaceModel> workspaces;
  final String? currentWorkspaceId;

  @override
  State<_OrganizationInviteDialog> createState() =>
      _OrganizationInviteDialogState();
}

class _OrganizationInviteDialogState extends State<_OrganizationInviteDialog> {
  final _email = TextEditingController();
  final Set<String> _workspaceIds = {};
  String _role = 'member';
  String? _emailError;

  @override
  void initState() {
    super.initState();
    final current = widget.currentWorkspaceId;
    if (current != null &&
        widget.workspaces.any((item) => item.id == current)) {
      _workspaceIds.add(current);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Invite a person'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: IiOsWidths.wideForm),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'They will receive an email invitation. Choose the workspaces '
                'they should see as soon as they join.',
              ),
              IiOsGap.vMd,
              TextField(
                key: const Key('organization-invite-email'),
                controller: _email,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: InputDecoration(
                  labelText: 'Email address',
                  hintText: 'name@company.com',
                  errorText: _emailError,
                ),
              ),
              IiOsGap.vMd,
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(
                  labelText: 'Organization role',
                ),
                items: const [
                  DropdownMenuItem(value: 'member', child: Text('Member')),
                  DropdownMenuItem(value: 'admin', child: Text('Admin')),
                ],
                onChanged: (value) => setState(() {
                  _role = value ?? 'member';
                }),
              ),
              IiOsGap.vLg,
              Text(
                'Workspace access',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              IiOsGap.vXxs,
              Text(
                _workspaceIds.isEmpty
                    ? 'No workspace selected. They will join the organization only.'
                    : '${_workspaceIds.length} selected',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              IiOsGap.vXs,
              for (final workspace in widget.workspaces)
                CheckboxListTile(
                  key: Key('invite-workspace-${workspace.id}'),
                  contentPadding: EdgeInsets.zero,
                  value: _workspaceIds.contains(workspace.id),
                  title: Text(workspace.name),
                  subtitle: Text(workspace.environment.toUpperCase()),
                  onChanged: (selected) => setState(() {
                    if (selected == true) {
                      _workspaceIds.add(workspace.id);
                    } else {
                      _workspaceIds.remove(workspace.id);
                    }
                  }),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Send invitation')),
      ],
    );
  }

  void _submit() {
    final email = _email.text.trim().toLowerCase();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() => _emailError = 'Enter a valid email address.');
      return;
    }
    Navigator.pop(
      context,
      _OrganizationInviteDraft(
        email: email,
        role: _role,
        workspaceIds: _workspaceIds.toList(growable: false),
      ),
    );
  }
}
