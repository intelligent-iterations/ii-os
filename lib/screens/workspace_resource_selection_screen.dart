import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:stacked/stacked.dart';

import '../models/models.dart';
import '../repositories/organization_repository.dart';
import '../state/app_controller.dart';
import '../view_models/workspace_resources_view_model.dart';
import '../widgets/common.dart';

part 'workspace_resource_selection_widgets.dart';
part 'workspace_resource_selection_fields.dart';

class WorkspaceResourceSelectionScreen extends StatelessWidget {
  const WorkspaceResourceSelectionScreen({
    required this.controller,
    this.embedded = false,
    this.repository,
    this.onOpenWorkspaceSetup,
    super.key,
  });

  final AppController controller;
  final bool embedded;
  final OrganizationResourceRepository? repository;
  final VoidCallback? onOpenWorkspaceSetup;

  @override
  Widget build(BuildContext context) {
    final workspace = controller.workspace!;
    final organization = controller.session!.organizationFor(workspace.id)!;
    return ViewModelBuilder<WorkspaceResourcesViewModel>.reactive(
      key: ValueKey(workspace.id),
      viewModelBuilder: () => WorkspaceResourcesViewModel(
        organization: organization,
        workspace: workspace,
        canManage:
            controller.can('workspace.manage') ||
            organization.can('org.integrations.manage'),
        repository: repository ?? controller.organizations,
        onSaved: controller.workspaceResourceGrantsSaved,
      ),
      builder: (context, model, _) => _WorkspaceResourcesPage(
        model: model,
        embedded: embedded,
        onOpenWorkspaceSetup: onOpenWorkspaceSetup,
      ),
    );
  }
}
