import 'package:flutter/material.dart';

import '../repositories/github_project_repository.dart';
import '../state/app_controller.dart';
import 'project_admin_screen.dart';

enum ProjectAdminTab {
  settings('settings', 'Setup');

  const ProjectAdminTab(this.slug, this.label);

  final String slug;
  final String label;

  static ProjectAdminTab parse(String? value) => values.firstWhere(
    (tab) => tab.slug == value,
    orElse: () => ProjectAdminTab.settings,
  );

  /// The route query value; the default tab keeps the URL clean.
  String? get query => this == ProjectAdminTab.settings ? null : slug;
}

class ProjectAdminPage extends StatelessWidget {
  const ProjectAdminPage({
    required this.controller,
    required this.tab,
    required this.onTabChanged,
    this.onManageOrganizationResources,
    this.onManageWorkspaceAccess,
    this.onOpenGitHubSetup,
    this.githubProjects,
    super.key,
  });

  final AppController controller;
  final ProjectAdminTab tab;
  final ValueChanged<ProjectAdminTab> onTabChanged;
  final VoidCallback? onManageOrganizationResources;
  final VoidCallback? onManageWorkspaceAccess;
  final VoidCallback? onOpenGitHubSetup;
  final GitHubProjectRepository? githubProjects;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      if (ProjectAdminTab.values.length > 1)
        _ProjectAdminTabs(selected: tab, onChanged: onTabChanged),
    ];
    return switch (tab) {
      ProjectAdminTab.settings => ProjectAdminScreen(
        controller: controller,
        pageActions: tabs,
        onManageOrganizationResources: onManageOrganizationResources,
        onManageWorkspaceAccess: onManageWorkspaceAccess,
        onOpenGitHubSetup: onOpenGitHubSetup,
        githubProjects: githubProjects,
      ),
    };
  }
}

class _ProjectAdminTabs extends StatelessWidget {
  const _ProjectAdminTabs({required this.selected, required this.onChanged});

  final ProjectAdminTab selected;
  final ValueChanged<ProjectAdminTab> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<ProjectAdminTab>(
    segments: [
      for (final tab in ProjectAdminTab.values)
        ButtonSegment(value: tab, label: Text(tab.label)),
    ],
    selected: {selected},
    onSelectionChanged: (selection) => onChanged(selection.single),
  );
}
