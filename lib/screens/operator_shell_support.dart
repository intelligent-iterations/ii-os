part of 'operator_shell.dart';

/// Whether the signed-in person holds [capability] at the tenant tier.
///
/// Tenant-tier access is a different question from project access, and no
/// project role implies an organization capability -- so this reads the
/// organization membership rather than the workspace one.
bool _canInOrganization(AppController controller, String capability) =>
    controller.session
        ?.organizationFor(controller.workspace?.id)
        ?.can(capability) ??
    false;

Future<void> _confirmLeaveWorkspace(
  BuildContext context,
  AppController controller,
) async {
  final workspaceName = controller.workspace?.name ?? 'this workspace';
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Leave workspace?'),
      content: Text(
        'You will lose access to $workspaceName. An owner or admin must invite you again to restore access.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Leave workspace'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await controller.leaveCurrentWorkspace();
  } on Object catch (error) {
    if (context.mounted) showFailure(context, error);
  }
}

Future<void> _confirmDeleteWorkspace(
  BuildContext context,
  AppController controller,
) async {
  final workspaceName = controller.workspace?.name ?? 'this workspace';
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete workspace?'),
      content: Text(
        'This removes $workspaceName from ii-os. It does not delete customer buckets, GitHub Apps, secrets, or generated media. Delete is allowed only when no other members remain.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete workspace'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await controller.deleteCurrentWorkspace();
  } on Object catch (error) {
    if (context.mounted) showFailure(context, error);
  }
}

@visibleForTesting
class OperatorNavigation extends StatefulWidget {
  const OperatorNavigation({
    super.key,
    required this.controller,
    required this.page,
    required this.onSelect,
    this.itemId,
    this.expanded = true,
  });

  final AppController controller;
  final AppPage page;

  /// The route's current resource id.
  ///
  /// Production lines all share one [AppPage], so the page alone cannot say
  /// which entry is selected -- without this every line would highlight at once.
  final String? itemId;

  final void Function(AppPage page, {String? itemId}) onSelect;
  final bool expanded;

  @override
  State<OperatorNavigation> createState() => _NavigationState();
}

class _NavigationState extends State<OperatorNavigation> {
  final Set<String> _collapsedSections = <String>{};

