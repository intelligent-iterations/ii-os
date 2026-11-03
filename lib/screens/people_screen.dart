import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:stacked/stacked.dart';

import '../models/models.dart';
import '../repositories/people_repository.dart';
import '../state/app_controller.dart';
import '../view_models/people_view_model.dart';
import '../view_models/workspace_access_view_model.dart';
import '../widgets/common.dart';
import '../widgets/people_directory.dart';

part 'people_dialogs.dart';
part 'people_access_dialogs.dart';
part 'people_permission_dialogs.dart';

class PeopleScreen extends StatelessWidget {
  const PeopleScreen({
    required this.controller,
    this.repository,
    this.onOrganizationDeleted,
    super.key,
  });

  final AppController controller;
  final PeopleRepository? repository;
  final Future<void> Function()? onOrganizationDeleted;

  @override
  Widget build(BuildContext context) {
    final organization = controller.session?.organizationFor(
      controller.workspace?.id,
    );
    if (organization == null) return const _NoPeopleOrganization();
    if (!organization.can('org.workspaces.access.manage')) {
      return _PeopleAccessRequired(organizationName: organization.name);
    }
    return _PeopleForOrganization(
      controller: controller,
      organization: organization,
      repository: repository ?? PeopleApiRepository(controller.api),
      onOrganizationDeleted: onOrganizationDeleted,
    );
  }
}

class _PeopleForOrganization extends StatelessWidget {
  const _PeopleForOrganization({
    required this.controller,
    required this.organization,
    required this.repository,
    required this.onOrganizationDeleted,
  });

  final AppController controller;
  final OrganizationAccess organization;
  final PeopleRepository repository;
  final Future<void> Function()? onOrganizationDeleted;

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<PeopleViewModel>.reactive(
      viewModelBuilder: () => PeopleViewModel(
        organizationId: organization.id,
        repository: repository,
      ),
      onViewModelReady: (model) => model.load(),
      builder: (context, model, _) => PageFrame(
        title: 'People',
        subtitle: '${organization.name} members and workspace access',
        actions: [
          if (organization.roleId == 'owner')
            OutlinedButton.icon(
              onPressed: model.deletingOrganization
                  ? null
                  : () => _deleteOrganization(context, model),
              icon: const Icon(LucideIcons.trash2, size: IiOsIconSize.md),
              label: Text(
                model.deletingOrganization
                    ? 'Deleting\u2026'
                    : 'Delete organization',
              ),
            ),
          OutlinedButton.icon(
            onPressed: model.isBusy ? null : model.load,
            icon: const Icon(LucideIcons.refreshCw, size: IiOsIconSize.md),
            label: const Text('Refresh'),
          ),
          FilledButton.icon(
            onPressed: !organization.can('org.members.manage') || model.inviting
                ? null
                : () => _invite(context, model),
            icon: model.inviting
                ? const SizedBox.square(
                    dimension: IiOsIconSize.md,
                    child: CircularProgressIndicator(
                      strokeWidth: IiOsSpacing.xxs / 2,
                    ),
                  )
                : const Icon(LucideIcons.userPlus, size: IiOsIconSize.md),
            label: Text(model.inviting ? 'Sending\u2026' : 'Invite person'),
          ),
        ],
        child: _PeopleBody(
          model: model,
          canInvite: organization.can('org.members.manage'),
          onManageAccess: (person) => _manageAccess(
            context,
            person,
            model.directory?.workspaces ?? const [],
            model.directory?.workspaceRoles ?? const [],
            model,
          ),
          onRevoke: (invitation) => _revoke(context, model, invitation),
        ),
      ),
    );
  }

  Future<void> _invite(BuildContext context, PeopleViewModel model) async {
    final directory = model.directory;
    if (directory == null) return;
    final draft = await showDialog<_OrganizationInviteDraft>(
      context: context,
      builder: (context) => _OrganizationInviteDialog(
        workspaces: directory.workspaces,
        currentWorkspaceId: controller.workspace?.id,
      ),
    );
    if (draft == null || !context.mounted) return;
    final feedback = await model.invite(
      email: draft.email,
      role: draft.role,
      workspaceIds: draft.workspaceIds,
    );
    if (feedback == null || !context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(feedback.message)));
  }

  Future<void> _manageAccess(
    BuildContext context,
    OrganizationPersonModel person,
    List<OrganizationWorkspaceModel> workspaces,
    List<PermissionRoleModel> workspaceRoles,
    PeopleViewModel peopleModel,
  ) async {
    final actorMemberships = <String, MembershipModel>{
      for (final access in controller.session?.workspaces ?? const [])
        if (access.workspace.organizationId == organization.id)
          access.workspace.id: access.membership,
    };
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => _PersonAccessDialog(
        organization: organization,
        person: person,
        workspaces: workspaces,
        workspaceRoles: workspaceRoles,
        actorWorkspaceMemberships: actorMemberships,
        repository: repository,
      ),
    );
    if (changed == true && context.mounted) {
      await peopleModel.load(quiet: true);
    }
  }

  Future<void> _deleteOrganization(
    BuildContext context,
    PeopleViewModel model,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) =>
          _DeleteOrganizationDialog(organizationName: organization.name),
    );
    if (confirmed != true || !context.mounted) return;
    if (!await model.deleteOrganization() || !context.mounted) return;
    await (onOrganizationDeleted ?? controller.refresh).call();
  }

  Future<void> _revoke(
    BuildContext context,
    PeopleViewModel model,
    OrganizationInvitationModel invitation,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revoke invitation?'),
        content: Text('${invitation.email} will no longer be able to join.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep invitation'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) await model.revoke(invitation.id);
  }
}

