import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:stacked/stacked.dart';

import '../models/models.dart';
import '../models/data_plane_connection.dart';
import '../repositories/organization_repository.dart';
import '../state/app_controller.dart';
import '../view_models/organization_resources_view_model.dart';
import '../widgets/common.dart';
import '../widgets/data_plane_status.dart';
import 'organization_resources_dialogs.dart';

part 'organization_resources_widgets.dart';
part 'organization_runner_pools_card.dart';

class OrganizationResourcesScreen extends StatelessWidget {
  const OrganizationResourcesScreen({
    required this.controller,
    this.embedded = false,
    this.repository,
    super.key,
  });

  final AppController controller;
  final bool embedded;
  final OrganizationResourceRepository? repository;

  @override
  Widget build(BuildContext context) {
    final organization = controller.session!.organizationFor(
      controller.workspace!.id,
    )!;
    final legacySourceWorkspaceId = _legacySourceWorkspaceId(
      controller.session!.workspaces,
      organization.id,
    );
    return ViewModelBuilder<OrganizationResourcesViewModel>.reactive(
      viewModelBuilder: () => OrganizationResourcesViewModel(
        organization: organization,
        repository: repository ?? controller.organizations,
        onSaved: controller.refresh,
        legacySourceWorkspaceId: legacySourceWorkspaceId,
      ),
      builder: (context, model, _) => _OrganizationResourcesPage(
        organization: organization,
        model: model,
        embedded: embedded,
        onAddGcp: () => _addGcp(context, model),
        onAddRunner: () => _addRunner(context, model),
        onEditRunner: (pool) => _editRunner(context, model, pool),
        onSyncRunner: model.syncFleetRunnerPool,
        onPromoteLegacy: model.promoteLegacySetup,
      ),
    );
  }

  Future<void> _addGcp(
    BuildContext context,
    OrganizationResourcesViewModel model,
  ) async {
    final input = await showOrganizationGcpResourceDialog(
      context,
      organizationId: model.organization.id,
    );
    if (input != null) await model.addGcp(input);
  }

  Future<void> _addRunner(
    BuildContext context,
    OrganizationResourcesViewModel model,
  ) async {
    final input = await showOrganizationRunnerPoolDialog(context);
    if (input != null) await model.addCustomerRunner(input);
  }

  Future<void> _editRunner(
    BuildContext context,
    OrganizationResourcesViewModel model,
    OrganizationRunnerPoolModel pool,
  ) async {
    final input = await showOrganizationRunnerPoolDialog(
      context,
      existing: pool,
    );
    if (input != null) await model.updateCustomerRunner(pool, input);
  }
}

String _legacySourceWorkspaceId(
  List<WorkspaceAccess> workspaces,
  String organizationId,
) {
  for (final access in workspaces) {
    final workspace = access.workspace;
    final connection = workspace.connection;
    if (workspace.organizationId == organizationId &&
        connection != null &&
        !connection.isOrganizationBound &&
        connection.workspaceId == workspace.id) {
      return workspace.id;
    }
  }
  return '';
}
