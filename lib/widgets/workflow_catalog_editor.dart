import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:stacked/stacked.dart';

import '../repositories/workflow_catalog_repository.dart';
import '../state/app_controller.dart';
import '../view_models/workflow_catalog_view_model.dart';
import 'common.dart';

part 'workflow_catalog_editor_body.dart';
part 'workflow_catalog_editor_content.dart';

class WorkflowCatalogEditor extends StatelessWidget {
  const WorkflowCatalogEditor({
    required this.controller,
    required this.selected,
    required this.onChanged,
    this.onManageWorkspaceAccess,
    this.repository,
    super.key,
  });

  final AppController controller;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;
  final VoidCallback? onManageWorkspaceAccess;
  final WorkflowCatalogRepository? repository;

  @override
  Widget build(BuildContext context) {
    final workspace = controller.workspace!;
    return ViewModelBuilder<WorkflowCatalogViewModel>.reactive(
      key: ValueKey(workspace.id),
      viewModelBuilder: () => WorkflowCatalogViewModel(
        workspaceId: workspace.id,
        repository: repository ?? WorkflowCatalogApiRepository(controller.api),
      ),
      onViewModelReady: (model) => model.start(),
      builder: (context, model, _) => _WorkflowCatalogBody(
        model: model,
        selected: selected,
        hasRepositories: workspace.repositories.isNotEmpty,
        onChanged: onChanged,
        onManageWorkspaceAccess: onManageWorkspaceAccess,
      ),
    );
  }
}