class _PeopleBody extends StatelessWidget {
  const _PeopleBody({
    required this.model,
    required this.canInvite,
    required this.onManageAccess,
    required this.onRevoke,
  });

  final PeopleViewModel model;
  final bool canInvite;
  final ValueChanged<OrganizationPersonModel> onManageAccess;
  final ValueChanged<OrganizationInvitationModel> onRevoke;

  @override
  Widget build(BuildContext context) {
    final directory = model.directory;
    if (model.isFirstLoad) {
      return const LoadingSurface(label: 'Loading organization people');
    }
    if (directory == null) {
      return ErrorSurface(
        title: 'People could not be loaded',
        message:
            model.errorMessage ?? 'The organization directory is unavailable.',
        onRetry: model.load,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (model.isBusy)
          const RefreshingStrip(label: 'Refreshing organization people\u2026'),
        if (!canInvite) ...[const _InvitePermissionNote(), IiOsGap.vMd],
        _PeopleSearch(onChanged: model.setQuery),
        InlineFormError(message: model.errorMessage),
        IiOsGap.vLg,
        PeopleDirectory(
          directory: directory,
          people: model.visiblePeople,
          onManageAccess: onManageAccess,
          onRevokeInvitation: canInvite ? onRevoke : null,
          isRevoking: model.revoking,
        ),
      ],
    );
  }
}

class _PeopleSearch extends StatelessWidget {
  const _PeopleSearch({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => TextField(
    onChanged: onChanged,
    keyboardType: TextInputType.emailAddress,
    decoration: const InputDecoration(
      labelText: 'Find a person',
      hintText: 'Search by email or organization role',
      prefixIcon: Icon(LucideIcons.search, size: IiOsIconSize.md),
    ),
  );
}

class _InvitePermissionNote extends StatelessWidget {
  const _InvitePermissionNote();

  @override
  Widget build(BuildContext context) => const Text(
    'You can assign existing people to workspaces. Ask an Organization Owner '
    'for People management access to send or revoke invitations.',
  );
}

class _NoPeopleOrganization extends StatelessWidget {
  const _NoPeopleOrganization();

  @override
  Widget build(BuildContext context) => const PageFrame(
    title: 'People',
    child: EmptyState(
      icon: LucideIcons.building2,
      title: 'No organization connected',
      message: 'Choose a workspace that belongs to an organization.',
    ),
  );
}

class _PeopleAccessRequired extends StatelessWidget {
  const _PeopleAccessRequired({required this.organizationName});

  final String organizationName;

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'People',
    subtitle: organizationName,
    child: const EmptyState(
      icon: LucideIcons.shieldAlert,
      title: 'Organization Admin access required',
      message: 'Ask an Organization Owner to manage workspace access for you.',
    ),
  );
}