  /// A collapsed rail needs the label; an expanded one already shows it. An
  /// entry needing attention always explains why, since the badge alone is a
  /// shape with no words.
  String _tooltip(_NavItem item, {required bool expanded}) {
    final attention = item.attention;
    if (attention != null) return '${item.label} \u2014 $attention';
    return expanded ? '' : item.label;
  }

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    final controller = widget.controller;
    final page = widget.page;
    final expanded = widget.expanded;
    final sections = <_NavSection>[
      _NavSection('Development', LucideIcons.code2, [
        const _NavItem(
          AppPage.githubSetup,
          'GitHub setup',
          LucideIcons.gitBranch,
        ),
        if (controller.can('tickets.read'))
          const _NavItem(
            AppPage.tickets,
            'Software Workshop',
            LucideIcons.hammer,
          ),
        if (controller.can('agent.permissions.read'))
          const _NavItem(
            AppPage.agentPermissions,
            'Agent permissions',
            LucideIcons.shieldCheck,
          ),
        if (controller.can('audit.read'))
          const _NavItem(
            AppPage.agentUsage,
            'Agent usage',
            LucideIcons.chartNoAxesColumnIncreasing,
          ),
        if (controller.can('jobs.read'))
          const _NavItem(AppPage.jobs, 'Jobs', LucideIcons.activity),
        if (controller.can('interactive.sessions.read'))
          const _NavItem(
            AppPage.terminalSessions,
            'Terminal sessions',
            LucideIcons.squareTerminal,
          ),
      ]),
      if (controller.can('lines.read') && controller.productionLines.isNotEmpty)
        _NavSection('Production Lines', LucideIcons.factory, [
          for (final line in controller.productionLines.lines)
            _NavItem.line(
              line,
              attention: controller.productionLines.attentionFor(line),
            ),
        ]),
      if (controller.can('jobs.trigger') || controller.can('jobs.read'))
        // Each generation tool is its own page rather than a tab inside one.
        // As tabs they were unreachable from the rail, invisible when the tab
        // strip overflowed on a phone, and stranded without their strip when
        // opened by URL.
        _NavSection('Creative', LucideIcons.palette, [
          if (controller.can('jobs.trigger')) ...[
            const _NavItem(
              AppPage.generate,
              'Create images',
              LucideIcons.image,
            ),
            const _NavItem(AppPage.imageEdit, 'Edit images', LucideIcons.brush),
            const _NavItem(
              AppPage.videoGeneration,
              'Video',
              LucideIcons.clapperboard,
            ),
            const _NavItem(
              AppPage.videoEditor,
              'Video editor',
              LucideIcons.film,
            ),
            const _NavItem(
              AppPage.songGeneration,
              'Music',
              LucideIcons.audioLines,
            ),
            const _NavItem(AppPage.narration, 'Narration', LucideIcons.mic2),
          ],
          if (controller.can('jobs.read') || controller.can('jobs.trigger'))
            const _NavItem(
              AppPage.history,
              'Asset library',
              LucideIcons.images,
            ),
          if (controller.can('jobs.read') || controller.can('jobs.trigger'))
            const _NavItem(
              AppPage.storyboards,
              'Storyboards',
              LucideIcons.panelsTopLeft,
            ),
          if (controller.can('characters.read'))
            const _NavItem(
              AppPage.characters,
              'Characters',
              LucideIcons.scanFace,
            ),
        ]),
      _NavSection('Account', LucideIcons.userRound, [
        const _NavItem(AppPage.home, 'Home', LucideIcons.layoutDashboard),
        if (controller.can('workspace.manage'))
          const _NavItem(
            AppPage.projectAdmin,
            'Workspace setup',
            LucideIcons.settings2,
          ),
        if (controller.can('workspace.manage') ||
            _canInOrganization(controller, 'org.integrations.manage'))
          const _NavItem(
            AppPage.workspaceResources,
            'Workspace access',
            LucideIcons.shieldCheck,
          ),
        if (_canInOrganization(controller, 'org.integrations.manage') ||
            _canInOrganization(controller, 'org.runners.manage'))
          const _NavItem(
            AppPage.organizationResources,
            'Organization resources',
            LucideIcons.building2,
          ),
        if (controller.can('members.manage') ||
            _canInOrganization(controller, 'org.workspaces.access.manage'))
          const _NavItem(AppPage.people, 'People', LucideIcons.users),
        if (_canInOrganization(controller, 'org.audit.read'))
          const _NavItem(AppPage.fleet, 'Infrastructure', LucideIcons.server),
      ]),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        IiOsSpacing.xs,
        IiOsSpacing.sm,
        IiOsSpacing.xs,
        IiOsSpacing.md,
      ),
      children: [
        for (final section in sections) ...[
          if (expanded)
            InkWell(
              borderRadius: BorderRadius.circular(5),
              onTap: () => setState(() {
                if (!_collapsedSections.add(section.label)) {
                  _collapsedSections.remove(section.label);
                }
              }),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
                child: Row(
                  children: [
                    Icon(section.icon, size: 15, color: palette.muted),
                    IiOsGap.hXs,
                    Expanded(
                      child: Text(
                        section.label.toUpperCase(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: palette.muted,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    Icon(
                      _collapsedSections.contains(section.label)
                          ? LucideIcons.chevronRight
                          : LucideIcons.chevronDown,
                      size: 15,
                      color: palette.muted,
                    ),
                  ],
                ),
              ),
            )
          else
            IiOsGap.vXs,
          if (!expanded || !_collapsedSections.contains(section.label))
            for (final item in section.items)
              Tooltip(
                message: _tooltip(item, expanded: expanded),
                child: IiOsSelectionRail(
                  // A tinted pill alone reads as hover on a list of thirteen.
                  // The rail is what makes the current destination findable
                  // without reading every label.
                  selected:
                      page == item.page &&
                      (item.itemId == null || item.itemId == widget.itemId),
                  color: palette.brand.text,
                  child: ListTile(
                    dense: true,
                    minTileHeight: 44,
                    // A fixed destination matches on page alone; one resource
                    // among many must also match its id, or every production
                    // line would render selected at the same time.
                    selected:
                        page == item.page &&
                        (item.itemId == null || item.itemId == widget.itemId),
                    selectedTileColor: palette.brand.container,
                    selectedColor: palette.brand.text,
                    shape: const RoundedRectangleBorder(
                      borderRadius: IiOsRadii.lgAll,
                    ),
                    // The identity glyph sets its colour on the Icon itself, so
                    // selectedColor above cannot repaint it green exactly when
                    // the operator is standing in that line.
                    leading: item.hasIdentity
                        ? IiOsIdentityGlyph(
                            colorToken: item.colorToken,
                            iconToken: item.iconToken,
                            needsAttention: item.attention != null,
                          )
                        : Icon(item.icon, size: 19),
                    title: expanded
                        ? Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        : null,
                    onTap: () =>
                        widget.onSelect(item.page, itemId: item.itemId),
                  ),
                ),
              ),
        ],
        IiOsGap.vSm,
        if (expanded) ...[
          const Divider(),
          IiOsGap.vSm,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: IiOsSpacing.sm),
            child: Row(
              children: [
                Icon(LucideIcons.shieldCheck, size: 16, color: palette.muted),
                IiOsGap.hXs,
                Expanded(
                  child: Text(
                    controller.membership!.roleLabel,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

final class _NavSection {
  const _NavSection(this.label, this.icon, this.items);

  final String label;
  final IconData icon;
  final List<_NavItem> items;
}

final class _NavItem {
  const _NavItem(this.page, this.label, this.icon)
    : itemId = null,
      colorToken = null,
      iconToken = null,
      attention = null;

  /// A production line: one nav entry per line, all sharing one [AppPage] and
  /// told apart by [itemId].
  _NavItem.line(ProductionLineModel line, {this.attention})
    : page = AppPage.productionLine,
      label = line.name,
      icon = LucideIcons.factory,
      itemId = line.id,
      colorToken = line.colorToken,
      iconToken = line.iconToken;

  final AppPage page;
  final String label;
  final IconData icon;

  /// Null for a fixed destination, set for one resource among many.
  final String? itemId;

  /// Identity tokens, when this entry carries one. See `IiOsIdentity`.
  final String? colorToken;
  final String? iconToken;

  /// Why this entry needs attention, or null when it is healthy.
  final String? attention;

  bool get hasIdentity => colorToken != null || iconToken != null;
}

class _AppBar extends StatelessWidget implements PreferredSizeWidget {
  const _AppBar({
    required this.controller,
    required this.currentRoute,
    required this.notifications,
    required this.onOpenNotification,
    required this.onWorkspaceSelected,
    required this.onCreateWorkspace,
    required this.onMenu,
  });

  final AppController controller;
  final String currentRoute;
  final GenerationNotificationService notifications;
  final ValueChanged<String> onOpenNotification;
  final ValueChanged<String> onWorkspaceSelected;
  final VoidCallback onCreateWorkspace;
  final VoidCallback onMenu;

  @override
  Size get preferredSize => const Size.fromHeight(58);

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    final workspace = controller.workspace!;
    final organization = controller.session?.organizationFor(workspace.id);
    final canCreateWorkspace =
        organization?.can('org.workspaces.create') ?? false;
    final compact = MediaQuery.sizeOf(context).width < 600;
    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      shape: Border(bottom: BorderSide(color: palette.border)),
      leading: IconButton(
        tooltip: 'Menu',
        onPressed: onMenu,
        icon: const Icon(LucideIcons.menu, size: 20),
      ),
      titleSpacing: 4,
      title: compact
          ? const IiOsAppTitle()
          : Row(
              children: [
                const IiOsAppTitle(),
                const SizedBox(width: 18),
                Flexible(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: workspace.id,
                      isDense: true,
                      borderRadius: BorderRadius.circular(IiOsRadii.md),
                      items: controller.session!.workspaces
                          .map(
                            (access) => DropdownMenuItem(
                              value: access.workspace.id,
                              child: Text(
                                access.workspace.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) onWorkspaceSelected(value);
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                StatusPill(workspace.environment),
              ],
            ),
      actions: [
        NotificationBell(service: notifications, onOpen: onOpenNotification),
        if (canCreateWorkspace)
          IconButton(
            tooltip: 'Create workspace in ${organization!.name}',
            onPressed: onCreateWorkspace,
            icon: const Icon(LucideIcons.plus, size: 18),
          ),
        if (compact)
          PopupMenuButton<String>(
            tooltip: 'Switch workspace',
            icon: const Icon(LucideIcons.building2, size: 18),
            initialValue: workspace.id,
            onSelected: onWorkspaceSelected,
            itemBuilder: (context) => controller.session!.workspaces
                .map(
                  (access) => PopupMenuItem(
                    value: access.workspace.id,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            access.workspace.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IiOsGap.hSm,
                        StatusPill(access.workspace.environment),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        if (!compact)
          IconButton(
            tooltip: 'Refresh',
            onPressed: controller.refreshing ? null : controller.refresh,
            icon: controller.refreshing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(LucideIcons.refreshCw, size: 18),
          ),
        Builder(
          builder: (context) {
            final appearance = AppearanceScope.maybeOf(context);
            if (appearance == null) return const SizedBox.shrink();
            return AppearanceToggle(
              brightness: Theme.of(context).brightness,
              compact: compact,
              onChanged: (target) => appearance.setMode(
                target == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
              ),
            );
          },
        ),
        BugReportButton(
          compact: compact,
          currentRoute: currentRoute,
          onSubmit: (draft) => BugReportClient(
            controller.api,
          ).submit(workspaceId: workspace.id, draft: draft),
        ),
        PopupMenuButton<String>(
          tooltip: 'Account: ${controller.session!.user.email}',
          onSelected: (value) async {
            if (value == 'refresh') {
              await controller.refresh();
              return;
            }
            if (value == 'invite') {
              await showInvitationAcceptanceDialog(
                context: context,
                signedInEmail: controller.session!.user.email,
                onAccept: controller.acceptInvitation,
                loadInvitations: controller.listAvailableInvitations,
                onSwitchAccount: FirebaseAuth.instance.signOut,
              );
              return;
            }
            if (value == 'leave') {
              await _confirmLeaveWorkspace(context, controller);
              return;
            }
            if (value == 'delete') {
              await _confirmDeleteWorkspace(context, controller);
              return;
            }
            if (value == 'signout') await FirebaseAuth.instance.signOut();
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              enabled: false,
              child: Text(
                controller.session!.user.email,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const PopupMenuDivider(),
            if (compact)
              const PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(LucideIcons.refreshCw, size: 17),
                    SizedBox(width: 10),
                    Text('Refresh'),
                  ],
                ),
              ),
            const PopupMenuItem(
              value: 'invite',
              child: Row(
                children: [
                  Icon(LucideIcons.mailCheck, size: 17),
                  SizedBox(width: 10),
                  Text('Invitations'),
                ],
              ),
            ),
            if (controller.membership?.role != 'owner')
              const PopupMenuItem(
                value: 'leave',
                child: Row(
                  children: [
                    Icon(LucideIcons.logOut, size: 17),
                    SizedBox(width: 10),
                    Text('Leave workspace'),
                  ],
                ),
              ),
            if (controller.membership?.role == 'owner')
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(LucideIcons.trash2, size: 17),
                    SizedBox(width: 10),
                    Text('Delete workspace'),
                  ],
                ),
              ),
            const PopupMenuItem(value: 'signout', child: Text('Sign out')),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: CircleAvatar(
              radius: 15,
              backgroundColor: palette.charcoal,
              child: Text(
                _initials(controller.session!.user.displayName),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String _initials(String value) {
  final parts = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty);
  final result = parts.take(2).map((part) => part[0].toUpperCase()).join();
  return result.isEmpty ? 'II' : result;
}
