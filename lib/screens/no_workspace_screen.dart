import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/models.dart';
import '../state/app_controller.dart';
import '../theme/ii_os_tokens.dart';
import '../widgets/common.dart';
import '../widgets/invitation_dialogs.dart';

class NoWorkspaceScreen extends StatefulWidget {
  const NoWorkspaceScreen({required this.controller, super.key});

  final AppController controller;

  @override
  State<NoWorkspaceScreen> createState() => _NoWorkspaceScreenState();
}

class _NoWorkspaceScreenState extends State<NoWorkspaceScreen> {
  final _name = TextEditingController();
  String _environment = 'dev';
  String? _organizationId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final organizations = _creatableOrganizations;
    if (organizations.isNotEmpty) _organizationId = organizations.first.id;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final organizations = _creatableOrganizations;
    final belongsToOrganization =
        widget.controller.session!.organizations.isNotEmpty;
    final canCreate = organizations.isNotEmpty || !belongsToOrganization;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'ii-os',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => FirebaseAuth.instance.signOut(),
            icon: const Icon(LucideIcons.logOut, size: 17),
            label: const Text('Sign out'),
          ),
          IiOsGap.hXs,
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(IiOsSpacing.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(IiOsSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Create or join a workspace',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    IiOsGap.vXxs,
                    Text(
                      'Signed in as ${widget.controller.session!.user.email}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    IiOsGap.vLg,
                    if (organizations.isNotEmpty) ...[
                      DropdownButtonFormField<String>(
                        initialValue: _organizationId,
                        decoration: const InputDecoration(
                          labelText: 'Organization',
                        ),
                        items: [
                          for (final organization in organizations)
                            DropdownMenuItem(
                              value: organization.id,
                              child: Text(organization.name),
                            ),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) =>
                                  setState(() => _organizationId = value),
                      ),
                      IiOsGap.vXs,
                      Text(
                        'This workspace will use the organization\u2019s existing '
                        'GCP, GitHub, and Fleet connections. People still '
                        'need an '
                        'explicit grant to open it.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      IiOsGap.vSm,
                    ] else if (!belongsToOrganization) ...[
                      Text(
                        'Your first workspace also creates your organization. '
                        'Later workspaces can share its GCP, GitHub, and Fleet '
                        'connection.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      IiOsGap.vSm,
                    ] else ...[
                      Text(
                        'You belong to an organization, but your role cannot '
                        'create a workspace. Ask an organization owner or '
                        'admin for project access.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      IiOsGap.vSm,
                    ],
                    if (canCreate) ...[
                      TextField(
                        controller: _name,
                        decoration: const InputDecoration(
                          labelText: 'Workspace name',
                        ),
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
                      IiOsGap.vSm,
                      FilledButton.icon(
                        onPressed: _busy ? null : _create,
                        icon: const Icon(LucideIcons.plus, size: 18),
                        label: const Text('Create workspace'),
                      ),
                    ],
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 22),
                      child: Divider(),
                    ),
                    Text(
                      'Join an existing workspace',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    IiOsGap.vXxs,
                    Text(
                      'Invitations are tied to your verified sign-in email. '
                      'Use the account your workspace admin invited.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    IiOsGap.vSm,
                    FilledButton.icon(
                      onPressed: _busy ? null : _showInvitations,
                      icon: const Icon(LucideIcons.inbox, size: 18),
                      label: const Text('Review invitations'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _create() async {
    if (_name.text.trim().isEmpty) return;
    await _run(() async {
      await widget.controller.createWorkspace(
        _name.text.trim(),
        _environment,
        organizationId: _organizationId,
      );
    });
  }

  List<OrganizationAccess> get _creatableOrganizations => widget
      .controller
      .session!
      .organizations
      .where((organization) => organization.can('org.workspaces.create'))
      .toList(growable: false);

  Future<void> _showInvitations() async {
    await showInvitationAcceptanceDialog(
      context: context,
      signedInEmail: widget.controller.session!.user.email,
      onAccept: widget.controller.acceptInvitation,
      loadInvitations: widget.controller.listAvailableInvitations,
      onSwitchAccount: FirebaseAuth.instance.signOut,
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on Object catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
